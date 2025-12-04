resource "google_alloydb_cluster" "default" {
  cluster_id = var.alloydb_cluster_id
  location   = var.region
  project    = google_project.project.project_id
  
  database_version = "POSTGRES_16"

  network_config {
    network = google_compute_network.vpc_network.id
  }

  initial_user {
    user     = "postgres"
    password = var.db_password
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_alloydb_instance" "primary" {
  provider      = google-beta
  cluster       = google_alloydb_cluster.default.name
  instance_id   = var.alloydb_instance_id
  instance_type = "PRIMARY"
  availability_type = "ZONAL"

  machine_config {
    cpu_count = 2
  }

  database_flags = {
    "alloydb_ai_nl.enabled"                          = "on"
    "google_ml_integration.enable_ai_query_engine"   = "on"
    "scann.enable_zero_knob_index_creation"          = "on"
    "password.enforce_complexity"                    = "on"
    "google_db_advisor.enable_auto_advisor"          = "on"
    "google_db_advisor.auto_advisor_schedule"        = "EVERY 24 HOURS"
  }

  query_insights_config {
    query_plans_per_minute = 5
  }

  observability_config {
    enabled                       = true
    # assistive_experiences_enabled = true # Requires Gemini Cloud Assist to be enabled on the project/user first
  }

  # Enable Public IP
  # Public IP Disabled for security
  network_config {
    enable_public_ip = false
  }
}
