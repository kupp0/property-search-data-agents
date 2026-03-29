import pytest
from unittest.mock import MagicMock, patch, AsyncMock
from fastapi.testclient import TestClient
import sys

# We need to mock google.auth before importing backend.main because it runs at module level
# (or at least handle the side effects).
# However, backend.main has a try-except block for the top-level init, so it won't crash.
# But we DO need to mock it for the request handling.

# Let's import the app.
# We will patch the dependencies using 'with patch' inside the test.
# But we also need to make sure we don't accidentally make network calls.

import backend.main
from backend.main import app

client = TestClient(app)

@pytest.mark.asyncio
async def test_search_api_logging():
    """
    Verifies that the search API returns results and logs the query to the database.
    """

    # Mocking query_gda to avoid calling the real Gemini Agent
    mock_gda_response = {
        "naturalLanguageAnswer": "This is a test answer.",
        "queryResult": {
            "rows": [],
            "columns": [],
            "query": "SELECT * FROM properties",
            "totalRowCount": "0"
        },
        "intentExplanation": "Test explanation."
    }

    # Setup DB Mocks
    # We need to mock get_engine to return a Mock Engine
    mock_engine = MagicMock()
    mock_conn = AsyncMock()

    # engine.begin() returns a context manager
    # async with db_engine.begin() as conn:
    mock_transaction = MagicMock()
    mock_transaction.__aenter__.return_value = mock_conn
    mock_transaction.__aexit__.return_value = None

    mock_engine.begin.return_value = mock_transaction

    with patch("backend.main.query_gda", return_value=mock_gda_response) as mock_query, \
         patch("backend.main.get_engine", new_callable=AsyncMock) as mock_get_engine:

        mock_get_engine.return_value = mock_engine

        # Make the request
        response = client.post("/api/search", json={"query": "test query"})

        # Assertions
        assert response.status_code == 200, f"Response: {response.text}"
        data = response.json()

        assert data["nl_answer"] == "This is a test answer."
        assert "GEMINI DATA AGENT CALL" in data["sql"]

        # Verify Database Interaction
        # Check if get_engine was called
        assert mock_get_engine.called

        # Check if execute was called on the connection
        assert mock_conn.execute.called, "Database execute should have been called"

        # Check arguments to execute
        call_args = mock_conn.execute.call_args
        # The first arg is the SQL text object
        sql_arg = call_args[0][0]
        assert "INSERT INTO user_prompt_history" in str(sql_arg)

        params = call_args[0][1] # or call_args[1] if passed as kwargs, but text() usually takes params as second arg in execute(statement, params)
        # Wait, in main.py: await conn.execute(text(...), {...})
        # So it's the second positional argument

        assert params["prompt"] == "test query"
        assert params["explanation"] == "Test explanation."
