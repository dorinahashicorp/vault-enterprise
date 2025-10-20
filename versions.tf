terraform {
  required_version = ">= 1.1.0"

  cloud {
    hostname = "app.terraform.io"
    organization = "Infragoose"

    workspaces {
      # IMPORTANT: update this to the exact workspace name you use in your
      # Terraform Cloud / HCP organization. I used "Vault-Deployments" as a
      # placeholder — change it if your workspace has a different name.
      name = "Vault-Deployments"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # Pin to 4.x series to maintain compatibility with the vpc module used
      version = "~> 4.0"
    }
  }
}
