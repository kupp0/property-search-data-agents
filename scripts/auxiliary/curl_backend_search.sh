#!/bin/bash

# Default to localhost:8080 if not set
BASE_URL="${BACKEND_URL:-https://data-agent-search-backend-950411912152.europe-west1.run.app}"

echo "🔍 Testing Backend Search Endpoint at $BASE_URL..."

curl -X POST "${BASE_URL}/api/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "show me Lovely Mountain Cabins under 15k"
  }' | json_pp
