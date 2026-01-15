#!/bin/bash
set -e

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"
echo "📂 Project Root: $PROJECT_ROOT"

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Source .env if it exists
if [ -f "backend/.env" ]; then
    echo "📄 Sourcing backend/.env..."
    set -o allexport
    source backend/.env
    set +o allexport
fi

export PROJECT_ID=$(gcloud config get-value project)
export GCP_LOCATION=${GCP_LOCATION:-europe-west1}
export REGION=$GCP_LOCATION

# Default AlloyDB Config (can be overridden by .env)
export ALLOYDB_REGION=${ALLOYDB_REGION:-$REGION}
export ALLOYDB_CLUSTER_ID=${ALLOYDB_CLUSTER_ID:-search-cluster}
export ALLOYDB_INSTANCE_ID=${ALLOYDB_INSTANCE_ID:-search-primary}
export ALLOYDB_DATABASE_ID=${ALLOYDB_DATABASE_ID:-search}
export DB_PASS=${DB_PASS:-Welcome01}
REPO_NAME="search-app-repo"

# Service Names
export BACKEND_SERVICE="data-agent-search-backend"
FRONTEND_SERVICE="data-agent-search-frontend"
export AGENT_SERVICE="data-agent-service"
TOOLBOX_SERVICE="data-agent-toolbox"

# Images
export BACKEND_IMAGE="europe-west1-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${BACKEND_SERVICE}"
FRONTEND_IMAGE="europe-west1-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${FRONTEND_SERVICE}"
export AGENT_IMAGE="europe-west1-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${AGENT_SERVICE}"
TOOLBOX_IMAGE="europe-west1-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${TOOLBOX_SERVICE}"

export TAG=$(date +%Y%m%d-%H%M%S)

echo "🚀 Starting Deployment to Cloud Run..."
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"

# Check for AGENT_CONTEXT_SET_ID
if [ -z "${AGENT_CONTEXT_SET_ID}" ]; then
    echo "⚠️  AGENT_CONTEXT_SET_ID is not set!"
    echo "Please set it in backend/.env or export it before running this script."
    exit 1
fi

# ==============================================================================
# 1. BUILD & PUSH IMAGES (PARALLEL)
# ==============================================================================

echo "📦 Starting Parallel Builds..."
PIDS=""

# --- MCP SERVER (TOOLBOX) ---
(
    echo "📦 [Toolbox] Preparing..."
    # Generate resolved tools configuration
    envsubst < backend/mcp_server/tools.yaml > backend/mcp_server/tools_resolved.yaml
    # Create temporary Dockerfile for deployment
    cp backend/mcp_server/Dockerfile backend/mcp_server/Dockerfile.deploy
    sed -i 's/tools.yaml/tools_resolved.yaml/g' backend/mcp_server/Dockerfile.deploy

    # Create temporary Cloud Build config
    cat > backend/mcp_server/cloudbuild_deploy.yaml <<'EOF'
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-f', 'Dockerfile.deploy', '-t', '${_IMAGE_NAME}:${_TAG}', '.']
images:
- '${_IMAGE_NAME}:${_TAG}'
EOF

    echo "📦 [Toolbox] Building Image..."
    gcloud builds submit ./backend/mcp_server \
        --config=backend/mcp_server/cloudbuild_deploy.yaml \
        --substitutions=_IMAGE_NAME=${TOOLBOX_IMAGE},_TAG=${TAG} > /dev/null 2>&1

    # Cleanup temporary files
    rm backend/mcp_server/tools_resolved.yaml backend/mcp_server/Dockerfile.deploy backend/mcp_server/cloudbuild_deploy.yaml
    echo "✅ [Toolbox] Build Complete"
) &
PIDS="$PIDS $!"

# --- AGENT ---
(
    echo "📦 [Agent] Building Image..."
    gcloud builds submit ./backend/agent --tag ${AGENT_IMAGE}:${TAG} > /dev/null 2>&1
    echo "✅ [Agent] Build Complete"
) &
PIDS="$PIDS $!"

# --- BACKEND ---
(
    echo "📦 [Backend] Building Image..."
    gcloud builds submit ./backend --tag ${BACKEND_IMAGE}:${TAG} > /dev/null 2>&1
    echo "✅ [Backend] Build Complete"
) &
PIDS="$PIDS $!"

# --- FRONTEND ---
(
    echo "📦 [Frontend] Building Image..."
    gcloud builds submit ./frontend --tag ${FRONTEND_IMAGE}:${TAG} > /dev/null 2>&1
    echo "✅ [Frontend] Build Complete"
) &
PIDS="$PIDS $!"

# Wait for all builds
echo "⏳ Waiting for builds to complete..."
FAIL=0
for job in $PIDS; do
    wait $job || let "FAIL+=1"
done

if [ "$FAIL" -eq "0" ]; then
    echo "🎉 All builds completed successfully!"
else
    echo "❌ $FAIL builds failed. Check logs."
    exit 1
fi

# ==============================================================================
# 2. DEPLOY TO CLOUD RUN
# ==============================================================================

# --- DEPLOY MCP SERVER ---
echo "🚀 Deploying MCP Server (Toolbox)..."
gcloud run deploy ${TOOLBOX_SERVICE} \
    --image ${TOOLBOX_IMAGE}:${TAG} \
    --region ${REGION} \
    --platform managed \
    --allow-unauthenticated \
    --port 8080 \
    --service-account search-backend-sa@${PROJECT_ID}.iam.gserviceaccount.com

TOOLBOX_URL=$(gcloud run services describe ${TOOLBOX_SERVICE} --region ${REGION} --format 'value(status.url)')
export TOOLBOX_URL
echo "✅ MCP Server deployed at: ${TOOLBOX_URL}"

# --- DEPLOY AGENT ---
echo "🚀 Deploying Agent with Sidecar..."
# Generate resolved service YAML
envsubst < backend/agent/service.yaml > backend/agent/service_resolved.yaml

gcloud run services replace backend/agent/service_resolved.yaml --region ${REGION}

# Cleanup
rm backend/agent/service_resolved.yaml

AGENT_URL=$(gcloud run services describe ${AGENT_SERVICE} --region ${REGION} --format 'value(status.url)')
echo "✅ Agent deployed at: ${AGENT_URL}"

# --- DEPLOY BACKEND ---
echo "🚀 Deploying Backend with Sidecar..."
# Generate resolved service YAML
envsubst < backend/service.yaml > backend/service_resolved.yaml

gcloud run services replace backend/service_resolved.yaml --region ${REGION}

# Cleanup
rm backend/service_resolved.yaml

BACKEND_URL=$(gcloud run services describe ${BACKEND_SERVICE} --region ${REGION} --format 'value(status.url)')
echo "✅ Backend deployed at: ${BACKEND_URL}"

# --- DEPLOY FRONTEND ---
echo "🚀 Deploying Frontend..."
gcloud run deploy ${FRONTEND_SERVICE} \
    --image ${FRONTEND_IMAGE}:${TAG} \
    --region ${REGION} \
    --platform managed \
    --allow-unauthenticated \
    --set-env-vars BACKEND_URL=${BACKEND_URL},AGENT_URL=${AGENT_URL}

FRONTEND_URL=$(gcloud run services describe ${FRONTEND_SERVICE} --region ${REGION} --format 'value(status.url)')

echo "🎉 Deployment Complete!"
echo "Frontend: ${FRONTEND_URL}"
echo "Backend:  ${BACKEND_URL}"
echo "Agent:    ${AGENT_URL}"
echo "Toolbox:  ${TOOLBOX_URL}"
