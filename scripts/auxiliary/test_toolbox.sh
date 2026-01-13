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

echo "✅ DB_PASSWORD is set (length: ${#DB_PASSWORD})"
echo "✅ PROJECT_ID: $GCP_PROJECT_ID"

# Prepare credentials with correct permissions
cp $HOME/.config/gcloud/application_default_credentials.json /tmp/adc.json
chmod 644 /tmp/adc.json

# Run toolbox
echo "📦 Running Toolbox Container..."
docker rm -f toolbox-test || true
docker run --rm \
    --name toolbox-test \
    --network host \
    -e PORT=8085 \
    -e DB_PASSWORD="$DB_PASSWORD" \
    -e PROJECT_ID="$GCP_PROJECT_ID" \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys.json \
    -v /tmp/adc.json:/tmp/keys.json:ro \
    -v $(pwd)/backend/mcp_server/tools_local.yaml:/secrets/tools.yaml:ro \
    us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:latest \
    --tools-file=/secrets/tools.yaml --address=0.0.0.0 --port=8085 --ui
