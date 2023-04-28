output "bootstrap" {
  value = confluent_kafka_cluster.dedicated.bootstrap_endpoint
}

output "kafka_api_key" {
  value = confluent_api_key.kafka-api-key.id
}

output "kafka_api_key_secret" {
  value     = confluent_api_key.kafka-api-key.secret
  sensitive = true
}
