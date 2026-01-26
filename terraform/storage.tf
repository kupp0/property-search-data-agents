resource "google_storage_bucket" "images_bucket" {
  name          = "property-images-data-agent-${var.project_id}"
  project       = google_project.project.project_id
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}


