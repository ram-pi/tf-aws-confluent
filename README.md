# Introduction

Demo setup for Confluent Private Dedicated cluster with AWS Transit Gateway

## Prerequisites

- Confluent environment
- Confluent Cloud Service Account with API Key and API Secret
- AWS Access Key and AWS Secret Key

## terraform.tfvars

```
service_account = "sa-***"
env             = "env-***"
aws_region      = "eu-central-1"
api_key         = "***"
secret          = "***"
```

## Running

```
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars
terraform apply
```
