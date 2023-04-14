
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.59"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.38.0"
    }
  }
}
