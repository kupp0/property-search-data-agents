import os
import sys
from unittest.mock import MagicMock, patch
import pytest

# 1. Setup Environment Variables
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["DB_PASSWORD"] = "dummy"
os.environ["DB_HOST"] = "localhost"
os.environ["AGENT_CONTEXT_SET_ID"] = "123"

# 2. Patch Google Cloud libraries BEFORE importing backend.main
import google.auth
from google.cloud import storage

# Wrap imports
with patch('google.auth.default', return_value=(MagicMock(), "test-project")) as mock_auth_default, \
     patch('google.cloud.storage.Client') as MockStorageClient:

    mock_instance = MockStorageClient.return_value
    mock_instance.bucket.return_value.blob.return_value.generate_signed_url.return_value = "https://mock-signed-url"

    from backend.main import app, storage_client

from fastapi.testclient import TestClient

@pytest.fixture
def client():
    return TestClient(app)

def test_ssrf_mitigation(client):
    """
    Verify that the application blocks access to disallowed buckets (SSRF fix).
    And verifies that allowed buckets are still accessible.
    """
    assert storage_client is not None
    storage_client.reset_mock()

    # 1. Test Blocked Access (Evil Bucket)
    evil_bucket = "evil-sensitive-bucket"
    mock_bucket = MagicMock()
    storage_client.bucket.return_value = mock_bucket

    uri = f"gs://{evil_bucket}/passwords.txt"
    response = client.get(f"/api/image?gcs_uri={uri}", follow_redirects=False)

    # Expectation: 400 Bad Request
    assert response.status_code == 400
    assert "Access to this bucket is not allowed" in response.json().get("detail", "")

    # Verify we DID NOT try to access the bucket
    assert storage_client.bucket.call_count == 0


    # 2. Test Allowed Access (Correct Bucket)
    # The default allowed bucket is property-images-{PROJECT_ID} -> property-images-test-project
    allowed_bucket = "property-images-test-project"

    # Setup successful sign
    mock_bucket_allowed = MagicMock()
    mock_blob_allowed = MagicMock()
    storage_client.bucket.return_value = mock_bucket_allowed
    mock_bucket_allowed.blob.return_value = mock_blob_allowed
    mock_blob_allowed.generate_signed_url.return_value = "https://good.url/image.jpg"

    uri_good = f"gs://{allowed_bucket}/listings/1.jpg"
    response_good = client.get(f"/api/image?gcs_uri={uri_good}", follow_redirects=False)

    # Expectation: 307 Redirect (Success)
    assert response_good.status_code == 307

    # Verify we accessed the correct bucket
    storage_client.bucket.assert_called_with(allowed_bucket)
