########################################
# IAM ROLE
########################################

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

########################################
# EC2 INSTANCE
########################################

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
set -xe

# Log everything
exec > /var/log/user-data.log 2>&1

echo "===== USER DATA START ====="

# Wait for network
sleep 30

# Install dependencies
apt-get update -y
apt-get install -y docker.io jq curl

# Enable Docker
systemctl enable docker
systemctl start docker

# Wait until Docker is ready
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker..."
  sleep 5
done

echo "Docker is ready"

# Save credentials securely
cat <<CREDENTIALS > /root/credentials.json
${local.credentials_json}
CREDENTIALS

chmod 600 /root/credentials.json

# Export environment variables
cat <<ENV >> /etc/environment
student_count=${var.student_count}
container_memory=${var.container_memory}
container_cpu=${var.container_cpu}
ENV

# Download setup script with retry
for i in {1..5}; do
  curl -fsSL https://raw.githubusercontent.com/VishalSC4/LAB-Automation/main/scripts/setup.sh -o /root/setup.sh && break
  echo "Retrying script download..."
  sleep 5
done

chmod +x /root/setup.sh

# Run setup script
bash /root/setup.sh

echo "===== USER DATA END ====="

EOF
  )

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

########################################
# ELASTIC IP
########################################

resource "aws_eip" "lab_server" {
  instance = aws_instance.lab_server.id
  domain   = "vpc"
}
