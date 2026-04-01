import os
import sys
import pytest
from unittest.mock import MagicMock, patch

# Configure environment before importing backend.main
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["ALLOWED_GCS_BUCKET"] = "allowed-bucket"
os.environ["AGENT_CONTEXT_SET_ID"] = "ctx-123"
os.environ["DB_HOST"] = "localhost"
os.environ["DB_PASSWORD"] = "dummy"

# Mock Google Cloud libraries PROPERLY
# Create the leaf modules
mock_auth_module = MagicMock()
mock_auth_module.default.return_value = (MagicMock(), "test-project")

mock_storage_module = MagicMock()
mock_storage_client_cls = MagicMock()
mock_storage_module.Client = mock_storage_client_cls
mock_storage_instance = MagicMock()
mock_storage_client_cls.return_value = mock_storage_instance

# Mock the 'google' package
mock_google = MagicMock()
mock_google.auth = mock_auth_module

# Mock 'google.cloud' package
mock_google_cloud = MagicMock()
mock_google_cloud.storage = mock_storage_module
mock_google.cloud = mock_google_cloud

# Register in sys.modules
sys.modules["google"] = mock_google
sys.modules["google.auth"] = mock_auth_module
sys.modules["google.cloud"] = mock_google_cloud
sys.modules["google.cloud.storage"] = mock_storage_module

# Now import the app
sys.path.append(os.getcwd())

from backend.main import app, storage_client

from fastapi.testclient import TestClient

client = TestClient(app)

def test_ssrf_protection_blocks_external_bucket():
    """
    Verify that accessing a GCS bucket not in the allowed list returns 403.
    """
    # The vulnerability: Accessing 'evil-bucket' which is not 'allowed-bucket'
    response = client.get("/api/image?gcs_uri=gs://evil-bucket/malware.exe", follow_redirects=False)

    # Assert 403 Forbidden
    # Currently, this will return 307 because the mock succeeds and there is no check.
    assert response.status_code == 403

def test_ssrf_protection_allows_configured_bucket():
    """
    Verify that accessing the configured allowed bucket works.
    """
    # Setup mock behavior for success path
    mock_blob = MagicMock()
    mock_blob.generate_signed_url.return_value = "https://signed.url"

    # Configure the mock instance that was used during import
    # storage_client is the instance we mocked (mock_storage_instance)
    mock_storage_instance.bucket.return_value.blob.return_value = mock_blob

    response = client.get("/api/image?gcs_uri=gs://allowed-bucket/image.jpg", follow_redirects=False)

    # Should redirect to signed URL
    assert response.status_code == 307
    assert response.headers["location"] == "https://signed.url"
