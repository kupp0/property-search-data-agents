#!/bin/bash
set -e

# Load environment variables
# Load environment variables
if [ -f "backend/.env" ]; then
    echo "📄 Loading configuration from backend/.env..."
    export $(grep -v '^#' backend/.env | xargs)
else
    echo "❌ backend/.env not found. Please run ./setup_env.sh first."
    exit 1
fi

PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project)}
REGION=${GCP_LOCATION:-"europe-west1"}
# In setup_env.sh, INSTANCE_CONNECTION_NAME is the full URI
INSTANCE_URI="${INSTANCE_CONNECTION_NAME}"

echo "🔧 Setting up local debug environment..."

# 1. Start AlloyDB Auth Proxy via Bastion (background)
echo "🔌 Starting AlloyDB Auth Proxy via Bastion..."

BASTION_NAME="search-demo-bastion"
BASTION_ZONE="${REGION}-b"

# Ensure local proxy binary exists
if [ ! -f "alloydb-auth-proxy" ]; then
    echo "   Downloading proxy binary locally..."
    wget -q https://storage.googleapis.com/alloydb-auth-proxy/v1.10.0/alloydb-auth-proxy.linux.amd64 -O alloydb-auth-proxy
    chmod +x alloydb-auth-proxy
fi

# Copy proxy to Bastion (since Bastion might not have internet)
echo "   Copying proxy to Bastion..."
# Kill existing proxy process to avoid "Text file busy" error
gcloud compute ssh $BASTION_NAME --zone $BASTION_ZONE --command "killall alloydb-auth-proxy || true" --quiet
gcloud compute scp alloydb-auth-proxy $BASTION_NAME:~/alloydb-auth-proxy --zone $BASTION_ZONE --quiet
gcloud compute ssh $BASTION_NAME --zone $BASTION_ZONE --command "chmod +x alloydb-auth-proxy"

# Start Proxy on Bastion and Tunnel
# We tunnel local 5432 -> Bastion 5432 (where proxy listens)
echo "   Establishing SSH tunnel and starting remote proxy..."
gcloud compute ssh $BASTION_NAME --zone $BASTION_ZONE \
    --command "./alloydb-auth-proxy \"$INSTANCE_URI\" --address=127.0.0.1 --port=5432 --debug-logs" \
    -- -L 5432:127.0.0.1:5432 > proxy.log 2>&1 &
PROXY_PID=$!
echo "   Proxy/Tunnel PID: $PROXY_PID"


# Cleanup function
cleanup() {
    echo "🧹 Stopping containers and proxy..."
    sudo docker stop search-backend search-frontend agent-service toolbox-service || true
    kill $PROXY_PID || true
}
trap cleanup EXIT

# --- PRE-CLEANUP ---
echo "🧹 Cleaning up existing containers..."
sudo docker rm -f search-backend search-frontend agent-service toolbox-service 2>/dev/null || true

# --- BUILD LOCALLY ---
echo "🔨 Building images locally to avoid auth issues..."
sudo docker build -t local-search-backend backend/
sudo docker build -t local-search-frontend frontend/

# 2. Run Backend Container
echo "📦 Running Backend Container..."
sudo docker run -d --rm \
    --name search-backend \
    --network host \
    -e PORT=8080 \
    -e DB_NAME=$DB_NAME \
    -e DB_USER=$DB_USER \
    -e DB_PASSWORD=$DB_PASSWORD \
    -e GCP_PROJECT_ID=$PROJECT_ID \
    -e GCP_LOCATION=$REGION \
    -e INSTANCE_CONNECTION_NAME=$INSTANCE_CONNECTION_NAME \
    -e VERTEX_SEARCH_DATA_STORE_ID="$VERTEX_SEARCH_DATA_STORE_ID" \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys.json \
    -v $HOME/.config/gcloud/application_default_credentials.json:/tmp/keys.json:ro \
    local-search-backend

echo "   Backend running on localhost:8080"

echo "   Backend running on localhost:8080"

# 2.3. Run Toolbox Container
echo "📦 Running Toolbox Container..."
sudo docker run -d --rm \
    --name toolbox-service \
    --network host \
    -e PORT=8085 \
    -e DB_PASSWORD=$DB_PASSWORD \
    -v $(pwd)/backend/mcp_server/tools_local.yaml:/secrets/tools.yaml:ro \
    us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:latest \
    --tools-file=/secrets/tools.yaml --address=0.0.0.0 --port=8085

echo "   Toolbox running on localhost:8085"
echo "📦 Running Agent Container..."
sudo docker build -t local-agent-service backend/agent/
sudo docker run -d --rm \
    --name agent-service \
    --network host \
    -e PORT=8083 \
    -e GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
    -e GOOGLE_CLOUD_REGION="us-central1" \
    -e GOOGLE_GENAI_USE_VERTEXAI=true \
    -e GOOGLE_CLOUD_LOCATION="us-central1" \
    -e TOOLBOX_URL="http://localhost:8085" \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys.json \
    -v $HOME/.config/gcloud/application_default_credentials.json:/tmp/keys.json:ro \
    local-agent-service

echo "   Agent running on localhost:8083"

# 3. Run Frontend Container
echo "📦 Running Frontend Container..."
sudo docker run -d --rm \
    --name search-frontend \
    --network host \
    -e PORT=8081 \
    -e BACKEND_URL="http://localhost:8080" \
    -e AGENT_URL="http://localhost:8083" \
    local-search-frontend

echo "   Frontend running on localhost:8081"
echo "🎉 Debug environment ready!"
echo "   Frontend: http://localhost:8081"
echo "   Backend logs: sudo docker logs -f search-backend"
echo "   Frontend logs: sudo docker logs -f search-frontend"
echo "   Press Ctrl+C to stop."

# Keep script running to maintain trap
wait
