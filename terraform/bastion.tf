# Bastion Host for Local Debugging
# This instance allows SSH tunneling to access the Private IP AlloyDB instance.

resource "google_service_account" "bastion_sa" {
  account_id   = "bastion-sa"
  display_name = "Bastion Service Account"
  project      = google_project.project.project_id
}

resource "google_compute_instance" "bastion" {
  name         = "search-demo-bastion"
  machine_type = "e2-micro"
  zone         = "${var.region}-b"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  project = google_project.project.project_id

  network_interface {
    network = google_compute_network.vpc_network.id
    # No public IP needed if we use IAP
    # But for IAP to work, we need firewall rules.
  }

  service_account {
    email  = google_service_account.bastion_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  tags = ["bastion"]
}

# Grant AlloyDB Client role to Bastion SA
resource "google_project_iam_member" "bastion_sa_roles" {
  for_each = toset([
    "roles/alloydb.client",
    "roles/logging.logWriter",
    "roles/serviceusage.serviceUsageConsumer"
  ])

  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.bastion_sa.email}"
}


# Firewall rule to allow IAP SSH
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.vpc_network.id
  project = google_project.project.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IP range for IAP
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

# Output the Bastion name for the script
output "bastion_instance_name" {
  value = google_compute_instance.bastion.name
}

output "bastion_zone" {
  value = google_compute_instance.bastion.zone
}
