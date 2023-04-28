data "aws_vpc" "peering_vpc" {
  id = var.vpc_id
}

# Environment 
data "confluent_environment" "main" {
  id = var.env
}

data "confluent_service_account" "cc_sa" {
  id = var.service_account
}

data "aws_availability_zones" "non_local" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

/* 
* Confluent Cloud Network and Attachment 
*/

# Create the network for the tgw
resource "confluent_network" "tgw" {
  display_name     = "${var.owner}-tgw-network-${random_id.confluent.hex}"
  cloud            = "AWS"
  region           = var.aws_region
  cidr             = "10.10.0.0/16"
  zones            = slice(data.aws_availability_zones.non_local.zone_ids, 0, 3)
  connection_types = ["TRANSITGATEWAY"]
  environment {
    id = data.confluent_environment.main.id
  }
}

# Create the tgw attachment
resource "confluent_transit_gateway_attachment" "main" {
  display_name = "${var.owner}-tgw-attachment-${random_id.confluent.hex}"
  aws {
    ram_resource_share_arn = aws_ram_resource_share.confluent.arn
    transit_gateway_id     = aws_ec2_transit_gateway.main.id
    routes                 = [data.aws_vpc.peering_vpc.cidr_block]
  }
  environment {
    id = data.confluent_environment.main.id
  }
  network {
    id = confluent_network.tgw.id
  }
}

# Provision the cluster in the network
resource "confluent_kafka_cluster" "dedicated" {
  display_name = "${var.owner}-dedicated-tgw"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  dedicated {
    cku = 1
  }
  environment {
    id = data.confluent_environment.main.id
  }
  network {
    id = confluent_network.tgw.id
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
    id          = confluent_kafka_cluster.dedicated.id
    api_version = confluent_kafka_cluster.dedicated.api_version
    kind        = confluent_kafka_cluster.dedicated.kind

    environment {
      id = data.confluent_environment.main.id
    }
  }
}

/* 
* AWS TGW
*/


# Create transit gateway 
resource "aws_ec2_transit_gateway" "main" {
  description = "tgw-${random_id.aws.hex}"
  tags = {
    Name    = "tgw-example-${var.owner}",
    "owner" = var.owner_email
  }
}
# Configure ram share
resource "aws_ram_resource_share" "confluent" {
  name                      = "resource-share-with-confluent-${random_id.aws.hex}"
  allow_external_principals = true

}
resource "aws_ram_principal_association" "confluent" {
  principal          = confluent_network.tgw.aws[0].account
  resource_share_arn = aws_ram_resource_share.confluent.arn
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.confluent.arn
}

# Find and set to auto-accept the transit gateway attachment from Confluent
data "aws_ec2_transit_gateway_vpc_attachment" "accepter" {
  id = confluent_transit_gateway_attachment.main.aws[0].transit_gateway_attachment_id
}

resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "accepter" {
  transit_gateway_attachment_id = data.aws_ec2_transit_gateway_vpc_attachment.accepter.id
}

# Create an attachment for the peer, AWS, VPC to the transit gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "attachment" {
  subnet_ids         = var.subnets_ids
  vpc_id             = data.aws_vpc.peering_vpc.id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
}

# Create routes from the subnets to the transit gateway CIDR
resource "aws_route" "tgw" {
  route_table_id         = var.route_table_id
  destination_cidr_block = confluent_network.tgw.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

# resource "aws_route" "tgw_public" {
#   count                  = length(aws_subnet.public)
#   route_table_id         = aws_route_table.public[count.index].id
#   destination_cidr_block = confluent_network.tgw.cidr
#   transit_gateway_id     = aws_ec2_transit_gateway.main.id
# }

# data "aws_subnet" "input" {
#   filter {
#     name   = "vpc-id"
#     values = [aws_vpc.main.id]
#   }
# }

# # Find the routing table
# data "aws_route_tables" "rts" {
#   vpc_id = aws_vpc.main.id
# }

# resource "aws_route" "r" {
#   # count                  = length(data.aws_route_tables.rts.ids)
#   count                  = length(aws_subnet.public)
#   route_table_id         = tolist(data.aws_route_tables.rts.ids)[count.index]
#   destination_cidr_block = confluent_network.tgw.cidr
#   transit_gateway_id     = aws_ec2_transit_gateway.main.id
# }
