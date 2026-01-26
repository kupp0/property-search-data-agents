import os
import requests
import google.auth
import google.auth.transport.requests
import google.oauth2.credentials
import json

# Configuration
PROJECT_ID = os.getenv("PROJECT_ID", "ai-powered-search-alloydb-1542")
# Note: Context Set location might differ from GDA location, but usually they should align or be accessible.
# Keeping europe-west4 for context set as per original script, but making it configurable.
CONTEXT_LOCATION = os.getenv("CONTEXT_LOCATION", "us-east1")
AGENT_CONTEXT_SET_ID = f"projects/{PROJECT_ID}/locations/{CONTEXT_LOCATION}/contextSets/property-agent"
GDA_LOCATION = os.getenv("GDA_LOCATION", "europe-west1")

def query_gda(prompt):
    url = f"https://geminidataanalytics.googleapis.com/v1beta/projects/{PROJECT_ID}/locations/{GDA_LOCATION}:queryData"
    
    # Get credentials
    access_token = os.getenv("ACCESS_TOKEN")
    if access_token:
        print("Using provided ACCESS_TOKEN")
        creds = google.oauth2.credentials.Credentials(token=access_token)
    else:
        creds, project = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
        if not creds.valid:
            creds.refresh(google.auth.transport.requests.Request())
    
    print(f"Creds: {creds.service_account_email if hasattr(creds, 'service_account_email') else 'User/Token Creds'}")

    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "parent": f"projects/{PROJECT_ID}/locations/{GDA_LOCATION}",
        "prompt": prompt,
        "context": {
            "datasourceReferences": {
                "alloydb": {
                    "databaseReference": {
                        "project_id": PROJECT_ID,
                        "region": "europe-west1",
                        "cluster_id": "search-cluster",
                        "instance_id": "search-primary",
                        "database_id": "search"
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
    
    print(f"Sending request to {url}")
    print(json.dumps(payload, indent=2))
    
    try:
        resp = requests.post(url, headers=headers, json=payload)
        print(f"Status: {resp.status_code}")
        print(resp.text)
        resp.raise_for_status()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    query_gda("show me Lovely Mountain Cabins under 15k")
