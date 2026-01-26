output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}



output "alloydb_cluster_id" {
  value = var.alloydb_cluster_id
}

output "alloydb_instance_id" {
  value = var.alloydb_instance_id
}

output "alloydb_cluster_ip" {
  value = google_compute_global_address.private_ip_address.address
}

output "bastion_ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.bastion.name} --zone ${var.zone} --tunnel-through-iap"
}


output "alloydb_sa_email" {
  value = google_project_service_identity.alloydb_sa.email
}

output "db_host" {
  value = google_alloydb_instance.primary.ip_address
}

output "db_user" {
  value = var.db_user
}

output "db_pass" {
  value = var.db_password
  sensitive = true
}

output "db_name" {
  value = var.db_name
}

output "instance_connection_name" {
  description = "The connection name of the AlloyDB instance to be used in env vars"
  value       = "projects/${var.project_id}/locations/${var.region}/clusters/${var.alloydb_cluster_id}/instances/${var.alloydb_instance_id}"
}
