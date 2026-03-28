import sys
import os
import pytest
from unittest.mock import MagicMock, patch, AsyncMock

# Set environment variables needed for import
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["AGENT_CONTEXT_SET_ID"] = "test-context"
os.environ["DB_PASSWORD"] = "test-pass"

# Import app - let module level init fail/warn (it's in a try/except block in main.py)
from backend.main import app

@pytest.mark.asyncio
async def test_search_properties_logs_to_db():
    # Mock the DB Engine and Connection
    # get_engine returns the engine.
    # db_engine.begin() is synchronous and returns an async context manager.

    mock_engine = MagicMock()
    mock_conn = AsyncMock()

    # Create a mock for the context manager returned by begin()
    mock_cm = MagicMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_conn)
    mock_cm.__aexit__ = AsyncMock(return_value=None)

    mock_engine.begin.return_value = mock_cm

    # Patch get_engine in backend.main
    # get_engine is async, so it returns a coroutine that resolves to mock_engine
    mock_get_engine = AsyncMock(return_value=mock_engine)

    with patch("backend.main.get_engine", side_effect=mock_get_engine):

        # Mock requests.post for GDA
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "naturalLanguageAnswer": "Here is a house.",
            "generatedQuery": "SELECT * FROM houses",
            "intentExplanation": "This query uses Template 42 to find houses.",
            "queryResult": {
                "rows": [],
                "columns": [],
                "totalRowCount": "0"
            }
        }
        mock_response.raise_for_status = MagicMock()

        # Mock get_gda_credentials to avoid auth errors
        mock_creds = MagicMock()
        mock_creds.token = "fake-token"

        with patch("backend.main.requests.post", return_value=mock_response), \
             patch("backend.main.get_gda_credentials", return_value=mock_creds):

            from fastapi.testclient import TestClient
            client = TestClient(app)

            payload = {"query": "test query"}
            response = client.post("/api/search", json=payload)

            assert response.status_code == 200
            data = response.json()
            assert data["nl_answer"] == "Here is a house."

            # Verify DB logging was called
            # Check if begin() was called
            assert mock_engine.begin.called

            # Check if execute was called on connection
            assert mock_conn.execute.called

            call_args = mock_conn.execute.call_args
            assert call_args is not None

            params = call_args[0][1]
            assert params["used"] is True
            assert params["id"] == 42
            assert params["prompt"] == "test query"
