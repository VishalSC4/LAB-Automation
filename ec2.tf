# ================================
# EC2 INSTANCE
# ================================

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
set -ex

# ================================
# BASIC SETUP
# ================================
apt-get update -y
apt-get install -y curl jq git docker.io

systemctl start docker
systemctl enable docker

# Wait for Docker to be ready
sleep 20

# ================================
# SAVE VARIABLES
# ================================
cat <<CREDENTIALS > /tmp/credentials.json
${local.credentials_json}
CREDENTIALS

export student_count=${var.student_count}
export credentials_json=$(cat /tmp/credentials.json)
export container_memory=${var.container_memory}
export container_cpu=${var.container_cpu}

# ================================
# DOWNLOAD SCRIPT
# ================================
curl -f -o /tmp/setup.sh https://raw.githubusercontent.com/VishalSC4/LAB-Automation/main/scripts/setup.sh

chmod +x /tmp/setup.sh

# ================================
# RUN SCRIPT
# ================================
bash /tmp/setup.sh

EOF
  )

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
