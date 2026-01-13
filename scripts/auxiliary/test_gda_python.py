import os
import requests
import google.auth
import google.auth.transport.requests
import json

# Configuration matching gda_curl_test.sh
PROJECT_ID = "my-search-demo-alloydb"
AGENT_CONTEXT_SET_ID = f"projects/{PROJECT_ID}/locations/europe-west4/contextSets/property-search-guru-w-fragmen"
GDA_LOCATION = "europe-west1"

def query_gda(prompt):
    url = f"https://geminidataanalytics.googleapis.com/v1beta/projects/{PROJECT_ID}/locations/{GDA_LOCATION}:queryData"
    
    # Get credentials
    creds, project = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    if not creds.valid:
        creds.refresh(google.auth.transport.requests.Request())
    
    print(f"Creds: {creds.service_account_email if hasattr(creds, 'service_account_email') else 'User Creds'}")

    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "parent": f"projects/{PROJECT_ID}/locations/{GDA_LOCATION}",
        "prompt": prompt,
        "context": {
            "datasourceReferences": {
                "alloydb": {
                    "databaseReference": {
                        "project_id": PROJECT_ID,
                        "region": "europe-west1",
                        "cluster_id": "search-cluster",
                        "instance_id": "search-primary",
                        "database_id": "search"
                    },
                    "agentContextReference": {
                        "context_set_id": AGENT_CONTEXT_SET_ID
                    }
                }
            }
        },
        "generation_options": {
            "generate_query_result": True,
            "generate_natural_language_answer": True,
            "generate_explanation": True
        }
    }
    
    print(f"Sending request to {url}")
    print(json.dumps(payload, indent=2))
    
    try:
        resp = requests.post(url, headers=headers, json=payload)
        print(f"Status: {resp.status_code}")
        print(resp.text)
        resp.raise_for_status()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    query_gda("What are the top 3 most expensive properties listed in Zurich?")
