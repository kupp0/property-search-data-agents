#!/bin/bash
set -e

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"
echo "📂 Project Root: $PROJECT_ROOT"

echo "🔧 Setting up environment configuration..."

ENV_FILE="backend/.env"

if [ -f "$ENV_FILE" ]; then
    echo "✅ $ENV_FILE already exists."
    read -p "Do you want to overwrite it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping setup."
        exit 0
    fi
fi

echo "Please enter the following configuration values:"

read -p "GCP Project ID: " GCP_PROJECT_ID
read -p "GCP Region (default: europe-west1): " GCP_LOCATION
GCP_LOCATION=${GCP_LOCATION:-europe-west1}

read -p "AlloyDB Cluster ID (default: search-cluster): " ALLOYDB_CLUSTER_ID
ALLOYDB_CLUSTER_ID=${ALLOYDB_CLUSTER_ID:-search-cluster}

read -p "AlloyDB Instance ID (default: search-primary): " ALLOYDB_INSTANCE_ID
ALLOYDB_INSTANCE_ID=${ALLOYDB_INSTANCE_ID:-search-primary}

read -p "AlloyDB Region (default: $GCP_LOCATION): " ALLOYDB_REGION
ALLOYDB_REGION=${ALLOYDB_REGION:-$GCP_LOCATION}

read -p "AlloyDB Database ID (default: search): " ALLOYDB_DATABASE_ID
ALLOYDB_DATABASE_ID=${ALLOYDB_DATABASE_ID:-search}

read -p "Agent Context Set ID: " AGENT_CONTEXT_SET_ID

echo "📝 Writing to $ENV_FILE..."

cat > "$ENV_FILE" <<EOF
GCP_PROJECT_ID=$GCP_PROJECT_ID
GCP_LOCATION=$GCP_LOCATION
ALLOYDB_CLUSTER_ID=$ALLOYDB_CLUSTER_ID
ALLOYDB_INSTANCE_ID=$ALLOYDB_INSTANCE_ID
ALLOYDB_REGION=$ALLOYDB_REGION
ALLOYDB_DATABASE_ID=$ALLOYDB_DATABASE_ID
AGENT_CONTEXT_SET_ID=$AGENT_CONTEXT_SET_ID
EOF

echo "✅ Configuration saved to $ENV_FILE"
echo "You can now run ./deploy.sh or ./debug_local.sh"
