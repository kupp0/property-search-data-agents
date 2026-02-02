## 2025-02-18 - SSRF in Image Proxy
**Vulnerability:** The `/api/image` endpoint allowed arbitrary GCS bucket access via the `gcs_uri` parameter, permitting potential access to sensitive data in other buckets within the same project.
**Learning:** The application relied on the service account's permissions without application-level scoping.
**Prevention:** Enforce strict allow-lists for external resource identifiers (buckets, domains) at the application boundary.
