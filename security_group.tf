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

  # SSH ports for student containers
  ingress {
    description = "SSH to student containers"
    from_port   = 2201
    to_port     = 2200 + var.student_count
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  dynamic "ingress" {
    for_each = var.enable_student_web_access ? [1] : []
    content {
      description = "HTTP for student apps"
      from_port   = var.student_web_port_start
      to_port     = var.student_web_port_start + var.student_count - 1
      protocol    = "tcp"
      cidr_blocks = var.allowed_web_cidrs
    }
  }

  dynamic "ingress" {
    for_each = var.enable_student_app_port_access ? [1] : []
    content {
      description = "Dynamic app ports for student apps"
      from_port   = var.student_app_port_start
      to_port     = var.student_app_port_start + var.student_count - 1
      protocol    = "tcp"
      cidr_blocks = var.allowed_app_cidrs
    }
  }

  dynamic "ingress" {
    for_each = var.enable_admin_dashboard ? [1] : []
    content {
      description = "Admin dashboard and reports"
      from_port   = var.admin_dashboard_port
      to_port     = var.admin_dashboard_port
      protocol    = "tcp"
      cidr_blocks = length(var.allowed_dashboard_cidrs) > 0 ? var.allowed_dashboard_cidrs : var.allowed_ssh_cidrs
    }
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
