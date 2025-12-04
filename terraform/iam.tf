# IAM Configuration

# Get the Project Number
data "google_project" "project" {
  project_id = google_project.project.project_id
}

# Dedicated Service Account for Backend
resource "google_service_account" "backend_sa" {
  account_id   = "search-backend-sa"
  display_name = "Search Backend Service Account"
  project      = google_project.project.project_id
}

# Default Compute Engine Service Account (Used by Cloud Build)
locals {
  compute_sa_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Grant required roles to the Default Compute SA (for Cloud Build)
resource "google_project_iam_member" "compute_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/storage.objectViewer",
    "roles/artifactregistry.writer"
  ])

  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${local.compute_sa_email}"
}


# Grant required roles to the Dedicated Service Account
resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/alloydb.client",
    "roles/logging.logWriter",
    "roles/artifactregistry.repoAdmin",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/aiplatform.user",
    "roles/discoveryengine.editor",
    "roles/storage.objectAdmin",
    "roles/datastore.user" # Often needed for Vertex AI Search if using Datastore mode, but here it's likely Discovery Engine
  ])

  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.backend_sa.email}"

  depends_on = [google_project_service.services]
}


# AlloyDB Service Agent (Required for AI/ML integration)
# AlloyDB Service Agent (Required for AI/ML integration)
# We must explicitly wait for the service identity to be created/available.
resource "google_project_service_identity" "alloydb_sa" {
  provider = google-beta
  project  = google_project.project.project_id
  service  = "alloydb.googleapis.com"

  depends_on = [google_project_service.services]
}

# Cloud Build Service Account Permissions
# Required to push images to Artifact Registry
resource "google_project_iam_member" "cloudbuild_sa_ar_writer" {
  project = google_project.project.project_id
  role    = "roles/artifactregistry.repoAdmin"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

}

resource "google_project_iam_member" "alloydb_sa_vertex_ai" {
  project = google_project.project.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_project_service_identity.alloydb_sa.email}"
}
