## 2026-02-03 - [Repeated Google Auth Calls]
**Learning:** The `query_gda` function was calling `google.auth.default()` on every request. This triggers environment checks and potential metadata server calls (I/O) for every search, adding latency.
**Action:** Cache the credentials object globally using a helper function `get_gda_credentials()` and reuse it, calling `.refresh()` only when needed.

## 2026-02-03 - [Blocking DB Logging in Search]
**Learning:** The `search_properties` endpoint was waiting for the database insertion of search history to complete before returning results to the user. This added unnecessary latency to the user-facing response.
**Action:** Offloaded the database logging to a `BackgroundTasks` function, `log_search_history`, allowing the API to return the search results immediately while logging happens asynchronously.
