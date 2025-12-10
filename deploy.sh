#!/bin/bash

# Exit on error
set -e

# Ensure we are in the script's directory
cd "$(dirname "$0")"

# Configuration
if [ -f "backend/.env" ]; then
    echo "📄 Loading configuration from backend/.env..."
    export $(grep -v '^#' backend/.env | xargs)
else
    echo "❌ backend/.env not found. Please run ./setup_env.sh first."
    exit 1
fi

PROJECT_ID=${GCP_PROJECT_ID}
REGION=${GCP_LOCATION}

if [ -z "$PROJECT_ID" ]; then
    echo "❌ GCP_PROJECT_ID not found in backend/.env"
    exit 1
fi

if [ -z "$REGION" ]; then
    echo "❌ GCP_LOCATION not found in backend/.env"
    exit 1
fi
BACKEND_SERVICE_NAME="search-backend"
FRONTEND_SERVICE_NAME="search-frontend"

# Ensure required variables are set
if [ -z "$INSTANCE_CONNECTION_NAME" ]; then
    echo "❌ Missing required configuration in backend/.env"
    exit 1
fi

# Password check
if [ -z "$DB_PASSWORD" ]; then
    read -s -p "Enter DB Password: " DB_PASSWORD
    echo ""
fi

echo "🚀 Starting Deployment to Cloud Run..."
echo "Project: $PROJECT_ID"
echo "Region: $REGION"

# --- PERMISSION CHECK ---
check_permissions() {
    echo "🔍 Checking permissions..."
    CURRENT_USER=$(gcloud config get-value account)
    echo "User: $CURRENT_USER"

    # Check if user has Owner, Editor, or Artifact Registry Writer roles
    # This is a heuristic check. 
    ROLES=$(gcloud projects get-iam-policy $PROJECT_ID \
        --flatten="bindings[].members" \
        --format="table(bindings.role)" \
        --filter="bindings.members:$CURRENT_USER")

    if echo "$ROLES" | grep -qE "roles/owner|roles/editor|roles/artifactregistry.writer|roles/artifactregistry.repoAdmin|roles/artifactregistry.admin"; then
        echo "✅ User has sufficient Artifact Registry permissions."
    else
        echo "❌ ERROR: User '$CURRENT_USER' is missing Artifact Registry permissions."
        echo "Required: roles/artifactregistry.writer OR roles/owner OR roles/editor"
        echo "Current Roles:"
        echo "$ROLES"
        echo ""
        echo "To fix this, ask an admin to run:"
        echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "    --member='user:$CURRENT_USER' \\"
        echo "    --role='roles/artifactregistry.writer'"
        echo ""
        echo "Exiting..."
        exit 1
    fi
    
}

check_service_account_permissions() {
    echo "🔍 Checking Build Service Account permissions..."
    PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
    # Cloud Build often uses the Compute Engine default service account by default in some configs,
    # or the Cloud Build Service Account. The error message specifically mentioned the Compute SA.
    # UPDATE: We are now using a dedicated SA: search-backend-sa
    COMPUTE_SA="search-backend-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "Checking Dedicated Service Account: $COMPUTE_SA"

    echo "ℹ️  Note: Builds submitted via gcloud often use this Service Account."
    echo "It needs 'roles/logging.logWriter' and 'roles/artifactregistry.writer'."
    
    # Check if we can see the policy (heuristic)
    SA_ROLES=$(gcloud projects get-iam-policy $PROJECT_ID \
        --flatten="bindings[].members" \
        --format="table(bindings.role)" \
        --filter="bindings.members:$COMPUTE_SA")

    if echo "$SA_ROLES" | grep -q "roles/logging.logWriter" && \
       echo "$SA_ROLES" | grep -q "roles/artifactregistry.repoAdmin" && \
       echo "$SA_ROLES" | grep -q "roles/alloydb.client" && \
       echo "$SA_ROLES" | grep -q "roles/serviceusage.serviceUsageConsumer"; then
        echo "✅ Service Account appears to have necessary roles."
    else
        echo "⚠️  WARNING: Service Account '$COMPUTE_SA' might be missing roles."
        echo "Current Roles:"
        echo "$SA_ROLES"
        echo ""
        echo "To fix the 'Permission denied' errors, run:"
        echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "    --member='serviceAccount:$COMPUTE_SA' \\"
        echo "    --role='roles/logging.logWriter'"
        echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "    --member='serviceAccount:$COMPUTE_SA' \\"
        echo "    --role='roles/artifactregistry.repoAdmin'"
        echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "    --member='serviceAccount:$COMPUTE_SA' \\"
        echo "    --role='roles/alloydb.client'"
        echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "    --member='serviceAccount:$COMPUTE_SA' \\"
        echo "    --role='roles/serviceusage.serviceUsageConsumer'"

        echo ""
        echo "You can copy and run the above commands manually."
        echo "Exiting to prevent build/runtime failure..."
        exit 1
    fi
}

check_permissions
check_service_account_permissions

# --- ENSURE REPO EXISTS ---
# Sometimes createOnPush fails even with permissions due to propagation delays.
# It's safer to ensure the repo exists explicitly.
echo "🔍 Checking/Creating Artifact Registry repository..."
# Use a standard Artifact Registry repo in the user's region.
REPO_NAME="search-app-repo"
REPO_URI="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME"

echo "📦 Switching to Artifact Registry: $REPO_URI"
if ! gcloud artifacts repositories describe $REPO_NAME --location=$REGION >/dev/null 2>&1; then
    echo "Creating Artifact Registry repository '$REPO_NAME'..."
    gcloud artifacts repositories create $REPO_NAME \
        --project=$PROJECT_ID \
        --repository-format=docker \
        --location=$REGION \
        --description="Docker repository for Search App"
else
    echo "✅ Repository '$REPO_NAME' already exists."
fi

# Update Image URIs to use the new Artifact Registry with a unique tag
TAG=$(date +%Y%m%d-%H%M%S)
echo "🏷️  Using Image Tag: $TAG"
BACKEND_IMAGE="$REPO_URI/$BACKEND_SERVICE_NAME:$TAG"
FRONTEND_IMAGE="$REPO_URI/$FRONTEND_SERVICE_NAME:$TAG"


# 1. Build and Push Backend Image
echo "📦 Building Backend Image..."
gcloud builds submit backend --tag $BACKEND_IMAGE --project=$PROJECT_ID

# 2. Deploy Backend with AlloyDB Auth Proxy Sidecar
echo "🚀 Deploying Backend..."
# We use the Dedicated Service Account for the runtime identity
SERVICE_ACCOUNT="search-backend-sa@${PROJECT_ID}.iam.gserviceaccount.com"
echo "Using Runtime Service Account: $SERVICE_ACCOUNT"

# Substitute variables in service.yaml
# BACKEND_IMAGE is already set to the new AR URI
export BACKEND_IMAGE
export SERVICE_ACCOUNT
export PROJECT_ID
export REGION
export DB_USER
export DB_NAME
export DB_PASSWORD
export INSTANCE_CONNECTION_NAME
export VERTEX_AI_SEARCH_DATA_STORE_ID


envsubst < backend/service.yaml > backend/service.resolved.yaml

gcloud run services replace backend/service.resolved.yaml --region $REGION --project=$PROJECT_ID

# Allow unauthenticated access (for demo purposes)
# Allow current user access (Org Policy restricts allUsers)
gcloud run services add-iam-policy-binding $BACKEND_SERVICE_NAME \
    --region $REGION \
    --member="user:$CURRENT_USER" \
    --role="roles/run.invoker"

# Get Backend URL
BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "✅ Backend deployed at: $BACKEND_URL"

# 3. Build and Push Toolbox Image
echo "📦 Building Toolbox Image..."
TOOLBOX_SERVICE_NAME="search-toolbox"
TOOLBOX_IMAGE="$REPO_URI/$TOOLBOX_SERVICE_NAME:$TAG"
gcloud builds submit backend/mcp_server --tag $TOOLBOX_IMAGE --project=$PROJECT_ID

# 4. Deploy Toolbox
echo "🚀 Deploying Toolbox..."
export TOOLBOX_IMAGE
envsubst < backend/mcp_server/service.yaml > backend/mcp_server/service.resolved.yaml
gcloud run services replace backend/mcp_server/service.resolved.yaml --region $REGION --project=$PROJECT_ID

# Allow unauthenticated access (internal/demo) - or restrict if needed
# For simplicity in this demo, we allow unauthenticated so Agent can call it easily without ID token logic
# Allow current user access
gcloud run services add-iam-policy-binding $TOOLBOX_SERVICE_NAME \
    --region $REGION \
    --member="user:$CURRENT_USER" \
    --role="roles/run.invoker"

TOOLBOX_URL=$(gcloud run services describe $TOOLBOX_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "✅ Toolbox deployed at: $TOOLBOX_URL"

# 5. Build and Push Agent Image
echo "📦 Building Agent Image..."
AGENT_SERVICE_NAME="search-agent"
AGENT_IMAGE="$REPO_URI/$AGENT_SERVICE_NAME:$TAG"
gcloud builds submit backend/agent --tag $AGENT_IMAGE --project=$PROJECT_ID

# 6. Deploy Agent
echo "🚀 Deploying Agent..."
export AGENT_IMAGE
export TOOLBOX_URL
envsubst < backend/agent/service.yaml > backend/agent/service.resolved.yaml
gcloud run services replace backend/agent/service.resolved.yaml --region $REGION --project=$PROJECT_ID

gcloud run services add-iam-policy-binding $AGENT_SERVICE_NAME \
    --region $REGION \
    --member="user:$CURRENT_USER" \
    --role="roles/run.invoker"

AGENT_URL=$(gcloud run services describe $AGENT_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "✅ Agent deployed at: $AGENT_URL"


# 7. Build and Push Frontend Image
echo "📦 Building Frontend Image..."
gcloud builds submit frontend --tag $FRONTEND_IMAGE --project=$PROJECT_ID

# 4. Deploy Frontend
echo "🚀 Deploying Frontend..."
gcloud run deploy $FRONTEND_SERVICE_NAME \
    --image $FRONTEND_IMAGE \
    --region $REGION \
    --platform managed \
    --project=$PROJECT_ID \
    --no-allow-unauthenticated \
    --set-env-vars BACKEND_URL=$BACKEND_URL,AGENT_URL=$AGENT_URL

# Get Frontend URL
FRONTEND_URL=$(gcloud run services describe $FRONTEND_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "🎉 Deployment Complete!"
echo "Frontend: $FRONTEND_URL"
