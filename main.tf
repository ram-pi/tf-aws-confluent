# locals
locals {
  privatelink = 0
}

# Create simple VPC
resource "aws_vpc" "main" {
  cidr_block = "10.1.0.0/16"

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.owner}-vpc",
    "owner" = var.owner_email
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name    = "${var.owner}-igw",
    "owner" = var.owner_email
  }
}

# Only Availability Zones (no Local Zones) https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones 
data "aws_availability_zones" "az" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Create N private subnets
resource "aws_subnet" "private" {
  count                = 1
  vpc_id               = aws_vpc.main.id
  availability_zone_id = data.aws_availability_zones.az.zone_ids[count.index]
  cidr_block           = "10.1.${count.index}.0/24"
  tags = {
    Name    = "${var.owner}-subnet-private-${count.index}",
    "owner" = var.owner_email
  }
}

# Create N public subnets
resource "aws_subnet" "public" {
  count                = 3
  vpc_id               = aws_vpc.main.id
  availability_zone_id = data.aws_availability_zones.az.zone_ids[count.index]
  cidr_block           = "10.1.${100 + count.index}.0/24"
  tags = {
    Name    = "${var.owner}-subnet-public-${count.index}",
    "owner" = var.owner_email
  }
}

# Create route table for private subnets
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id
  tags = {
    Name    = "${var.owner}-subnet-private-${count.index}-rt",
    "owner" = var.owner_email
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  route_table_id = aws_route_table.private[count.index].id
  subnet_id      = aws_subnet.private[count.index].id
}

# Create a route table for publics subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name    = "${var.owner}-subnet-public-rt",
    "owner" = var.owner_email
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_route" "igw" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.igw.id
}

# Create nat gws stuff for private
resource "aws_eip" "nat_gw" {
  count = length(aws_subnet.private)
  tags = {
    Name    = "${var.owner}-subnet-private-${count.index}-nat-gw-eip",
    "owner" = var.owner_email
  }
}

resource "aws_nat_gateway" "nat_gw" {
  count             = length(aws_subnet.private)
  connectivity_type = "public"
  allocation_id     = aws_eip.nat_gw[count.index].id
  subnet_id         = aws_subnet.public[count.index].id
  tags = {
    Name    = "${var.owner}-subnet-private-${count.index}-nat-gw",
    "owner" = var.owner_email
  }
}

resource "aws_route" "nat_gw" {
  count                  = length(aws_subnet.private)
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.private[count.index].id
  nat_gateway_id         = aws_nat_gateway.nat_gw[count.index].id
}

# Find instance ami and type
data "aws_ami" "ubuntu" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

data "aws_ec2_instance_type" "micro" {
  instance_type = "t2.small"
}

# Create private instances and related SGs
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "my_private_key" {
  depends_on = [
    tls_private_key.key
  ]
  content         = tls_private_key.key.private_key_pem
  filename        = "private.pem"
  file_permission = "0600"
}

resource "local_file" "my_public_key" {
  depends_on = [
    tls_private_key.key
  ]
  content         = tls_private_key.key.public_key_openssh
  filename        = "public.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "generate_key" {
  key_name = "private-instance-key"
  #public_key = tls_private_key.key.public_key_openssh
  public_key = local_file.my_public_key.content
  tags = {
    Name    = "${var.owner}-private-instance-key",
    "owner" = var.owner_email
  }
}

resource "aws_security_group" "private_instance_ssh" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id
  name   = "${var.owner}-private-instance-${count.index}-sg"
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ALL"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["10.1.${100 + count.index}.0/24"]
  }
  ingress {
    description = "PING"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${aws_vpc.main.cidr_block}"]
  }
  tags = {
    Name = "${var.owner}-private-instance-${count.index}-sg"
  }
}

resource "aws_instance" "private" {
  count                  = length(aws_subnet.private)
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = data.aws_ec2_instance_type.micro.instance_type
  key_name               = aws_key_pair.generate_key.key_name
  subnet_id              = aws_subnet.private[count.index].id
  vpc_security_group_ids = aws_security_group.private_instance_ssh[*].id
  tags = {
    Name    = "${var.owner}-private-instance-${count.index}",
    "owner" = var.owner_email
  }
}

# Create bastion instances and related sgs
resource "aws_instance" "bastion" {
  count                       = 1
  ami                         = data.aws_ami.ubuntu.id
  associate_public_ip_address = true
  instance_type               = data.aws_ec2_instance_type.micro.instance_type
  key_name                    = aws_key_pair.generate_key.key_name
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = ["${aws_security_group.bastion.id}"]
  tags = {
    Name    = "${var.owner}-bastion-instance-${count.index}",
    "owner" = var.owner_email
  }
}

# Capture the current public ip of the machine running this
data "http" "myip" {
  url = "http://ifconfig.me"
}

# Gather all the service ips from aws
data "http" "ec2_instance_connect" {
  url = "https://ip-ranges.amazonaws.com/ip-ranges.json"
}

# Specifically get the ec2 instance connect service ip so it can be whitelisted
locals {
  ec2_instance_connect_ip = [for e in jsondecode(data.http.ec2_instance_connect.response_body)["prefixes"] : e.ip_prefix if e.region == "${var.aws_region}" && e.service == "EC2_INSTANCE_CONNECT"]
}

resource "aws_security_group" "bastion" {
  vpc_id = aws_vpc.main.id
  name   = "${var.owner}-bastion-instance-sg"
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "All from ${local.ec2_instance_connect_ip[0]}, ${chomp(data.http.myip.response_body)}/32 and ${aws_vpc.main.cidr_block}"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["${local.ec2_instance_connect_ip[0]}", "${chomp(data.http.myip.response_body)}/32", "${aws_vpc.main.cidr_block}"]
  }
  ingress {
    description = "PING"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${aws_vpc.main.cidr_block}"]
  }
  tags = {
    Name = "${var.owner}-bastion-instance-sg"
  }
}

# MSK
resource "aws_msk_configuration" "conf" {
  kafka_versions = ["3.3.2"]
  name           = "${var.owner}-conf"

  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
PROPERTIES
}

resource "aws_kms_key" "kms" {
  description = "mks-kms"
  tags = {
    Name    = "${var.owner}-mks-kms",
    "owner" = var.owner_email
  }
}

# AWS Managed Kafka Service
resource "aws_msk_cluster" "cluster_1" {
  cluster_name           = "${var.owner}-cluster"
  kafka_version          = "3.3.2"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type = "kafka.m5.large"
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    client_subnets  = aws_subnet.public.*.id
    security_groups = aws_security_group.private_instance_ssh[*].id

    # public_access {
    #   type = "SERVICE_PROVIDED_EIPS"
    # }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.kms.arn
  }

  client_authentication {
    unauthenticated = true
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled = false
      }
      firehose {
        enabled = false
      }
      s3 {
        enabled = false
      }
    }
  }

  tags = {
    Name    = "${var.owner}-mks",
    "owner" = var.owner_email
  }
}

# AWS Glue Schema Registry 
resource "aws_glue_registry" "sr" {
  registry_name = "registry_1"

  tags = {
    Name    = "${var.owner}-glue_sr",
    "owner" = var.owner_email
  }
}

resource "aws_glue_schema" "schema_1" {
  schema_name       = "example"
  registry_arn      = aws_glue_registry.sr.arn
  data_format       = "AVRO"
  compatibility     = "NONE"
  schema_definition = "{\"type\": \"record\", \"name\": \"r1\", \"fields\": [ {\"name\": \"f1\", \"type\": \"int\"}, {\"name\": \"f2\", \"type\": \"string\"} ]}"
}

/* Confluent Cloud Private Link */
module "privatelink" {
  count  = local.privatelink
  source = "./modules/dedicated-with-privatelink"

  confluent_cloud_api_key    = var.confluent_cloud_api_key
  confluent_cloud_api_secret = var.confluent_cloud_api_secret
  confluent_env              = var.confluent_env
  confluent_sa               = var.confluent_sa
  region                     = var.aws_region
  owner                      = var.owner
  cloud_provider             = "AWS"
  azs                        = data.aws_availability_zones.az.zone_ids
  subnet_ids                 = aws_subnet.public.*.id
  security_group_ids         = [aws_security_group.bastion.id]
  vpc_id                     = aws_vpc.main.id
}
