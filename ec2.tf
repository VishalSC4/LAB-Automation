# IAM ROLE

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 INSTANCE

resource "aws_instance" "lab_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.admin_key.key_name
  vpc_security_group_ids = [aws_security_group.lab_instance.id]
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<EOF
#!/bin/bash
set -e

# Install dependencies
apt-get update -y
apt-get install -y docker.io jq curl

# Enable Docker
systemctl enable docker
systemctl start docker

# Wait for Docker
sleep 15

# Save credentials securely (NOT logging)
cat <<CREDENTIALS > /root/credentials.json
${local.credentials_json}
CREDENTIALS

chmod 600 /root/credentials.json

# Export variables (safe)
echo "student_count=${var.student_count}" >> /etc/environment
echo "container_memory=${var.container_memory}" >> /etc/environment
echo "container_cpu=${var.container_cpu}" >> /etc/environment

# Download setup script
curl -fsSL -o /root/setup.sh https://raw.githubusercontent.com/VishalSC4/LAB-Automation/main/scripts/setup.sh
chmod +x /root/setup.sh

# Run setup script
bash /root/setup.sh

EOF
  )

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# ELASTIC IP

resource "aws_eip" "lab_server" {
  instance = aws_instance.lab_server.id
  domain   = "vpc"
}
