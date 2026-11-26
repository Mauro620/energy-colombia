terraform {
  required_version = ">= 1.10" # use_lockfile en el backend S3 (sin DynamoDB)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # El bucket no se escribe aqui (no admite variables): `make tf-init` lo pasa con -backend-config="bucket=..."
  backend "s3" {
    key          = "energia-db/e2/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Proyecto = "energia-db"
      Entrega  = "E2"
    }
  }
}
