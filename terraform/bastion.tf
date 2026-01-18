# Bastion host for accessing Aurora and MSK resources

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for bastion host
resource "aws_security_group" "bastion_sg" {
  count       = var.create_bastion ? 1 : 0
  name        = "bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.this.id

  # SSH access from anywhere (you can restrict this to your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# IAM role for SSM (Systems Manager) access
resource "aws_iam_role" "bastion_role" {
  count = var.create_bastion ? 1 : 0
  name  = "bastion-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "bastion-ssm-role"
  }
}

# Attach SSM managed policy for Session Manager access
resource "aws_iam_role_policy_attachment" "bastion_ssm_policy" {
  count      = var.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow bastion to describe RDS resources for getting endpoints
resource "aws_iam_role_policy" "bastion_rds_read" {
  count = var.create_bastion ? 1 : 0
  name  = "bastion-rds-read-policy"
  role  = aws_iam_role.bastion_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "bastion_profile" {
  count = var.create_bastion ? 1 : 0
  name  = "bastion-instance-profile"
  role  = aws_iam_role.bastion_role[0].name
}

# EC2 bastion instance
resource "aws_instance" "bastion" {
  count                  = var.create_bastion ? 1 : 0
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion_sg[0].id]
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile[0].name

  # User data to install MySQL client
  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y

              # Install MySQL client
              yum install -y mariadb105

              # Install useful tools
              yum install -y telnet nc

              # Install Kafka tools (optional, for testing MSK)
              wget https://archive.apache.org/dist/kafka/3.5.1/kafka_2.13-3.5.1.tgz
              tar -xzf kafka_2.13-3.5.1.tgz -C /opt/
              ln -s /opt/kafka_2.13-3.5.1 /opt/kafka

              echo "Bastion host setup complete" > /tmp/setup-complete.txt
              EOF

  tags = {
    Name = "msk-workshop-bastion"
  }

  # Ensure we can SSH if needed
  associate_public_ip_address = true
}
