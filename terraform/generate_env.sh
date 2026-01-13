#!/bin/bash
set -e

# Configuration
TERRAFORM_DIR="$(dirname "$0")"
PROJECT_ROOT="$TERRAFORM_DIR/.."
ENV_FILE="$PROJECT_ROOT/backend/.env"

echo "🔍 Reading Terraform outputs..."

# Check if terraform is initialized
if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
    echo "❌ Terraform not initialized. Please run 'terraform init' and 'terraform apply' first."
    exit 1
fi

# Get outputs in JSON format
OUTPUTS=$(cd "$TERRAFORM_DIR" && terraform output -json)

# Extract values using python (to avoid jq dependency if not present, though jq is better)
# Assuming python3 is available.
extract_value() {
    echo "$OUTPUTS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('$1', {}).get('value', ''))"
}

PROJECT_ID=$(extract_value "project_id")
CLUSTER_ID=$(extract_value "alloydb_cluster_id")
INSTANCE_ID=$(extract_value "alloydb_instance_id")

REGION=$(cd "$TERRAFORM_DIR" && grep 'region' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

# Fallback for Region if not in tfvars (default)
if [ -z "$REGION" ]; then
    REGION=${GCP_LOCATION:-europe-west1}
fi

# Get DB Password from tfvars (simple grep, assuming standard format)
# WARNING: This is a simple extraction. For production, use a secrets manager.
DB_PASSWORD=$(cd "$TERRAFORM_DIR" && grep 'db_password' terraform.tfvars | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "')

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Could not extract Project ID from Terraform outputs. Did you run 'terraform apply'?"
    exit 1
fi

echo "✅ Extracted configuration:"
echo "   Project: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Cluster: $CLUSTER_ID"
echo "   Instance: $INSTANCE_ID"
echo "   Data Store: $DATA_STORE_ID"

# Construct Connection Name
INSTANCE_CONNECTION_NAME="projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID/instances/$INSTANCE_ID"

echo "📝 Writing to $ENV_FILE..."

cat > "$ENV_FILE" <<EOF
GCP_PROJECT_ID=$PROJECT_ID
GCP_LOCATION=$REGION
INSTANCE_CONNECTION_NAME=$INSTANCE_CONNECTION_NAME
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=$DB_PASSWORD
EOF

echo "🎉 Configuration saved to $ENV_FILE"
echo "🚀 You can now run '../deploy.sh' to deploy the application."
