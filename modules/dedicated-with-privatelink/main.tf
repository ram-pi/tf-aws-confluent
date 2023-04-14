data "confluent_environment" "c_env" {
  id = var.confluent_env
}

data "confluent_service_account" "cc_sa" {
  id = var.confluent_sa
}

data "aws_vpc" "privatelink" {
  id = var.vpc_id
}

data "aws_caller_identity" "current" {}

resource "confluent_network" "my_private_link" {
  display_name     = "${var.owner} Private Link Network"
  cloud            = var.cloud_provider
  region           = var.region
  connection_types = ["PRIVATELINK"]
  zones            = var.azs
  environment {
    id = data.confluent_environment.c_env.id
  }
}

resource "confluent_private_link_access" "my_confluent_private_link_access" {
  display_name = "${var.cloud_provider} Private Link Access"
  aws {
    account = data.aws_caller_identity.current.account_id
  }
  environment {
    id = data.confluent_environment.c_env.id
  }
  network {
    id = confluent_network.my_private_link.id
  }
}

resource "aws_security_group" "privatelink" {
  # Ensure that SG is unique, so that this module can be used multiple times within a single VPC
  name        = "ccloud-privatelink_${local.bootstrap_prefix}_${var.vpc_id}"
  description = "Confluent Cloud Private Link minimal security group for ${confluent_kafka_cluster.k_cluster.bootstrap_endpoint} in ${var.vpc_id}"
  vpc_id      = data.aws_vpc.privatelink.id

  ingress {
    # only necessary if redirect support from http/https is desired
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.privatelink.cidr_block]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.privatelink.cidr_block]
  }

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.privatelink.cidr_block]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "my_vpc_endpoint" {
  vpc_id            = var.vpc_id
  service_name      = confluent_network.my_private_link.aws[0].private_link_endpoint_service
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.privatelink.id,
  ]

  subnet_ids          = var.subnet_ids
  private_dns_enabled = false

  tags = {
    Name    = "endpoint-${var.owner}"
    "owner" = var.owner
  }

  depends_on = [
    confluent_private_link_access.my_confluent_private_link_access,
  ]
}

resource "confluent_kafka_cluster" "k_cluster" {
  display_name = "private"
  availability = "MULTI_ZONE"
  cloud        = var.cloud_provider
  region       = var.region

  dedicated {
    cku = 2
  }

  environment {
    id = data.confluent_environment.c_env.id
  }

  network {
    id = confluent_network.my_private_link.id
  }
}

resource "confluent_api_key" "kafka-api-key" {
  display_name = "tf-kafka-api-key"
  description  = "tf-kafka-api-key"

  disable_wait_for_ready = true

  # Set optional `disable_wait_for_ready` attribute (defaults to `false`) to `true` if the machine where Terraform is not run within a private network
  # disable_wait_for_ready = true

  owner {
    id          = data.confluent_service_account.cc_sa.id
    api_version = data.confluent_service_account.cc_sa.api_version
    kind        = data.confluent_service_account.cc_sa.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.k_cluster.id
    api_version = confluent_kafka_cluster.k_cluster.api_version
    kind        = confluent_kafka_cluster.k_cluster.kind

    environment {
      id = data.confluent_environment.c_env.id
    }
  }
}

locals {
  hosted_zone = length(regexall(".glb", confluent_kafka_cluster.k_cluster.bootstrap_endpoint)) > 0 ? replace(regex("^[^.]+-([0-9a-zA-Z]+[.].*):[0-9]+$", confluent_kafka_cluster.k_cluster.bootstrap_endpoint)[0], "glb.", "") : regex("[.]([0-9a-zA-Z]+[.].*):[0-9]+$", confluent_kafka_cluster.k_cluster.bootstrap_endpoint)[0]
}

locals {
  glb_hosted_zone = regex("[.]([0-9a-zA-Z]+[.].*):[0-9]+$", confluent_kafka_cluster.k_cluster.bootstrap_endpoint)[0]
}

locals {
  bootstrap_prefix = split(".", confluent_kafka_cluster.k_cluster.bootstrap_endpoint)[0]
}

locals {
  endpoint_prefix = split(".", aws_vpc_endpoint.my_vpc_endpoint.dns_entry[0]["dns_name"])[0]
}

resource "aws_route53_zone" "privatelink" {
  name = local.hosted_zone

  vpc {
    vpc_id = var.vpc_id
  }

  comment = "Managed by Terraform for ${var.owner}"

  tags = {
    description = "${var.owner} tf hosted zone"
  }
}

resource "aws_route53_record" "privatelink" {
  count   = length(var.subnet_ids) == 1 ? 0 : 1
  zone_id = aws_route53_zone.privatelink.zone_id
  name    = "*.${aws_route53_zone.privatelink.name}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.my_vpc_endpoint.dns_entry[0]["dns_name"]
  ]
}

# https://www.youtube.com/watch?v=tZCrVFSj4XY&t=1s 
# resource "aws_route53_record" "privatelink-zonal" {
#   count = length(var.subnet_ids)

#   zone_id = aws_route53_zone.privatelink.zone_id
#   name    = length(var.subnet_ids) == 1 ? "*" : "*.${var.azs[count.index]}-"
#   type    = "CNAME"
#   ttl     = "60"
#   records = [
#     format("%s-%s%s",
#       local.endpoint_prefix,
#       var.azs[count.index], // data.aws_availability_zone.privatelink[each.key].name
#       replace(aws_vpc_endpoint.my_vpc_endpoint.dns_entry[0]["dns_name"], local.endpoint_prefix, "")
#     )
#   ]
# }
