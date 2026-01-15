#!/bin/bash
set -e

# Load environment variables
if [ -f "backend/.env" ]; then
    set -a
    source backend/.env
    set +a
else
    echo "❌ backend/.env not found. Please run ./setup_env.sh first."
    exit 1
fi

if [ -z "$INSTANCE_CONNECTION_NAME" ]; then
    echo "❌ INSTANCE_CONNECTION_NAME is not set in backend/.env"
    exit 1
fi

echo "📦 Running AlloyDB Auth Proxy (Public IP)..."
echo "   Instance: $INSTANCE_CONNECTION_NAME"

# Check if port 5432 is in use
if lsof -i :5432 -t >/dev/null; then
    echo "   ⚠️  Port 5432 is in use. Killing existing process..."
    kill -9 $(lsof -i :5432 -t)
fi

# Prepare credentials with correct permissions for Docker
cp $HOME/.config/gcloud/application_default_credentials.json /tmp/adc.json
chmod 644 /tmp/adc.json

docker run -it --rm \
    --name alloydb-auth-proxy \
    --network host \
    -v /tmp/adc.json:/tmp/keys.json:ro \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys.json \
    gcr.io/alloydb-connectors/alloydb-auth-proxy:latest \
    "$INSTANCE_CONNECTION_NAME" \
    --address 0.0.0.0 \
    --port 5432 \
    --public-ip
