output "bastion_public_ip" {
  value = aws_instance.bastion[*].public_ip
}

output "internal_private_ip" {
  value = aws_instance.private[*].private_ip
}

output "availability_zones" {
  value = data.aws_availability_zones.az.zone_ids[*]
}

output "subnet_ids" {
  value = aws_subnet.public[*].id
}

output "zookeeper_connect_string" {
  value = aws_msk_cluster.cluster_1.zookeeper_connect_string
}

output "bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.cluster_1.bootstrap_brokers_tls
}

output "bootstrap_brokers_public_sasl_iam" {
  value = aws_msk_cluster.cluster_1.bootstrap_brokers_public_sasl_iam
}

output "aws_glue_registry_arn" {
  value = aws_glue_registry.sr.arn
}

output "aws_glue_schema_id" {
  value = aws_glue_schema.schema_1.id
}

output "aws_vpc_id" {
  value = aws_vpc.main.id
}

/* Confluent Cloud Outputs */
output "bootstrap_endpoint" {
  value = module.privatelink.*.bootstrap_endpoint
}

output "dns_domain" {
  value = module.privatelink.*.dns_domain
}

output "dns_zonal_domains" {
  value = module.privatelink.*.dns_zonal_domains
}

output "kafka_api_key" {
  value = module.privatelink.*.kafka_api_key
}

output "kafka_api_secret" {
  sensitive = true
  value     = module.privatelink.*.kafka_api_secret
}

output "vpc_endpoint_entry" {
  value = module.privatelink.*.vpc_endpoint_entry
}

output "hosted_zone" {
  value = module.privatelink.*.hosted_zone
}

output "bootstrap_prefix" {
  value = module.privatelink.*.bootstrap_prefix
}

output "endpoint_prefix" {
  value = module.privatelink.*.endpoint_prefix
}
