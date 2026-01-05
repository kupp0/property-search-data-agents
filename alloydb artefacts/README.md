# AlloyDB Artifacts & Bootstrap

This directory contains SQL scripts for setting up AlloyDB and a Python script `bootstrap_images.py` to generate images and embeddings for property listings.

## How to run `bootstrap_images.py`

This script generates AI images for listings using Imagen, creates embeddings, uploads images to GCS, and updates the AlloyDB database.

### Prerequisites

1.  **Environment Variables**:
    The script loads environment variables from `../backend/.env`.
    Ensure this file exists and is populated. You can generate it using Terraform outputs:
    ```bash
    cd ../terraform
    ./generate_env.sh
    ```
    Or manually create it based on `../example.env`.

2.  **AlloyDB Auth Proxy**:
    The script connects to AlloyDB via `127.0.0.1:5432`. You must have the Auth Proxy running.
    A helper script is provided to start the proxy via the Bastion host:
    ```bash
    ./run_proxy.sh
    ```
    *This will establish an SSH tunnel and start the proxy on the Bastion host.*

3.  **Python Environment**:
    Ensure you have Python installed and the required dependencies.
    It is recommended to use a virtual environment.

    ```bash
    # Create and activate virtual env
    python3 -m venv venv
    source venv/bin/activate

    # Install dependencies
    pip install -r requirements.txt
    ```

### Running the Script

Once the proxy is running and environment is set:

```bash
python bootstrap_images.py
```

### What it does
1.  Connects to AlloyDB via localhost:5432.
2.  Finds listings with `image_gcs_uri IS NULL`.
3.  Generates an image using Vertex AI Imagen.
4.  Uploads the image to the GCS bucket (`property-images-{PROJECT_ID}`).
5.  Generates a multimodal embedding for the image.
6.  Updates the `property_listings` table with the GCS URI and embedding.
