variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloud-lab"
}

variable "student_count" {
  description = "Number of student containers to create"
  type        = number
  default     = 5

  validation {
    condition     = var.student_count >= 1 && var.student_count <= 10
    error_message = "student_count must be between 1 and 10 for this lab blueprint."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the shared lab host"
  type        = string
  default     = "t3.small"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_web_cidrs" {
  description = "List of CIDR blocks allowed to access student web application ports"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_app_cidrs" {
  description = "List of CIDR blocks allowed to access student dynamic application ports"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_dashboard_cidrs" {
  description = "List of CIDR blocks allowed to access the admin dashboard and reports"
  type        = list(string)
  default     = []
}

variable "container_memory" {
  description = "Memory limit per container"
  type        = string
  default     = "256m"
}

variable "container_cpu" {
  description = "CPU limit per container"
  type        = string
  default     = "0.20"
}

variable "enable_student_web_access" {
  description = "Whether to open student web application ports"
  type        = bool
  default     = true
}

variable "student_web_port_start" {
  description = "Starting HTTP port for student applications"
  type        = number
  default     = 8001
}

variable "student_web_port_end" {
  description = "Ending HTTP port for student applications"
  type        = number
  default     = 8005

  validation {
    condition     = var.student_web_port_end >= var.student_web_port_start
    error_message = "student_web_port_end must be greater than or equal to student_web_port_start."
  }
}

variable "enable_student_app_port_access" {
  description = "Whether to expose a dedicated dynamic app port for each student"
  type        = bool
  default     = true
}

variable "student_app_port_start" {
  description = "Starting host port for student dynamic applications"
  type        = number
  default     = 9001
}

variable "student_app_port_end" {
  description = "Ending host port for student dynamic applications"
  type        = number
  default     = 9005

  validation {
    condition     = var.student_app_port_end >= var.student_app_port_start
    error_message = "student_app_port_end must be greater than or equal to student_app_port_start."
  }
}

variable "existing_eip_allocation_id" {
  description = "Existing Elastic IP allocation ID to reuse across destroys/applies. Leave empty to let Terraform allocate a new EIP for this stack."
  type        = string
  default     = ""
}

variable "existing_lab_data_volume_id" {
  description = "Existing EBS volume ID to reattach as the persistent /lab-data disk after a rebuild. Leave empty to create a new volume."
  type        = string
  default     = ""
}

variable "sync_interval_minutes" {
  description = "How often student workspaces are auto-synced to GitHub"
  type        = number
  default     = 5

  validation {
    condition     = var.sync_interval_minutes >= 1 && var.sync_interval_minutes <= 60
    error_message = "sync_interval_minutes must be between 1 and 60."
  }
}

variable "lab_data_volume_size" {
  description = "Size in GiB of the persistent EBS volume used for /lab-data and Docker state"
  type        = number
  default     = 8

  validation {
    condition     = var.lab_data_volume_size >= 8
    error_message = "lab_data_volume_size must be at least 8 GiB."
  }
}

variable "lab_data_volume_type" {
  description = "EBS volume type for the persistent lab data disk"
  type        = string
  default     = "gp3"
}

variable "enable_github_sync" {
  description = "Enable automated pull/push of each student's workspace to GitHub"
  type        = bool
  default     = false
}

variable "enable_container_state_restore" {
  description = "Restore container filesystem changes outside mounted student work directories. Leave disabled for stable rebuilds."
  type        = bool
  default     = false
}

variable "enable_repo_bootstrap" {
  description = "Create missing GitHub repositories or branches automatically when GitHub sync is enabled"
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub user or organization that owns student repositories"
  type        = string
  default     = ""
}

variable "github_repo_prefix" {
  description = "Prefix used for per-student repositories (for example: student-lab -> student-lab-1)"
  type        = string
  default     = "student-lab"
}

variable "github_repository_url" {
  description = "Optional single GitHub repository URL for all students (uses one branch per student when set)"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "Git branch used for per-student repositories"
  type        = string
  default     = "main"
}

variable "github_student_branch_prefix" {
  description = "Branch prefix for single-repository mode (for example: student- -> student-1, student-2)"
  type        = string
  default     = "student-"
}

variable "github_token_ssm_parameter" {
  description = "SSM parameter name (SecureString recommended) containing a GitHub token for pull/push automation"
  type        = string
  default     = ""
}

variable "github_commit_author_name" {
  description = "Author name used for automated Git commits"
  type        = string
  default     = "Cloud Lab Bot"
}

variable "github_commit_author_email" {
  description = "Author email used for automated Git commits"
  type        = string
  default     = "cloud-lab-bot@example.com"
}

variable "enable_admin_dashboard" {
  description = "Expose a simple admin dashboard with student links and host status"
  type        = bool
  default     = true
}

variable "admin_dashboard_port" {
  description = "Host port for the admin dashboard"
  type        = number
  default     = 8080

  validation {
    condition     = var.admin_dashboard_port >= 1024 && var.admin_dashboard_port <= 65535
    error_message = "admin_dashboard_port must be between 1024 and 65535."
  }
}

variable "enable_backups" {
  description = "Enable periodic compressed backups of the lab data disk"
  type        = bool
  default     = true
}

variable "backup_interval_minutes" {
  description = "How often lab data backups run"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_interval_minutes >= 5 && var.backup_interval_minutes <= 1440
    error_message = "backup_interval_minutes must be between 5 and 1440."
  }
}

variable "backup_retention_count" {
  description = "Number of compressed lab backups to keep"
  type        = number
  default     = 24

  validation {
    condition     = var.backup_retention_count >= 1 && var.backup_retention_count <= 200
    error_message = "backup_retention_count must be between 1 and 200."
  }
}

variable "enable_usage_tracking" {
  description = "Collect per-student CPU and memory usage for dashboard and reports"
  type        = bool
  default     = true
}

variable "usage_tracking_interval_minutes" {
  description = "How often usage metrics are refreshed"
  type        = number
  default     = 5

  validation {
    condition     = var.usage_tracking_interval_minutes >= 1 && var.usage_tracking_interval_minutes <= 60
    error_message = "usage_tracking_interval_minutes must be between 1 and 60."
  }
}

variable "enable_auto_cleanup" {
  description = "Enable periodic cleanup of Docker cache, logs, and old temp files"
  type        = bool
  default     = true
}

variable "cleanup_interval_hours" {
  description = "How often host cleanup runs"
  type        = number
  default     = 12

  validation {
    condition     = var.cleanup_interval_hours >= 1 && var.cleanup_interval_hours <= 168
    error_message = "cleanup_interval_hours must be between 1 and 168."
  }
}

variable "enable_lab_schedule" {
  description = "Enable a daily open/close schedule for the student containers"
  type        = bool
  default     = false
}

variable "lab_open_time" {
  description = "Daily lab open time in 24-hour HH:MM format"
  type        = string
  default     = "08:00"
}

variable "lab_close_time" {
  description = "Daily lab close time in 24-hour HH:MM format"
  type        = string
  default     = "20:00"
}

variable "lab_timezone" {
  description = "Timezone used for scheduled lab open and close actions"
  type        = string
  default     = "Asia/Kolkata"
}

variable "enable_email_alerts" {
  description = "Send setup and maintenance alerts by email using Amazon SES"
  type        = bool
  default     = false
}

variable "alert_email_from" {
  description = "Verified SES sender email address used for alerts"
  type        = string
  default     = ""
}

variable "alert_email_to" {
  description = "Email address that receives lab alerts"
  type        = string
  default     = ""
}
