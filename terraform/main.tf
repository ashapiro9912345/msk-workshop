locals {
  az_count = length(var.public_subnets)
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = { Name = "msk-workshop-vpc" }
}

resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "private-${count.index + 1}" }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "msk_sg" {
  name   = "msk-sg"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "rds-sg"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redshift_sg" {
  name   = "redshift-sg"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.msk_cluster_name
  kafka_version          = "3.2.0"
  number_of_broker_nodes = local.az_count

  broker_node_group_info {
    instance_type = var.msk_instance_type
    client_subnets = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk_sg.id]
    
  }
}

resource "aws_db_subnet_group" "aurora_subnets" {
  name       = "aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = var.aurora_cluster_identifier
  engine                  = "aurora-mysql"
  engine_mode             = "provisioned"
  master_username         = var.db_master_username
  master_password         = var.db_master_password
  db_subnet_group_name    = aws_db_subnet_group.aurora_subnets.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  tags = { Name = var.aurora_cluster_identifier }
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count              = 1
  identifier         = "${var.aurora_cluster_identifier}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r5.large"
  engine             = aws_rds_cluster.aurora.engine
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name       = "redshift-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier = var.redshift_cluster_identifier
  node_type          = var.redshift_node_type
  number_of_nodes    = var.redshift_number_of_nodes
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids     = [aws_security_group.redshift_sg.id]
  skip_final_snapshot = true
  publicly_accessible = false
  tags = { Name = var.redshift_cluster_identifier }
}
