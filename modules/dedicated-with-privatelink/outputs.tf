output "display_name" {
  value = confluent_kafka_cluster.k_cluster.display_name
}

output "bootstrap_endpoint" {
  value = confluent_kafka_cluster.k_cluster.bootstrap_endpoint
}

output "dns_domain" {
  value = confluent_network.my_private_link.dns_domain
}

output "dns_zonal_domains" {
  value = confluent_network.my_private_link.zonal_subdomains
}

output "kafka_api_key" {
  value = confluent_api_key.kafka-api-key.id
}

output "kafka_api_secret" {
  sensitive = true
  value     = confluent_api_key.kafka-api-key.secret
}

output "vpc_endpoint_entry" {
  value = aws_vpc_endpoint.my_vpc_endpoint.dns_entry[0]
}

output "hosted_zone" {
  value = local.hosted_zone
}

output "bootstrap_prefix" {
  value = local.bootstrap_prefix
}

output "endpoint_prefix" {
  value = local.endpoint_prefix
}
