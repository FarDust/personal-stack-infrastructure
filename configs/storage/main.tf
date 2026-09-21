resource "google_storage_bucket" "gpu_idle_lab_dvc" {
  project  = var.project_id
  name     = var.gpu_idle_lab_dvc_bucket_name
  location = var.gcp_region

  lifecycle {
    prevent_destroy = true
  }

  force_destroy               = false
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = {
    app     = "gpu-idle-lab"
    purpose = "dvc-artifacts"
  }
}
