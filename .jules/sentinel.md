## 2026-02-02 - SSRF in GCS Image Proxy
**Vulnerability:** Unrestricted GCS bucket access in `/api/image` endpoint allowed reading files from any bucket accessible by the service account.
**Learning:** The application trusted user input (`gcs_uri`) to determine the source bucket without validation, assuming all GCS URIs were benign.
**Prevention:** Enforce an allowlist for bucket names when proxying GCS content. Use environment variables to define the trust boundary.
