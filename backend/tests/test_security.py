import os
import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch
import sys

# Ensure backend is in path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Set necessary environment variables before importing app to avoid errors during import
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["AGENT_CONTEXT_SET_ID"] = "test-context"
os.environ["DB_PASSWORD"] = "test-pass"

# We patch google.auth.default to avoid real auth attempts during import
with patch("google.auth.default", return_value=(MagicMock(), "test-project")):
    # We also patch storage.Client to avoid real connection attempts
    with patch("google.cloud.storage.Client"):
        from main import app

client = TestClient(app)

def test_ssrf_vulnerability_blocked():
    """
    Test that the application BLOCKS accessing arbitrary buckets (SSRF).
    """

    # Mock the storage_client instance in backend.main
    with patch("main.storage_client") as mock_storage_client:
        # The attacker tries to access a bucket that is NOT the intended one
        # Expected allowed bucket is "property-images-test-project"
        evil_bucket = "evil-bucket"
        url = f"/api/image?gcs_uri=gs://{evil_bucket}/secret.jpg"

        response = client.get(url, follow_redirects=False)

        # It should return 400 Bad Request
        assert response.status_code == 400
        assert response.json()["detail"] == "Invalid GCS bucket."

        # Verify that bucket() was NOT called
        mock_storage_client.bucket.assert_not_called()

def test_allowed_bucket_access():
    """
    Test that the application ALLOWS accessing the correct bucket.
    """

    with patch("main.storage_client") as mock_storage_client:
        mock_bucket = MagicMock()
        mock_storage_client.bucket.return_value = mock_bucket
        mock_blob = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_blob.generate_signed_url.return_value = "https://signed-url.com"

        # The correct bucket
        allowed_bucket = "property-images-test-project"
        url = f"/api/image?gcs_uri=gs://{allowed_bucket}/listing.jpg"

        response = client.get(url, follow_redirects=False)

        # It should return a redirect to the signed URL
        assert response.status_code == 307
        assert response.headers["location"] == "https://signed-url.com"

        # Verify bucket was called
        mock_storage_client.bucket.assert_called_with(allowed_bucket)
