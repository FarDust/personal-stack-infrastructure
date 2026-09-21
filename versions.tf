terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0, < 8.0.0"
    }
  }

  required_version = ">= 1.16.3, < 2.0.0"
}
