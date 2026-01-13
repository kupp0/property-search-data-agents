#!/bin/bash

# Configuration
# <<< REPLACE with your actual Project ID >>>
PROJECT_ID="my-search-demo-alloydb"

# Extract details from the MCP Toolkit Definition
GDA_LOCATION="europe-west1"
API_ENDPOINT="https://geminidataanalytics.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${GDA_LOCATION}:queryData"

# AlloyDB connection details from YAML
DB_PROJECT_ID="${PROJECT_ID}"
DB_REGION="europe-west1"
DB_CLUSTER_ID="search-cluster"
DB_INSTANCE_ID="search-primary"
DB_DATABASE_ID="search"
AGENT_CONTEXT_SET_ID="projects/${PROJECT_ID}/locations/europe-west4/contextSets/property-search-guru-w-fragmen"

# Generation Options from YAML
GEN_QUERY_RESULT="true"
GEN_NL_ANSWER="true"
GEN_EXPLANATION="true"
GEN_DISAMBIGUATION="true"

# Get OAuth access token from gcloud
TOKEN=$(gcloud auth print-access-token)

# Check if token retrieval was successful
if [ -z "$TOKEN" ]; then
  echo "Failed to get gcloud auth token. Make sure you are authenticated."
  exit 1
fi

# JSON Payload constructed from YAML values (Corrected datasourceReferences)
read -r -d '' JSON_PAYLOAD << EOF
{
  "parent": "projects/${PROJECT_ID}/locations/${GDA_LOCATION}",
  "prompt": "${1:-Show me family apartments in Zurich with a nice view up to 16k}",
  "context": {
    "datasourceReferences": {
      "alloydb": {
        "databaseReference": {
          "project_id": "${DB_PROJECT_ID}",
          "region": "${DB_REGION}",
          "cluster_id": "${DB_CLUSTER_ID}",
          "instance_id": "${DB_INSTANCE_ID}",
          "database_id": "${DB_DATABASE_ID}"
        },
        "agentContextReference": {
          "context_set_id": "${AGENT_CONTEXT_SET_ID}"
        }
      }
    }
  },
  "generation_options": {
    "generate_query_result": ${GEN_QUERY_RESULT},
    "generate_natural_language_answer": ${GEN_NL_ANSWER},
    "generate_explanation": ${GEN_EXPLANATION},
    "generate_disambiguation_question": ${GEN_DISAMBIGUATION}
  }
}
EOF

echo "Sending request to: ${API_ENDPOINT}"
echo "Payload:"
echo "${JSON_PAYLOAD}"
echo "---"

# Make the API call using curl
curl -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "${JSON_PAYLOAD}" \
  "${API_ENDPOINT}"

echo # Add a newline for cleaner output
