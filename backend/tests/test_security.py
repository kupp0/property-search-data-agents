import sys
import os
from unittest.mock import MagicMock
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport

# ==============================================================================
# MOCKING GOOGLE LIBRARIES
# ==============================================================================
# We must do this BEFORE importing backend.main because it initializes clients
# at the module level.

# 1. Mock 'google' package
mock_google = MagicMock()
sys.modules["google"] = mock_google

# 2. Mock 'google.auth'
mock_auth = MagicMock()
mock_auth.default.return_value = (MagicMock(), "test-project")
# Important: Link it to google mock so `import google.auth` works as expected
mock_google.auth = mock_auth
sys.modules["google.auth"] = mock_auth
sys.modules["google.auth.transport"] = MagicMock()
sys.modules["google.auth.transport.requests"] = MagicMock()

# 3. Mock 'google.cloud' and 'google.cloud.storage'
mock_cloud = MagicMock()
mock_google.cloud = mock_cloud
sys.modules["google.cloud"] = mock_cloud

mock_storage = MagicMock()
mock_cloud.storage = mock_storage
sys.modules["google.cloud.storage"] = mock_storage

# 4. Mock Storage Client behavior
mock_storage_client_instance = MagicMock()
mock_storage.Client.return_value = mock_storage_client_instance

mock_bucket = MagicMock()
mock_storage_client_instance.bucket.return_value = mock_bucket

mock_blob = MagicMock()
mock_bucket.blob.return_value = mock_blob
mock_blob.generate_signed_url.return_value = "https://signed.url/image.jpg"

# ==============================================================================
# ENVIRONMENT VARIABLES
# ==============================================================================
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["DB_PASSWORD"] = "dummy"

# ==============================================================================
# APP IMPORT
# ==============================================================================
from backend.main import app

# ==============================================================================
# TESTS
# ==============================================================================

@pytest.fixture
def anyio_backend():
    return 'asyncio'

@pytest_asyncio.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

@pytest.mark.asyncio
async def test_get_image_valid_bucket(client):
    """
    Verifies that accessing an image from the default allowed bucket works.
    Default bucket: property-images-data-agent-{PROJECT_ID} -> property-images-data-agent-test-project
    """
    valid_uri = "gs://property-images-data-agent-test-project/house.jpg"

    response = await client.get("/api/image", params={"gcs_uri": valid_uri})

    # Expect redirect (307)
    # If 500, check stdout for mock errors
    assert response.status_code == 307
    assert response.headers["location"] == "https://signed.url/image.jpg"

@pytest.mark.asyncio
async def test_get_image_blocked_bucket(client):
    """
    Verifies that accessing an image from a NON-allowed bucket is blocked.
    This test is expected to FAIL (return 307) before the fix is implemented.
    """
    invalid_uri = "gs://secret-bucket/passwords.txt"

    response = await client.get("/api/image", params={"gcs_uri": invalid_uri})

    # We expect 403 Forbidden after the fix
    assert response.status_code == 403
