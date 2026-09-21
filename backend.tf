terraform {

  cloud {
    organization = "fardust"
    workspaces {
      name = "personal-stack-infrastructure"
    }
  }
}
