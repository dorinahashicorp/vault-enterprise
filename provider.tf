provider "aws" {
  region = var.aws_region
}

terraform {
  # Keep state in Terraform Cloud (configured in versions.tf). No local
  # backend block here since we rely on the cloud stanza above.
}
