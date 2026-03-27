# Security Group for EC2 Instance
resource "aws_security_group" "lab_instance" {
  name        = "${var.project_name}-instance-sg"
  description = "Security group for Cloud Lab EC2 instance"
  vpc_id      = aws_vpc.main.id

  # SSH access to host (for admin)
  ingress {
    description = "SSH to host"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # SSH ports for student containers (2201-2210)
  ingress {
    description = "SSH to student containers"
    from_port   = 2201
    to_port     = 2210
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # HTTP ports for student web applications (8001-8010)
  ingress {
    description = "HTTP for student apps"
    from_port   = 8001
    to_port     = 8010
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # HTTPS ports for student web applications (8441-8450)
  ingress {
    description = "HTTPS for student apps"
    from_port   = 8441
    to_port     = 8450
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-instance-sg"
  }
}
