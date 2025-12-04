# Terraform Infrastructure Setup

This directory contains Terraform scripts to automate the deployment of the Search Demo infrastructure on Google Cloud.

## Prerequisites

1.  **Terraform**: Ensure Terraform is installed (v1.0+).
    -   [Install Terraform](https://developer.hashicorp.com/terraform/install)
2.  **Google Cloud SDK**: Ensure `gcloud` is installed and authenticated.
    ```bash
    gcloud auth application-default login
    ```
3.  **Billing Account ID**: You need the ID of the billing account to associate with the new project.
    -   Find it via `gcloud beta billing accounts list`.

## Quick Start

### 1. Initialize Terraform
Navigate to this directory and initialize the provider plugins:
```bash
cd terraform
terraform init
```

### 2. Configure Variables
Create a `terraform.tfvars` file to specify your project details. **Do not commit this file if it contains secrets.**

**`terraform.tfvars` example:**
```hcl
project_id         = "my-search-demo-project-123"
billing_account_id = "000000-000000-000000"
region             = "europe-west1"
db_password        = "StrongPassword123!" # Must meet complexity requirements
```

### 3. Review the Plan
Run `terraform plan` to see what resources will be created.
```bash
terraform plan
```
*Review the output to ensure it matches your expectations (Project, AlloyDB Cluster, IAM bindings, etc.).*

### 4. Apply the Configuration
Run `terraform apply` to create the infrastructure.
```bash
terraform apply
```
*Type `yes` when prompted to confirm.*

## What gets created?

-   **Project**: A new Google Cloud Project with enabled APIs.
-   **Network**: A VPC network (`search-demo-vpc`) with Private Service Access for AlloyDB.
-   **AlloyDB**:
    -   Cluster: `search-cluster`
    -   Instance: `search-primary` (2 vCPU, Private IP only)
    -   Flags: AI & ML integration enabled.
-   **Bastion Host**: `search-demo-bastion` (e2-micro) for SSH tunneling.
-   **Artifact Registry**: Repository `search-app-repo`.
-   **IAM**: Creates a dedicated Service Account `search-backend-sa` and grants necessary roles.
-   **Vertex AI Search**: Creates a Data Store `property-listings-ds` linked to AlloyDB (via API call).


## 5. Deploy Application (Optional)

Once the infrastructure is ready, you can automatically generate the configuration file for the application deployment.

1.  **Generate Environment Config**:
    ```bash
    ./generate_env.sh
    ```
    This script reads the Terraform outputs and creates `backend/.env`.

2.  **Deploy Application**:
    Navigate back to the root directory and run the deploy script:
    ```bash
    cd ..
    ./deploy.sh
    ```

## Outputs
After a successful apply, Terraform will output:
-   `project_id`
-   `alloydb_cluster_id`
-   `alloydb_instance_id`
-   `backend_service_account`
-   `bastion_instance_name`
-   `bastion_zone`
-   `vertex_ai_data_store_id`

You can use these values to configure your `backend/.env` file.
