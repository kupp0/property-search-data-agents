#!/bin/bash

# Exit on error
set -e

# Configuration
if [ -f "backend/.env" ]; then
    echo "📄 Loading configuration from backend/.env..."
    export $(grep -v '^#' backend/.env | xargs)
else
    echo "❌ backend/.env not found. Please run ./setup_env.sh first."
    exit 1
fi

PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project)}
REGION=${GCP_LOCATION:-"europe-west1"}
BACKEND_SERVICE_NAME="search-backend"
FRONTEND_SERVICE_NAME="search-frontend"

# Ensure required variables are set
if [ -z "$INSTANCE_CONNECTION_NAME" ] || [ -z "$VERTEX_SEARCH_DATA_STORE_ID" ]; then
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
    COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
    echo "Build Service Account: $COMPUTE_SA"

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
       echo "$SA_ROLES" | grep -q "roles/serviceusage.serviceUsageConsumer" && \
       echo "$SA_ROLES" | grep -q "roles/discoveryengine.editor"; then
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
        echo "gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "    --member='serviceAccount:$COMPUTE_SA' \\"
        echo "    --role='roles/discoveryengine.editor'"
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
# gcr.io repositories are actually hosted in Artifact Registry now for new projects.
# We'll try to create it if it doesn't exist.
# Note: 'gcr.io' is a special multi-region location.
# However, for Cloud Build to push to gcr.io/$PROJECT_ID, the underlying repo must exist.
# We can try to enable the API and let it handle it, or just rely on the user having repoAdmin.
# If the user has repoAdmin, we can try to run a command to create it, but gcr.io is legacy-mapped.

# Alternative: Use a standard Artifact Registry repo instead of gcr.io to avoid this legacy mess.
# Let's switch to a modern Artifact Registry repo in the user's region.
REPO_NAME="search-app-repo"
REPO_URI="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME"

echo "📦 Switching to Artifact Registry: $REPO_URI"
if ! gcloud artifacts repositories describe $REPO_NAME --location=$REGION >/dev/null 2>&1; then
    echo "Creating Artifact Registry repository '$REPO_NAME'..."
    gcloud artifacts repositories create $REPO_NAME \
        --repository-format=docker \
        --location=$REGION \
        --description="Docker repository for Search App"
else
    echo "✅ Repository '$REPO_NAME' already exists."
fi

# Update Image URIs to use the new Artifact Registry
BACKEND_IMAGE="$REPO_URI/$BACKEND_SERVICE_NAME"
FRONTEND_IMAGE="$REPO_URI/$FRONTEND_SERVICE_NAME"


# 1. Build and Push Backend Image
echo "📦 Building Backend Image..."
gcloud builds submit backend --tag $BACKEND_IMAGE

# 2. Deploy Backend with AlloyDB Auth Proxy Sidecar
echo "🚀 Deploying Backend..."
# Get current service account
# SERVICE_ACCOUNT=$(gcloud config get-value account) # This is the USER account, not valid for Cloud Run runtime
# We should use the Default Compute Service Account for the runtime identity
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
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
export VERTEX_SEARCH_DATA_STORE_ID

envsubst < backend/service.yaml > backend/service.resolved.yaml

gcloud run services replace backend/service.resolved.yaml --region $REGION

# Allow unauthenticated access (for demo purposes)
gcloud run services add-iam-policy-binding $BACKEND_SERVICE_NAME \
    --region $REGION \
    --member="allUsers" \
    --role="roles/run.invoker"

# Get Backend URL
BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "✅ Backend deployed at: $BACKEND_URL"

# 3. Build and Push Frontend Image
echo "📦 Building Frontend Image..."
gcloud builds submit frontend --tag $FRONTEND_IMAGE

# 4. Deploy Frontend
echo "🚀 Deploying Frontend..."
gcloud run deploy $FRONTEND_SERVICE_NAME \
    --image $FRONTEND_IMAGE \
    --region $REGION \
    --platform managed \
    --allow-unauthenticated \
    --set-env-vars BACKEND_URL=$BACKEND_URL

# Get Frontend URL
FRONTEND_URL=$(gcloud run services describe $FRONTEND_SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "🎉 Deployment Complete!"
echo "Frontend: $FRONTEND_URL"
