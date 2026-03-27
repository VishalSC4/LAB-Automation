# Generate random passwords for each student
resource "random_password" "student_passwords" {
  count            = var.student_count
  length           = 16
  special          = true
  override_special = "!@#$%"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 1
}

# Generate SSH key pair for admin access
resource "tls_private_key" "admin_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "admin_key" {
  key_name   = "${var.project_name}-admin-key"
  public_key = tls_private_key.admin_key.public_key_openssh

  tags = {
    Name = "${var.project_name}-admin-key"
  }
}

# Save private key locally
resource "local_file" "admin_private_key" {
  content         = tls_private_key.admin_key.private_key_pem
  filename        = "${path.module}/admin-key.pem"
  file_permission = "0400"
}

# Get latest Ubuntu 22.04 AMI
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

# Create student credentials JSON for the setup script
locals {
  student_credentials = [
    for i in range(var.student_count) : {
      student_id   = "student${i + 1}"
      password     = random_password.student_passwords[i].result
      ssh_port     = 2201 + i
      http_port    = 8001 + i
      https_port   = 8441 + i
      container_ip = "172.20.0.${10 + i}"
    }
  ]

  credentials_json = jsonencode(local.student_credentials)
}
