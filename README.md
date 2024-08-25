# WireGuard VPN on AWS using Terraform

This Terraform script automates the setup of a WireGuard VPN server on AWS. It creates all necessary AWS resources and configures WireGuard, allowing for easy deployment and management of a personal VPN.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [What This Script Does](#what-this-script-does)
3. [How It Works](#how-it-works)
4. [Usage](#usage)
5. [Variables](#variables)
6. [Outputs](#outputs)
7. [Security Considerations](#security-considerations)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

- Terraform installed on your local machine
- AWS CLI configured with appropriate credentials
- WireGuard tools installed on your local machine (for key generation)

## What This Script Does

This Terraform script sets up the following:

1. A VPC in the specified AWS region
2. A public subnet within the VPC
3. An Internet Gateway for the VPC
4. A route table for internet access
5. A security group allowing WireGuard and SSH traffic
6. An EC2 instance to run the WireGuard server
7. An Elastic IP address for the server
8. WireGuard installation and configuration on the EC2 instance

## How It Works

1. **Network Setup**: The script creates a VPC, subnet, internet gateway, and route table to provide a network environment for the VPN server.

2. **Security**: A security group is created to control inbound and outbound traffic, allowing WireGuard UDP traffic and SSH access.

3. **Key Generation**: WireGuard keys are generated locally using the `wg` command-line tool.

4. **EC2 Instance**: An Ubuntu EC2 instance is launched in the public subnet.

5. **WireGuard Installation**: The user data script installs WireGuard on the EC2 instance.

6. **WireGuard Configuration**: The script creates a WireGuard configuration file (`wg0.conf`) on the EC2 instance using the generated keys and specified settings.

7. **Service Activation**: WireGuard is enabled and started as a systemd service on the EC2 instance.

## Usage

1. Clone this repository:
   ```
   git clone <repository-url>
   cd <repository-directory>
   ```

2. Initialize Terraform:
   ```
   terraform init
   ```

3. Customize the variables in `terraform.tfvars` or pass them via command line.

4. Apply the Terraform configuration:
   ```
   terraform apply
   ```

5. After successful application, Terraform will output the VPN server's public IP and the WireGuard server's public key.

## Variables

- `create_vpn`: Boolean to control VPN creation/destruction
- `wireguard_port`: Port for WireGuard VPN (default: 51820)
- `vpn_cidr`: CIDR for VPN network
- `aws_region`: AWS region for deployment
- `client_public_key`: WireGuard client public key
- `instance_type`: EC2 instance type

## Outputs

- `vpn_public_ip`: Public IP address of the VPN server
- `wireguard_server_public_key`: WireGuard server's public key
- `ec2_key_pair_name`: Name of the created EC2 key pair
- `ec2_public_key`: Public key of the EC2 instance

## Security Considerations

- The script opens SSH (port 22) to the public internet. Consider restricting this to your IP address.
- Ensure you keep your WireGuard client private key secure.
- Regularly update the EC2 instance for security patches.

## Troubleshooting

- If WireGuard fails to start, check the EC2 instance's system log.
- Ensure that the client public key is correctly specified in the Terraform variables.
- Verify that the security group allows traffic on the specified WireGuard port.

---

For more detailed information on WireGuard, visit the [official WireGuard website](https://www.wireguard.com/).

For AWS-specific questions, refer to the [AWS Documentation](https://docs.aws.amazon.com/).
