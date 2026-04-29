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

resource "aws_iam_role_policy" "lab_storage" {
  name = "${var.project_name}-lab-storage"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_ebs_volume" "lab_data" {
  count             = var.existing_lab_data_volume_id == "" ? 1 : 0
  availability_zone = aws_subnet.public.availability_zone
  size              = var.lab_data_volume_size
  type              = var.lab_data_volume_type

  tags = {
    Name = "${var.project_name}-lab-data"
  }
}

########################################
# EC2 INSTANCE
########################################

resource "aws_instance" "lab_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.admin_key.key_name
  vpc_security_group_ids      = [aws_security_group.lab_instance.id]
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region                      = var.aws_region
    credentials_json                = local.credentials_json
    student_count                   = var.student_count
    container_memory                = var.container_memory
    container_cpu                   = var.container_cpu
    sync_interval_minutes           = var.sync_interval_minutes
    student_web_port_start          = var.student_web_port_start
    student_app_port_start          = var.student_app_port_start
    enable_student_web_access       = tostring(var.enable_student_web_access)
    enable_student_app_port_access  = tostring(var.enable_student_app_port_access)
    enable_github_sync              = tostring(var.enable_github_sync)
    enable_container_state_restore  = tostring(var.enable_container_state_restore)
    enable_repo_bootstrap           = tostring(var.enable_repo_bootstrap)
    github_org                      = var.github_org
    github_repo_prefix              = var.github_repo_prefix
    github_repository_url           = var.github_repository_url
    github_branch                   = var.github_branch
    github_student_branch_prefix    = var.github_student_branch_prefix
    github_token_ssm_parameter      = var.github_token_ssm_parameter
    github_commit_author_name       = var.github_commit_author_name
    github_commit_author_email      = var.github_commit_author_email
    enable_admin_dashboard          = tostring(var.enable_admin_dashboard)
    admin_dashboard_port            = var.admin_dashboard_port
    enable_backups                  = tostring(var.enable_backups)
    backup_interval_minutes         = var.backup_interval_minutes
    backup_retention_count          = var.backup_retention_count
    enable_usage_tracking           = tostring(var.enable_usage_tracking)
    usage_tracking_interval_minutes = var.usage_tracking_interval_minutes
    enable_auto_cleanup             = tostring(var.enable_auto_cleanup)
    cleanup_interval_hours          = var.cleanup_interval_hours
    enable_lab_schedule             = tostring(var.enable_lab_schedule)
    lab_open_time                   = var.lab_open_time
    lab_close_time                  = var.lab_close_time
    lab_timezone                    = var.lab_timezone
    enable_email_alerts             = tostring(var.enable_email_alerts)
    alert_email_from                = var.alert_email_from
    alert_email_to                  = var.alert_email_to
    lab_data_mount_point            = "/lab-data"
    setup_script                    = file("${path.module}/scripts/setup.sh")
    sync_script                     = file("${path.module}/scripts/sync-data.sh")
    backup_script                   = file("${path.module}/scripts/backup-data.sh")
    cleanup_script                  = file("${path.module}/scripts/cleanup.sh")
    usage_script                    = file("${path.module}/scripts/collect-usage.sh")
    report_script                   = file("${path.module}/scripts/generate-report.sh")
    dashboard_script                = file("${path.module}/scripts/render-dashboard.sh")
    alert_script                    = file("${path.module}/scripts/send-alert.sh")
    reset_password_script           = file("${path.module}/scripts/reset-student-password.sh")
    schedule_script                 = file("${path.module}/scripts/toggle-lab-access.sh")
  }))
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "lab_data" {
  device_name = "/dev/sdf"
  volume_id   = local.lab_data_volume_id
  instance_id = aws_instance.lab_server.id
}

########################################
# ELASTIC IP
########################################

resource "aws_eip" "lab_server" {
  count  = var.existing_eip_allocation_id == "" ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

resource "aws_eip_association" "lab_server" {
  instance_id   = aws_instance.lab_server.id
  allocation_id = var.existing_eip_allocation_id != "" ? var.existing_eip_allocation_id : aws_eip.lab_server[0].id
}
