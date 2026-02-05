## 2024-05-22 - Image Proxy SSRF
**Vulnerability:** The `/api/image` endpoint accepted arbitrary GCS URIs and used the default compute service account (with global `cloud-platform` scope) to access them. This allowed an attacker to access *any* GCS bucket visible to the project, leading to SSRF/IDOR.
**Learning:** Default Google Cloud credentials often have broad scopes (like `https://www.googleapis.com/auth/cloud-platform`). Relying on "internal" URIs provided by the database is insufficient if the endpoint accepts user input (even if indirectly intended for UI).
**Prevention:** Explicitly validate resource identifiers (bucket names) against an allowlist (env var `ALLOWED_GCS_BUCKET`) before accessing them using privileged clients.
