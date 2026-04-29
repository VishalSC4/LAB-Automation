output "lab_server_public_ip" {
  description = "Public IP address of the lab server"
  value       = local.lab_server_public_ip
}

output "lab_server_eip_allocation_id" {
  description = "Elastic IP allocation ID attached to the lab server"
  value       = var.existing_eip_allocation_id != "" ? var.existing_eip_allocation_id : aws_eip.lab_server[0].id
}

output "lab_server_instance_id" {
  description = "Instance ID of the lab server"
  value       = aws_instance.lab_server.id
}

output "lab_data_volume_id" {
  description = "EBS volume ID used for persistent /lab-data storage"
  value       = local.lab_data_volume_id
}

output "admin_ssh_command" {
  description = "SSH command to connect to the lab server as admin"
  value       = "ssh -i admin-key.pem ubuntu@${local.lab_server_public_ip}"
}

output "admin_dashboard_url" {
  description = "URL for the admin dashboard"
  value       = var.enable_admin_dashboard ? "http://${local.lab_server_public_ip}:${var.admin_dashboard_port}" : "Dashboard disabled"
}

output "student_access_info" {
  description = "Student access information"
  value = [
    for i in range(var.student_count) : {
      student_id  = "student${i + 1}"
      username    = "student"
      password    = local.student_credentials[i].password
      ssh_port    = 2201 + i
      http_port   = var.student_web_port_start + i
      app_port    = var.student_app_port_start + i
      ssh_command = "ssh -p ${2201 + i} student@${local.lab_server_public_ip}"
      static_url  = "http://${local.lab_server_public_ip}:${var.student_web_port_start + i}"
      dynamic_url = "http://${local.lab_server_public_ip}:${var.student_app_port_start + i}"
    }
  ]
  sensitive = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.lab_instance.id
}

# Generate a formatted credentials file
resource "local_file" "student_credentials" {
  content = templatefile("${path.module}/templates/credentials.tpl", {
    public_ip         = local.lab_server_public_ip
    web_enabled       = var.enable_student_web_access
    dashboard_enabled = var.enable_admin_dashboard
    dashboard_url     = var.enable_admin_dashboard ? "http://${local.lab_server_public_ip}:${var.admin_dashboard_port}" : ""
    students = [
      for i in range(var.student_count) : {
        number    = i + 1
        username  = "student"
        password  = local.student_credentials[i].password
        ssh_port  = 2201 + i
        http_port = var.student_web_port_start + i
        app_port  = var.student_app_port_start + i
      }
    ]
  })
  filename = "${path.module}/STUDENT_CREDENTIALS.txt"
}
