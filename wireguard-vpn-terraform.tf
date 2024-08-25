# WireGuard VPN Server on AWS using Terraform

# Variables (unchanged)
variable "create_vpn" {
  description = "Set to true to create the VPN, false to destroy it"
  type        = bool
  default     = true
}

variable "wireguard_port" {
  description = "Port for WireGuard VPN"
  type        = number
  default     = 51820
}

variable "vpn_cidr" {
  description = "CIDR for VPN network"
  type        = string
  default     = "10.0.1.0/24"
}

variable "aws_region" {
  description = "AWS region to deploy the VPN"
  type        = string
  default     = "eu-central-1"
}

variable "client_public_key" {
  description = "WireGuard client public key"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

# Provider (unchanged)
provider "aws" {
  region = var.aws_region
}

# Generate WireGuard Keys (new)
resource "null_resource" "wireguard_keys" {
  count = var.create_vpn ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOT
      wg genkey | tee privatekey | wg pubkey > publickey
    EOT
  }
}

data "local_file" "private_key" {
  count    = var.create_vpn ? 1 : 0
  filename = "${path.module}/privatekey"
  depends_on = [null_resource.wireguard_keys]
}

data "local_file" "public_key" {
  count    = var.create_vpn ? 1 : 0
  filename = "${path.module}/publickey"
  depends_on = [null_resource.wireguard_keys]
}

# Generate EC2 Key Pair (unchanged)
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vpn_key_pair" {
  key_name   = "wireguard-vpn-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Data source for Ubuntu AMI (unchanged)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC (unchanged)
resource "aws_vpc" "vpn_vpc" {
  count                = var.create_vpn ? 1 : 0
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wireguard-vpn-vpc"
  }
}

# Subnet (unchanged)
resource "aws_subnet" "vpn_subnet" {
  count                   = var.create_vpn ? 1 : 0
  vpc_id                  = aws_vpc.vpn_vpc[0].id
  cidr_block              = var.vpn_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "wireguard-vpn-subnet"
  }
}

# Internet Gateway (unchanged)
resource "aws_internet_gateway" "vpn_igw" {
  count  = var.create_vpn ? 1 : 0
  vpc_id = aws_vpc.vpn_vpc[0].id

  tags = {
    Name = "wireguard-vpn-igw"
  }
}

# Route Table (unchanged)
resource "aws_route_table" "vpn_rt" {
  count  = var.create_vpn ? 1 : 0
  vpc_id = aws_vpc.vpn_vpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpn_igw[0].id
  }

  tags = {
    Name = "wireguard-vpn-rt"
  }
}

# Route Table Association (unchanged)
resource "aws_route_table_association" "vpn_rta" {
  count          = var.create_vpn ? 1 : 0
  subnet_id      = aws_subnet.vpn_subnet[0].id
  route_table_id = aws_route_table.vpn_rt[0].id
}

# Security Group (unchanged)
resource "aws_security_group" "vpn_sg" {
  count       = var.create_vpn ? 1 : 0
  name        = "wireguard-vpn-sg"
  description = "Security group for WireGuard VPN"
  vpc_id      = aws_vpc.vpn_vpc[0].id

  ingress {
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wireguard-vpn-sg"
  }
}

# EC2 Instance
resource "aws_instance" "vpn_server" {
  count                       = var.create_vpn ? 1 : 0
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.vpn_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.vpn_sg[0].id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.vpn_key_pair.key_name

  user_data = <<-EOF
              #!/bin/bash
              apt update && apt upgrade -y
              apt install -y wireguard

              echo "${data.local_file.private_key[0].content}" > /etc/wireguard/private.key
              chmod 600 /etc/wireguard/private.key
              echo "${data.local_file.public_key[0].content}" > /etc/wireguard/public.key

              # Create WireGuard configuration
              cat << EOT > /etc/wireguard/wg0.conf
              [Interface]
              PrivateKey = $(cat /etc/wireguard/private.key)
              Address = ${cidrhost(var.vpn_cidr, 1)}/24
              ListenPort = ${var.wireguard_port}
              PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
              PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE

              [Peer]
              PublicKey = ${var.client_public_key}
              AllowedIPs = ${cidrhost(var.vpn_cidr, 2)}/32
              EOT

              # Set correct permissions
              chmod 600 /etc/wireguard/wg0.conf

              # Enable IP forwarding
              echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
              sysctl -p

              # Start WireGuard
              systemctl enable wg-quick@wg0.service
              systemctl start wg-quick@wg0.service
              EOF

  tags = {
    Name = "wireguard-vpn-server"
  }
}

# Elastic IP (unchanged)
resource "aws_eip" "vpn_eip" {
  count    = var.create_vpn ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.vpn_server[0].id

  tags = {
    Name = "wireguard-vpn-eip"
  }
}

# Outputs (unchanged)
output "vpn_public_ip" {
  value = var.create_vpn ? aws_eip.vpn_eip[0].public_ip : "VPN is not created"
}

output "wireguard_server_public_key" {
  value = var.create_vpn ? data.local_file.public_key[0].content : "VPN is not created"
}

output "wireguard_server_private_key" {
  value     = var.create_vpn ? data.local_file.private_key[0].content : "VPN is not created"
  sensitive = true
}

output "ec2_key_pair_name" {
  value = aws_key_pair.vpn_key_pair.key_name
}

output "ec2_private_key" {
  value     = tls_private_key.ec2_key.private_key_pem
  sensitive = true
}

output "ec2_public_key" {
  value = tls_private_key.ec2_key.public_key_openssh
}
