output "project_id" {
  value = google_project.project.project_id
}

output "region" {
  value = var.region
}

output "alloydb_cluster_id" {
  value = google_alloydb_cluster.default.cluster_id
}

output "alloydb_instance_id" {
  value = google_alloydb_instance.primary.instance_id
}

output "backend_service_account" {
  value = google_service_account.backend_sa.email
}
