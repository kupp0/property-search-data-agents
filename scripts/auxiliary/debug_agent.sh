#!/bin/bash
set -e

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"
echo "📂 Project Root: $PROJECT_ROOT"

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

echo "🔧 Starting ADK Agent..."
echo "   Project: $PROJECT_ID"
echo "   Region: $REGION"

# Activate venv
source backend/agent/.venv/bin/activate

# Set environment variables for ADK
export GOOGLE_CLOUD_PROJECT=$PROJECT_ID
export GOOGLE_CLOUD_REGION="global"
export TOOLBOX_URL="http://127.0.0.1:5000"

# Export variables for google.genai auto-configuration
export GOOGLE_GENAI_USE_VERTEXAI=true
export GOOGLE_CLOUD_LOCATION=$GOOGLE_CLOUD_REGION

# Run the agent
# We use uvicorn to run the FastAPI app
# Reload flag is useful for development
uvicorn backend.agent.main:app --host 0.0.0.0 --port 8083 --reload
