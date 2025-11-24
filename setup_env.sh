#!/bin/bash
set -e

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

read -p "AlloyDB Cluster Name: " CLUSTER_NAME
read -p "AlloyDB Instance Name: " INSTANCE_NAME
read -p "AlloyDB Database Name: " DB_NAME
DB_NAME=${DB_NAME:-postgres}
read -p "AlloyDB User: " DB_USER
DB_USER=${DB_USER:-postgres}
read -s -p "AlloyDB Password: " DB_PASSWORD
echo

read -p "Vertex AI Search Data Store ID: " VERTEX_SEARCH_DATA_STORE_ID

# Construct INSTANCE_CONNECTION_NAME
INSTANCE_CONNECTION_NAME="projects/$GCP_PROJECT_ID/locations/$GCP_LOCATION/clusters/$CLUSTER_NAME/instances/$INSTANCE_NAME"

echo "📝 Writing to $ENV_FILE..."

cat > "$ENV_FILE" <<EOF
GCP_PROJECT_ID=$GCP_PROJECT_ID
GCP_LOCATION=$GCP_LOCATION
INSTANCE_CONNECTION_NAME=$INSTANCE_CONNECTION_NAME
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
VERTEX_SEARCH_DATA_STORE_ID=$VERTEX_SEARCH_DATA_STORE_ID
EOF

echo "✅ Configuration saved to $ENV_FILE"
echo "You can now run ./deploy.sh or ./debug_local.sh"
