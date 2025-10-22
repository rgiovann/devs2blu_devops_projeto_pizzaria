terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }

    random = {
    source  = "hashicorp/random"
    version = "~> 3.7"
}

}

  backend "s3" {
    bucket         = "leopoldo-pizzaria-bucket-terraform-state"  # ← S3
    key            = "pizzaria/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"                      # ← DynamoDB
  }

  required_version = ">= 1.5"

}

provider "aws" {
  region = "us-east-2"
}
