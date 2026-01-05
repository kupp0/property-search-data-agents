# IAM Configuration

# Get the Project Number
data "google_project" "project" {
  project_id = google_project.project.project_id
}


resource "google_service_account" "search_backend_sa" {
  account_id   = "search-backend-sa"
  display_name = "Search Backend Service Account"
  project      = google_project.project.project_id
}

# Grant required roles to the Service Account
resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/alloydb.client",
    "roles/logging.logWriter",
    "roles/artifactregistry.repoAdmin",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/aiplatform.user",
    "roles/discoveryengine.editor",
    "roles/storage.objectAdmin",
    "roles/secretmanager.secretAccessor"
  ])

  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.search_backend_sa.email}"

  depends_on = [google_project_service.services]
}

# We must explicitly wait for the Cloud Build service identity to be created.
resource "google_project_service_identity" "cloudbuild_sa" {
  provider = google-beta
  project  = google_project.project.project_id
  service  = "cloudbuild.googleapis.com"
  depends_on = [google_project_service.services]
}

# We must explicitly wait for the AlloyDB service identity to be created.
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
  member  = "serviceAccount:${google_project_service_identity.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "alloydb_sa_vertex_ai" {
  project = google_project.project.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_project_service_identity.alloydb_sa.email}"
}
