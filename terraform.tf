terraform {
  required_version = ">= 1.9"

  # HCP Terraform backend configuration
  cloud {
    organization = "Infragoose"

    workspaces {
      name = "vault-enterprise"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "vault-enterprise"
      ManagedBy   = "terraform"
      Workspace   = "vault-enterprise"
    }
  }
}
