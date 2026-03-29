## 2026-02-03 - [Repeated Google Auth Calls]
**Learning:** The `query_gda` function was calling `google.auth.default()` on every request. This triggers environment checks and potential metadata server calls (I/O) for every search, adding latency.
**Action:** Cache the credentials object globally using a helper function `get_gda_credentials()` and reuse it, calling `.refresh()` only when needed.

## 2026-02-04 - [Synchronous DB Logging]
**Learning:** The `/api/search` endpoint was awaiting database logging *inline*, delaying the response to the user.
**Action:** Use FastAPI `BackgroundTasks` to offload non-critical side effects like history logging.
