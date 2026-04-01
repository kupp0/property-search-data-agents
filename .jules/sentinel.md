## 2024-05-23 - [Testing SSRF with FastAPI TestClient]
**Vulnerability:** Insecure Direct Object Reference / SSRF in GCS image proxy.
**Learning:** `FastAPI.testclient.TestClient` follows redirects by default. When testing for SSRF where the vulnerability manifests as an open redirect (307), the client follows it. If the redirect URL is a mocked string, it fails with 404 (Not Found), masking the successful redirect (307). If it's a Mock object, it crashes.
**Prevention:** Use `client.get(..., follow_redirects=False)` when testing redirect-based vulnerabilities or logic to inspect the response status and headers directly.
