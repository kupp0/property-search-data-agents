#!/bin/bash
set -e

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"
echo "📂 Project Root: $PROJECT_ROOT"

# Kill background processes on exit
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

echo "🚀 Starting Local Development Environment..."

# 1. Start Backend (FastAPI)
echo "🐍 Starting Backend (FastAPI)..."
cd backend

# Source .env and export variables
if [ -f ".env" ]; then
    echo "   Loading environment variables from .env..."
    set -a
    source .env
    set +a
    # Map GCP_PROJECT_ID to PROJECT_ID for tools.yaml
    if [ -n "$GCP_PROJECT_ID" ] && [ -z "$PROJECT_ID" ]; then
        export PROJECT_ID=$GCP_PROJECT_ID
    fi
fi

# Setup/Activate Virtual Environment



# Install dependencies
echo "   Checking/Installing dependencies..."
python3 -m pip install -r requirements.txt

# Run uvicorn
# We don't need DB_HOST anymore as we use GDA API
python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --reload &
BACKEND_PID=$!
cd ..

# 2. Start MCP Server
echo "🧰 Starting MCP Server..."
cd backend/mcp_server
# Generate resolved tools configuration
envsubst < tools.yaml > tools_resolved.yaml
# Run toolbox
./toolbox --tools-file=tools_resolved.yaml --address=0.0.0.0 --port=8082 &
MCP_PID=$!
cd ../..

# 3. Start Agent
echo "🤖 Starting Agent..."
cd backend/agent
# Install agent dependencies
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate

# Try to install dependencies, but don't fail the whole script if google-adk is missing
if pip install -r requirements.txt; then
    # Run agent
    export TOOLBOX_URL=http://127.0.0.1:8082
    python3 -m uvicorn main:app --host 0.0.0.0 --port 8083 &
    AGENT_PID=$!
else
    echo "⚠️  WARNING: Failed to install Agent dependencies (likely google-adk missing)."
    echo "⚠️  The 'AI Agent' chat feature will be unavailable, but Search will still work."
fi
cd ../..

# 4. Start Frontend (Vite)
echo "⚛️  Starting Frontend (Vite)..."
cd frontend
# npm install # Uncomment if needed
npm run dev -- --port 8081 &
FRONTEND_PID=$!
cd ..

echo "✅ Services Started!"
echo "   Backend: http://localhost:8080"
echo "   Frontend: http://localhost:8081"
echo "   MCP Server: http://localhost:8082"
echo "   Agent: http://localhost:8083"
echo "   (Press Ctrl+C to stop)"

wait
