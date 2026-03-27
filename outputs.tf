output "lab_server_public_ip" {
  description = "Public IP address of the lab server"
  value       = aws_eip.lab_server.public_ip
}

output "lab_server_instance_id" {
  description = "Instance ID of the lab server"
  value       = aws_instance.lab_server.id
}

output "admin_ssh_command" {
  description = "SSH command to connect to the lab server as admin"
  value       = "ssh -i admin-key.pem ubuntu@${aws_eip.lab_server.public_ip}"
}

output "student_access_info" {
  description = "Student access information"
  value = [
    for i in range(var.student_count) : {
      student_id   = "student${i + 1}"
      username     = "student"
      password     = random_password.student_passwords[i].result
      ssh_port     = 2201 + i
      http_port    = 8001 + i
      ssh_command  = "ssh -p ${2201 + i} student@${aws_eip.lab_server.public_ip}"
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
    public_ip   = aws_eip.lab_server.public_ip
    students    = [
      for i in range(var.student_count) : {
        number      = i + 1
        username    = "student"
        password    = random_password.student_passwords[i].result
        ssh_port    = 2201 + i
        http_port   = 8001 + i
      }
    ]
  })
  filename = "${path.module}/STUDENT_CREDENTIALS.txt"
}
