provider "aws" {
  region = "us-east-1"
}

terraform {
  # Relaxed from the original exact pin of "1.3.9" so the template also works
  # with the newer Terraform releases people have installed locally.
  required_version = ">= 1.3.9"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Bumped from the original "4.55.0" (Feb 2023). The old provider predates
      # the AL2023 EKS node AMI type, which is required for Kubernetes >= 1.33.
      version = "~> 5.80"
    }
  }
}
