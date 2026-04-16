terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "simpletimeservice-terraform-state-328263827642"
    key            = "simpletimeservice/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "simpletimeservice-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}
