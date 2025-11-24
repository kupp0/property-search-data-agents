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

# 1. Start AlloyDB Auth Proxy locally (background)
echo "🔌 Starting AlloyDB Auth Proxy..."

if [ ! -f "./alloydb-auth-proxy" ]; then
    echo "   Proxy binary not found. Downloading..."
    wget https://storage.googleapis.com/alloydb-auth-proxy/v1.10.0/alloydb-auth-proxy.linux.amd64 -O alloydb-auth-proxy
    chmod +x alloydb-auth-proxy
fi

./alloydb-auth-proxy "$INSTANCE_URI" --address=0.0.0.0 --port=5432 --public-ip --credentials-file ~/.config/gcloud/application_default_credentials.json > proxy.log 2>&1 &
PROXY_PID=$!
echo "   Proxy PID: $PROXY_PID"

# Cleanup function
cleanup() {
    echo "🧹 Stopping containers and proxy..."
    sudo docker stop search-backend search-frontend || true
    kill $PROXY_PID || true
}
trap cleanup EXIT

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

# 3. Run Frontend Container
echo "📦 Running Frontend Container..."
sudo docker run -d --rm \
    --name search-frontend \
    --network host \
    -e PORT=8081 \
    -e BACKEND_URL="http://localhost:8080" \
    local-search-frontend

echo "   Frontend running on localhost:8081"
echo "🎉 Debug environment ready!"
echo "   Frontend: http://localhost:8081"
echo "   Backend logs: sudo docker logs -f search-backend"
echo "   Frontend logs: sudo docker logs -f search-frontend"
echo "   Press Ctrl+C to stop."

# Keep script running to maintain trap
wait
