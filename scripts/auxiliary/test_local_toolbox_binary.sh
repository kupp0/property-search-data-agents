#!/bin/bash
set -e

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"
echo "📂 Project Root: $PROJECT_ROOT"

# Load env vars
set -a
source backend/.env
set +a

# Verify DB_PASSWORD
if [ -z "$DB_PASSWORD" ]; then
    echo "❌ DB_PASSWORD is empty"
    exit 1
fi

echo "✅ DB_PASSWORD is set"
export PROJECT_ID=$GCP_PROJECT_ID

# Run local toolbox binary
echo "📦 Running Local Toolbox Binary..."
./backend/mcp_server/toolbox --tools-file "backend/mcp_server/tools_local.yaml" --address=0.0.0.0 --port=8085
