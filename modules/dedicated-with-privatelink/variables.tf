variable "confluent_cloud_api_key" {}
variable "confluent_cloud_api_secret" {}
variable "confluent_env" {}
variable "confluent_sa" {}
variable "region" {}
variable "azs" {}
variable "owner" {}
variable "cloud_provider" {
  default = "AWS"
}
variable "vpc_id" {}
variable "security_group_ids" {}
variable "subnet_ids" {
  type = list(any)
}
