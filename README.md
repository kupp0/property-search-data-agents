# AlloyDB AI Search Demo (Gemini Data Agent)

This application demonstrates a **Natural Language to SQL (NL2SQL)** pipeline powered by the **Gemini Data Agent**. It allows users to search for property listings using natural language queries, which are translated into SQL and executed against an AlloyDB database.

## Architecture

![Architecture Diagram](assets/data_agent_diagram.png)

*   **Frontend**: React application (Vite) with a modern UI.
*   **Backend**: FastAPI (Python) service that proxies requests to the Gemini Data Agent API and serves images securely from Google Cloud Storage.
*   **Gemini Data Agent**: A managed service that understands natural language and interacts with your data.
*   **AlloyDB**: PostgreSQL-compatible database storing property listings.

## Features

*   **Natural Language Search**: Ask questions like "Show me 2-bedroom apartments in Zurich under 3000 CHF".
*   **Generative AI Answers**: Get natural language summaries alongside data results.
*   **Secure Image Serving**: Images are served securely from a private GCS bucket via the backend.
*   **Modern UI**: Responsive design with dark mode support. 

## Prerequisites

*   Google Cloud Project with billing enabled.
*   AlloyDB Cluster and Instance.
*   Gemini Data Agent configured with AlloyDB as a data source.
*   Google Cloud Storage bucket for images.
*   If Data Agent feature is still in gated preview, whitelist your project first. Details: https://docs.cloud.google.com/alloydb/docs/ai/data-agent-overview

## Local Development

1.  **Configure Environment**:
    Copy `.env.example` to `backend/.env` and fill in your values:
    ```bash
    cp .env.example backend/.env
    ```

2.  **Start Services**:
    Run the development script to start both Backend and Frontend:
    ```bash
    ./scripts/dev_local.sh
    ```
    *   Backend: http://localhost:8080
    *   Frontend: http://localhost:8081

    **Alternatively (Recommended with Docker):**
    ```bash
    ./scripts/debug_local.sh
    ```

## Deployment

To deploy to Google Cloud Run:

```bash
./scripts/deploy.sh
```

This script will:
1.  Build Docker images for Backend and Frontend.
2.  Push images to Artifact Registry.
3.  Deploy services to Cloud Run.

## Project Structure

*   `backend/`: FastAPI application.
*   `frontend/`: React application.
*   `terraform/`: Infrastructure as Code (optional).
