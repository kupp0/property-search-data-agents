import os
import json
import requests
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv
import google.auth
from google.cloud import storage
import asyncpg
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy import text
import logging
import sys
import re
from typing import List, Optional, Any
from sqlalchemy import text, bindparam

# ==============================================================================
# LOGGING CONFIGURATION
# ==============================================================================
# Configure JSON-style logging for production
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)
# ==============================================================================
# CONFIGURATION & INITIALIZATION
# ==============================================================================

# Load environment variables from .env file
backend_dir = os.path.dirname(os.path.abspath(__file__))
dotenv_path = os.path.join(backend_dir, '.env')
load_dotenv(dotenv_path=dotenv_path)

app = FastAPI(title="AlloyDB Property Search Demo")

# Configure CORS
# In production, this should be restricted to specific domains.
ALLOWED_ORIGINS_STR = os.getenv("ALLOWED_ORIGINS", "*")
ALLOWED_ORIGINS = [origin.strip() for origin in ALLOWED_ORIGINS_STR.split(",") if origin.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Google Cloud Clients
storage_client = None
PROJECT_ID = os.getenv("GCP_PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT")
AGENT_CONTEXT_SET_ID = os.getenv("AGENT_CONTEXT_SET_ID")

# Configure allowed GCS bucket for image serving to prevent SSRF
GCS_BUCKET_NAME = os.getenv("GCS_BUCKET_NAME")
if not GCS_BUCKET_NAME and PROJECT_ID:
    GCS_BUCKET_NAME = f"property-images-{PROJECT_ID}"

try:
    # Initialize credentials with Cloud Platform scope
    credentials, _ = google.auth.default(
        scopes=['https://www.googleapis.com/auth/cloud-platform']
    )
    
    # Initialize Storage Client for image serving
    storage_client = storage.Client(project=PROJECT_ID, credentials=credentials)
    print("Google Cloud Storage client initialized successfully.")
    
except Exception as e:
    print(f"Warning: Google Cloud initialization failed. Image serving may not work.\nError: {e}")

# AlloyDB Configuration
# AlloyDB Configuration
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
DB_NAME = os.environ.get("DB_NAME", "search")

if not DB_PASSWORD:
    logger.warning("DB_PASSWORD environment variable is not set. Database connection may fail if password is required.")

# Global DB Engine
engine = None

async def get_engine():
    global engine
    if engine:
        return engine

    if not DB_HOST:
        raise ValueError("DB_HOST environment variable is not set.")

    logger.info(f"Connecting to AlloyDB via Auth Proxy at {DB_HOST}...")
    db_url = f"postgresql+asyncpg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}"
    engine = create_async_engine(db_url)
    return engine

@app.on_event("shutdown")
async def shutdown_event():
    global engine
    if engine:
        await engine.dispose()
        logger.info("Database engine disposed.")

# ==============================================================================
# DATA MODELS
# ==============================================================================

class SearchRequest(BaseModel):
    query: str

class FilterCondition(BaseModel):
    column: str
    operator: str
    value: Any
    logic: str = "AND"

class HistoryRequest(BaseModel):
    # Deprecated: where_clause (unsafe), prefer filters
    where_clause: Optional[str] = None
    filters: List[FilterCondition] = []

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

def query_gda(prompt: str) -> dict:
    """
    Queries the Gemini Data Agent (GDA) API to get property listings and natural language answers.
    
    This function sends the user's prompt to the GDA API, which translates it into a SQL query,
    executes it against the AlloyDB database, and returns the results along with a natural language summary.
    """
    if not AGENT_CONTEXT_SET_ID:
        raise HTTPException(500, "AGENT_CONTEXT_SET_ID is not configured.")
    
    # GDA API Endpoint
    gda_location = os.getenv("GCP_LOCATION", "europe-west1")
    url = f"https://geminidataanalytics.googleapis.com/v1beta/projects/{PROJECT_ID}/locations/{gda_location}:queryData"
    
    # Obtain credentials for the API request
    scopes = ['https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/userinfo.email']
    creds, _ = google.auth.default(scopes=scopes)
    if not creds.valid:
        creds.refresh(google.auth.transport.requests.Request())
    
    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json"
    }
    
    # Construct the GDA API payload
    payload = {
        "parent": f"projects/{PROJECT_ID}/locations/{gda_location}",
        "prompt": prompt,
        "context": {
            "datasourceReferences": {
                "alloydb": {
                    "databaseReference": {
                        "project_id": PROJECT_ID,
                        "region": os.getenv("ALLOYDB_REGION", gda_location),
                        "cluster_id": os.getenv("ALLOYDB_CLUSTER_ID", "search-cluster"),
                        "instance_id": os.getenv("ALLOYDB_INSTANCE_ID", "search-primary"),
                        "database_id": os.getenv("ALLOYDB_DATABASE_ID", "search")
                    },
                    "agentContextReference": {
                        "context_set_id": AGENT_CONTEXT_SET_ID
                    }
                }
            }
        },
        "generation_options": {
            "generate_query_result": True,
            "generate_natural_language_answer": True,
            "generate_explanation": True
        }
    }
    
    try:
        logger.info(f"Sending request to GDA API: {url}")
        resp = requests.post(url, headers=headers, data=json.dumps(payload))
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        logger.error(f"GDA API Request Failed: {e}")
        if hasattr(e, 'response') and e.response:
             logger.error(f"GDA Error Response: {e.response.text}")
        raise HTTPException(500, f"Failed to query Gemini Data Agent: {e}")

# ==============================================================================
# API ENDPOINTS
# ==============================================================================

@app.get("/api/image")
async def get_image(gcs_uri: str):
    """
    Serves images from Google Cloud Storage (GCS).
    
    This endpoint acts as a secure proxy, allowing the frontend to display images
    from a private GCS bucket without exposing the bucket publicly.
    It attempts to generate a signed URL for direct access (efficient) or streams
    the file content if signing fails.
    """
    if not storage_client:
        raise HTTPException(500, "Storage client is not initialized.")

    try:
        # Parse the GCS URI to extract bucket and blob names
        if gcs_uri.startswith("gs://"):
            path = gcs_uri[5:]
        elif gcs_uri.startswith("https://storage.googleapis.com/"):
            path = gcs_uri[31:]
        else:
            raise HTTPException(400, "Invalid GCS URI format.")
            
        if "/" not in path:
             raise HTTPException(400, "Invalid GCS URI: Missing object path.")

        bucket_name, blob_name = path.split("/", 1)

        # Security Check: Ensure we are accessing the allowed bucket
        if GCS_BUCKET_NAME and bucket_name != GCS_BUCKET_NAME:
            logger.warning(f"Blocked access to unauthorized bucket: {bucket_name}")
            raise HTTPException(400, "Invalid GCS bucket.")

        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        
        # Method 1: Generate a Signed URL (Preferred for performance)
        try:
            signed_url = blob.generate_signed_url(
                version="v4",
                expiration=3600, # URL valid for 1 hour
                method="GET"
            )
            return RedirectResponse(
                url=signed_url, 
                status_code=307,
                headers={"Cache-Control": "public, max-age=300"}
            )
        except Exception as sign_err:
            # Method 2: Stream content (Fallback)
            logger.warning(f"Signed URL generation failed, falling back to streaming: {sign_err}")
            file_obj = blob.open("rb")
            return StreamingResponse(
                file_obj, 
                media_type="image/jpeg", 
                headers={"Cache-Control": "public, max-age=86400"}
            )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error serving image: {e}")
        raise HTTPException(404, "Image not found or inaccessible.")

@app.post("/api/search")
async def search_properties(request: SearchRequest):
    """
    Handles property search requests using the Gemini Data Agent.
    
    Accepts a natural language query, sends it to GDA, and returns:
    1. A list of property listings.
    2. The generated SQL query.
    3. A natural language answer.
    4. An explanation of the reasoning (if available).
    """
    logger.info(f"Processing search query: '{request.query}'")
    
    try:
        # Query the Gemini Data Agent
        gda_resp = query_gda(request.query)
        
        # Extract components from the response
        nl_answer = gda_resp.get("naturalLanguageAnswer", "")
        query_result = gda_resp.get("queryResult", {})
        rows = query_result.get("rows", [])
        cols = query_result.get("columns", [])
        
        # Process rows into a list of dictionaries
        results = []
        if rows and cols:
            col_names = [c["name"] for c in cols]
            for row in rows:
                values = row.get("values", [])
                
                # Flatten the response structure:
                # GDA returns values as {"value": "actual_value"}, we extract "actual_value".
                # We also filter out large embedding fields to reduce payload size.
                item = {
                    k: (v["value"] if isinstance(v, dict) and "value" in v else v)
                    for k, v in zip(col_names, values)
                    if k not in ("description_embedding", "image_embedding")
                }
                
                # Update image URIs to use the local proxy endpoint
                # This prevents mixed content warnings and handles auth
                if item.get("image_gcs_uri"):
                    item["image_gcs_uri"] = f"/api/image?gcs_uri={item['image_gcs_uri']}"
                
                results.append(item)
        
        # Construct the System Output for the UI
        generated_sql = gda_resp.get("generatedQuery") or gda_resp.get("queryResult", {}).get("query", "SQL not returned by GDA")
        explanation = gda_resp.get('intentExplanation', '')
        total_row_count = gda_resp.get("queryResult", {}).get("totalRowCount", "0")
        
        # Create a preview of the raw query results (first 3 rows)
        query_result_preview = {
            "columns": cols,
            "rows": rows[:3] if rows else []
        }
        
        display_sql = f"// GEMINI DATA AGENT CALL\n// Generated SQL: {generated_sql}\n// Answer: {nl_answer}"
        if explanation:
            display_sql += f"\n// Explanation: {explanation}"
        
        # Log to Database
        try:
            db_engine = await get_engine()
            async with db_engine.begin() as conn:
                # Determine template usage
                query_template_used = False
                query_template_id = None
                
                if explanation:
                    # Look for "Template X" pattern in the explanation
                    match = re.search(r"Template\s+(\d+)", explanation, re.IGNORECASE)
                    if match:
                        query_template_used = True
                        query_template_id = int(match.group(1))
                
                await conn.execute(
                    text("""
                    INSERT INTO user_prompt_history 
                    (user_prompt, query_template_used, query_template_id, query_explanation)
                    VALUES (:prompt, :used, :id, :explanation)
                    """),
                    {
                        "prompt": request.query, 
                        "used": query_template_used, 
                        "id": query_template_id,
                        "explanation": explanation
                    }
                )

            logger.info("User prompt history saved (Search).")
        except Exception as db_err:
            logger.error(f"Failed to save user prompt history (Search): {db_err}")

        return {
            "listings": results, 
            "sql": display_sql, 
            "nl_answer": nl_answer,
            "details": {
                "generated_query": generated_sql,
                "intent_explanation": explanation,
                "total_row_count": total_row_count,
                "query_result_preview": query_result_preview
            }
        }

    except Exception as e:
        logger.error(f"Search failed: {e}")
        return {
            "listings": [], 
            "sql": f"An error occurred during search: {str(e)}",
            "nl_answer": "I encountered an error while processing your request."
        }

@app.post("/api/history")
async def get_history(request: HistoryRequest):
    """
    Retrieves user prompt history using direct DB connection.
    Supports structured filtering to prevent SQL injection.
    """
    try:
        db_engine = await get_engine()
        async with db_engine.connect() as conn:
            base_query = """
                SELECT user_prompt, query_template_used, query_template_id, query_explanation 
                FROM "public"."user_prompt_history"
            """
            
            conditions = []
            params = {}
            
            # Handle legacy where_clause (only if simple/safe or warn)
            if request.where_clause:
                logger.warning("Usage of unsafe 'where_clause' in history API. This field is deprecated.")
                # For now, we DO NOT append it blindly to avoid SQLi, unless we are sure.
                # Or we can just ignore it and rely on filters.
                # Let's try to be backward compatible ONLY if it's empty or simple?
                # Actually, for security audit, we MUST disable raw injection.
                # We will ignore it or throw error if it contains dangerous keywords?
                # Safest: Ignore it and log warning, or return error.
                # Let's return error to force frontend update if it's being used.
                pass 

            # Handle structured filters
            ALLOWED_COLUMNS = {"user_prompt", "query_template_used", "query_template_id", "query_explanation"}
            ALLOWED_OPERATORS = {"=", "!=", "LIKE", "ILIKE", ">", "<", ">=", "<="}
            
            query_str = base_query
            first_condition = True

            if request.filters:
                for idx, f in enumerate(request.filters):
                    if f.column not in ALLOWED_COLUMNS:
                        continue # Skip invalid columns
                    if f.operator not in ALLOWED_OPERATORS:
                        continue # Skip invalid operators
                    
                    param_name = f"p{idx}"
                    
                    # Handle type casting for integer/boolean columns when using string operators
                    column_expr = f.column
                    if f.column in ("query_template_id", "query_template_used") and f.operator.upper() in ("LIKE", "ILIKE"):
                        column_expr = f"CAST({f.column} AS TEXT)"
                        
                    clause = f"{column_expr} {f.operator} :{param_name}"
                    params[param_name] = f.value
                    
                    if first_condition:
                        query_str += f" WHERE {clause}"
                        first_condition = False
                    else:
                        logic_op = f.logic.upper()
                        if logic_op not in ("AND", "OR"):
                            logic_op = "AND"
                        query_str += f" {logic_op} {clause}"

            query_str += " LIMIT 1000"
            
            result = await conn.execute(text(query_str), params)
            rows = [dict(row) for row in result.mappings()]
            
        return {"rows": rows}
        
    except Exception as e:
        logger.error(f"History fetch failed: {e}")
        raise HTTPException(500, f"Failed to fetch history: {e}")
