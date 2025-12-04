resource "google_project_organization_policy" "iam_allowed_policy_member_domains" {
  project    = google_project.project.project_id
  constraint = "constraints/iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      all = true
    }
  }
}



resource "google_project_organization_policy" "compute_vm_external_ip_access" {
  project    = google_project.project.project_id
  constraint = "constraints/compute.vmExternalIpAccess"

  list_policy {
    allow {
      all = true
    }
  }
}

