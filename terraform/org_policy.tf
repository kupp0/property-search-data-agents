resource "google_project_organization_policy" "iam_allowed_policy_member_domains" {
  project    = google_project.project.project_id
  constraint = "constraints/iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      all = true
    }
  }
}
