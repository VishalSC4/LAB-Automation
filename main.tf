# Generate SSH key pair for admin access
resource "tls_private_key" "admin_key" {
  algorithm = "ED25519"
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
  content         = tls_private_key.admin_key.private_key_openssh
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

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eip" "existing_lab_server" {
  count = var.existing_eip_allocation_id != "" ? 1 : 0
  id    = var.existing_eip_allocation_id
}

data "aws_ebs_volume" "existing_lab_data" {
  count = var.existing_lab_data_volume_id != "" ? 1 : 0

  filter {
    name   = "volume-id"
    values = [var.existing_lab_data_volume_id]
  }
}

# Create student credentials JSON for the setup script
locals {
  lab_server_public_ip = var.existing_eip_allocation_id != "" ? data.aws_eip.existing_lab_server[0].public_ip : aws_eip.lab_server[0].public_ip
  lab_data_volume_id   = var.existing_lab_data_volume_id != "" ? data.aws_ebs_volume.existing_lab_data[0].id : aws_ebs_volume.lab_data[0].id

  student_credentials = [
    for i in range(var.student_count) : {
      student_id = "student${i + 1}"
      username   = "student"
      password = format(
        "Lab%s%s@%02d",
        upper(substr(md5("${data.aws_caller_identity.current.account_id}-${var.project_name}-${i + 1}"), 0, 2)),
        substr(md5("${data.aws_caller_identity.current.account_id}-${var.project_name}-${i + 1}"), 2, 6),
        i + 1
      )
      ssh_port  = 2201 + i
      http_port = var.student_web_port_start + i
      app_port  = var.student_app_port_start + i
    }
  ]

  credentials_json = jsonencode(local.student_credentials)
}
