terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }

  cloud {
    organization = "dorinahashicorp"

    workspaces {
      name = "vault-enterprise"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Vault provider is configured in main.tf with HCP Vault credentials
