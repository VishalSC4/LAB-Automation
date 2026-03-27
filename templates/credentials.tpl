╔══════════════════════════════════════════════════════════════════════════════╗
║                    CLOUD LAB - STUDENT ACCESS CREDENTIALS                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Server IP: ${public_ip}
║                                                                              
║  HOW TO CONNECT:                                                            ║
║  1. Open your terminal (Command Prompt, PowerShell, or Terminal)            ║
║  2. Run the SSH command for your student number                             ║
║  3. When prompted, enter your password                                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
%{ for student in students ~}

┌──────────────────────────────────────────────────────────────────────────────┐
│ STUDENT ${student.number}
├──────────────────────────────────────────────────────────────────────────────┤
│ Username    : ${student.username}
│ Password    : ${student.password}
│ SSH Port    : ${student.ssh_port}
│ HTTP Port   : ${student.http_port}
│ 
│ SSH Command : ssh -p ${student.ssh_port} ${student.username}@${public_ip}
│ Web Access  : http://${public_ip}:${student.http_port}
└──────────────────────────────────────────────────────────────────────────────┘
%{ endfor ~}

╔══════════════════════════════════════════════════════════════════════════════╗
║  IMPORTANT NOTES:                                                           ║
║  • Each student has their own isolated environment                          ║
║  • Your work is saved within your container session                         ║
║  • Do not share your credentials with others                                ║
║  • Contact your instructor if you face any issues                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
