terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# =======================================================
# Primary AWS Provider
# =======================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Production"
      ManagedBy   = "Terraform"
      Owner       = "DevOps"
      RegionRole  = "Primary"
    }
  }
}

# =======================================================
# DR AWS Provider
# =======================================================

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Production"
      ManagedBy   = "Terraform"
      Owner       = "DevOps"
      RegionRole  = "DR"
    }
  }
}
