╔══════════════════════════════════════════════════════════════════════════════╗
║                    CLOUD LAB - STUDENT ACCESS CREDENTIALS                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Server IP: ${public_ip}
║                                                                              
║  HOW TO CONNECT:                                                            ║
║  1. Open your terminal (Command Prompt, PowerShell, or Terminal)            ║
║  2. Run the SSH command for your student number                             ║
║  3. When prompted, enter your password                                      ║
%{ if dashboard_enabled ~}
║  4. Admin dashboard: ${dashboard_url}
%{ endif ~}
╠══════════════════════════════════════════════════════════════════════════════╣
%{ for student in students ~}

┌──────────────────────────────────────────────────────────────────────────────┐
│ STUDENT ${student.number}
├──────────────────────────────────────────────────────────────────────────────┤
│ Username    : ${student.username}
│ Password    : ${student.password}
│ SSH Port    : ${student.ssh_port}
%{ if web_enabled ~}
│ HTTP Port   : ${student.http_port}
│ App Port    : ${student.app_port}
%{ endif ~}
│ 
│ SSH Command : ssh -p ${student.ssh_port} ${student.username}@${public_ip}
%{ if web_enabled ~}
│ Static App  : http://${public_ip}:${student.http_port}
│ Dynamic App : http://${public_ip}:${student.app_port}
%{ endif ~}
└──────────────────────────────────────────────────────────────────────────────┘
%{ endfor ~}

╔══════════════════════════════════════════════════════════════════════════════╗
║  IMPORTANT NOTES:                                                           ║
║  • Each student has their own isolated environment                          ║
║  • Your work is backed up and restored when the lab is rebuilt              ║
║  • Do not share your credentials with others                                ║
║  • Contact your instructor if you face any issues                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
