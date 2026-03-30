 #!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/cloud-lab-setup.log) 2>&1
echo "=== Cloud Lab Setup Started at $(date) ==="

# Variables from Terraform
STUDENT_COUNT=${student_count}
CREDENTIALS_JSON='${credentials_json}'
CONTAINER_MEMORY="${container_memory}"
CONTAINER_CPU="${container_cpu}"

# Update system
echo "=== Updating system packages ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install required packages
echo "=== Installing required packages ==="
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    htop \
    net-tools \
    fail2ban \
    ufw

# Install Docker
echo "=== Installing Docker ==="
curl -fsSL [download.docker.com](https://download.docker.com/linux/ubuntu/gpg) | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] [download.docker.com](https://download.docker.com/linux/ubuntu) $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Create Docker network for student containers
echo "=== Creating Docker network ==="
docker network create --driver bridge --subnet=172.20.0.0/16 student-network || true

# Create the student container Dockerfile
echo "=== Creating Dockerfile for student containers ==="
mkdir -p /opt/cloud-lab
cat > /opt/cloud-lab/Dockerfile << 'DOCKERFILE'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

# Update and install essential packages
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    vim \
    nano \
    git \
    curl \
    wget \
    htop \
    net-tools \
    iputils-ping \
    dnsutils \
    tree \
    unzip \
    zip \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    default-jdk \
    maven \
    build-essential \
    gcc \
    g++ \
    make \
    nginx \
    mysql-client \
    postgresql-client \
    redis-tools \
    jq \
    tmux \
    screen \
    man-db \
    locales \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "[awscli.amazonaws.com](https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip)" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Install Terraform
RUN wget -O- [apt.releases.hashicorp.com](https://apt.releases.hashicorp.com/gpg) | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] [apt.releases.hashicorp.com](https://apt.releases.hashicorp.com) $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y terraform \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "[dl.k8s.io](https://dl.k8s.io/release/$(curl) -L -s [dl.k8s.io](https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl)" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Install Docker CLI (for learning, not actual Docker operations)
RUN curl -fsSL [download.docker.com](https://download.docker.com/linux/ubuntu/gpg) | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] [download.docker.com](https://download.docker.com/linux/ubuntu) $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Ansible
RUN pip3 install ansible boto3 botocore

# Configure locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Configure SSH
RUN mkdir /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# Create workspace directory
RUN mkdir -p /home/student/workspace /home/student/projects

# Create welcome message script
RUN echo '#!/bin/bash\n\
echo ""\n\
echo "╔════════════════════════════════════════════════════════════════╗"\n\
echo "║           Welcome to Cloud Learning Lab Environment           ║"\n\
echo "╠════════════════════════════════════════════════════════════════╣"\n\
echo "║  Available Tools:                                             ║"\n\
echo "║  • AWS CLI v2      • Terraform       • Ansible                ║"\n\
echo "║  • kubectl         • Docker CLI      • Python 3               ║"\n\
echo "║  • Node.js         • Java/Maven      • Git                    ║"\n\
echo "╠════════════════════════════════════════════════════════════════╣"\n\
echo "║  Directories:                                                 ║"\n\
echo "║  • ~/workspace  - Your working directory                      ║"\n\
echo "║  • ~/projects   - For your projects                           ║"\n\
echo "╠════════════════════════════════════════════════════════════════╣"\n\
echo "║  Tips:                                                        ║"\n\
echo "║  • Use '\''aws configure'\'' to set up AWS credentials              ║"\n\
echo "║  • Your changes persist within the session                    ║"\n\
echo "║  • Type '\''help'\'' for available commands                          ║"\n\
echo "╚════════════════════════════════════════════════════════════════╝"\n\
echo ""\n' > /etc/profile.d/welcome.sh \
    && chmod +x /etc/profile.d/welcome.sh

# Expose SSH port
EXPOSE 22

# Start SSH service
CMD ["/usr/sbin/sshd", "-D"]
DOCKERFILE

# Build the student container image
echo "=== Building student container image ==="
cd /opt/cloud-lab
docker build -t student-lab:latest .

# Create credentials file
echo "=== Creating credentials file ==="
echo "$CREDENTIALS_JSON" > /opt/cloud-lab/credentials.json

# Create and start student containers
echo "=== Creating student containers ==="
for i in $(seq 1 $STUDENT_COUNT); do
    STUDENT_ID="student$i"
    SSH_PORT=$((2200 + i))
    HTTP_PORT=$((8000 + i))
    HTTPS_PORT=$((8440 + i))
    CONTAINER_IP="172.20.0.$((9 + i))"
    
    # Get password from credentials JSON
    PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")
    
    echo "Creating container for $STUDENT_ID on port $SSH_PORT..."
    
    # Create and start container
    docker run -d \
        --name "$STUDENT_ID" \
        --hostname "$STUDENT_ID-lab" \
        --network student-network \
        --ip "$CONTAINER_IP" \
        --memory="$CONTAINER_MEMORY" \
        --cpus="$CONTAINER_CPU" \
        --restart unless-stopped \
        -p "$SSH_PORT:22" \
        -p "$HTTP_PORT:80" \
        -p "$HTTPS_PORT:443" \
        -v "/opt/cloud-lab/shared:/shared:ro" \
        student-lab:latest
    
    # Wait for container to be ready
    sleep 2
    
    # Create student user with password
    docker exec "$STUDENT_ID" bash -c "
        useradd -m -s /bin/bash -G sudo student
        echo 'student:$PASSWORD' | chpasswd
        chown -R student:student /home/student
        echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
    "
    
    echo "Container $STUDENT_ID created successfully"
done

# Create shared directory for common files
echo "=== Creating shared directory ==="
mkdir -p /opt/cloud-lab/shared
cat > /opt/cloud-lab/shared/README.txt << 'EOF'
=== Cloud Lab Shared Directory ===

This directory contains shared resources for all students.
Files here are READ-ONLY.

For your work, use:
- ~/workspace - Your personal working directory
- ~/projects  - For your projects
EOF

# Generate student credentials report
echo "=== Generating credentials report ==="
PUBLIC_IP=$(curl -s [169.254.169.254](http://169.254.169.254/latest/meta-data/public-ipv4) || echo "PENDING")

cat > /opt/cloud-lab/student_credentials.txt << EOF
╔══════════════════════════════════════════════════════════════════════════════╗
║                    CLOUD LAB - STUDENT ACCESS CREDENTIALS                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Server IP: $PUBLIC_IP                                                       
║  Generated: $(date)                                                          
╠══════════════════════════════════════════════════════════════════════════════╣
║  CONNECTION INSTRUCTIONS:                                                   ║
║  ssh -p <PORT> student@$PUBLIC_IP                               
║  Then enter the password when prompted.                                     ║
╠══════════════════════════════════════════════════════════════════════════════╣

EOF

for i in $(seq 1 $STUDENT_COUNT); do
    STUDENT_ID="student$i"
    SSH_PORT=$((2200 + i))
    HTTP_PORT=$((8000 + i))
    PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")
    
    cat >> /opt/cloud-lab/student_credentials.txt << EOF
┌──────────────────────────────────────────────────────────────────────────────┐
│ Student $i                                                                    
├──────────────────────────────────────────────────────────────────────────────┤
│ Username    : student                                                        │
│ Password    : $PASSWORD
│ SSH Port    : $SSH_PORT                                                       
│ HTTP Port   : $HTTP_PORT                                                      
│ SSH Command : ssh -p $SSH_PORT student@$PUBLIC_IP               
└──────────────────────────────────────────────────────────────────────────────┘

EOF
done

chmod 600 /opt/cloud-lab/student_credentials.txt

# Create management scripts
echo "=== Creating management scripts ==="

# Script to view credentials
cat > /usr/local/bin/show-credentials << 'EOF'
#!/bin/bash
cat /opt/cloud-lab/student_credentials.txt
EOF
chmod +x /usr/local/bin/show-credentials

# Script to restart all containers
cat > /usr/local/bin/restart-all-containers << 'EOF'
#!/bin/bash
echo "Restarting all student containers..."
for i in $(seq 1 10); do
    docker restart "student$i" 2>/dev/null || true
done
echo "All containers restarted."
EOF
chmod +x /usr/local/bin/restart-all-containers

# Script to check container status
cat > /usr/local/bin/check-containers << 'EOF'
#!/bin/bash
echo "=== Student Container Status ==="
echo ""
printf "%-15s %-15s %-15s %-10s\n" "CONTAINER" "STATUS" "IP" "SSH PORT"
printf "%-15s %-15s %-15s %-10s\n" "---------" "------" "--" "--------"
for i in $(seq 1 10); do
    CONTAINER="student$i"
    STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not found")
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null || echo "N/A")
    PORT=$((2200 + i))
    printf "%-15s %-15s %-15s %-10s\n" "$CONTAINER" "$STATUS" "$IP" "$PORT"
done
EOF
chmod +x /usr/local/bin/check-containers

# Script to reset a specific student container
cat > /usr/local/bin/reset-student << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: reset-student <student_number>"
    echo "Example: reset-student 1"
    exit 1
fi

STUDENT_NUM=$1
CONTAINER="student$STUDENT_NUM"
SSH_PORT=$((2200 + STUDENT_NUM))
HTTP_PORT=$((8000 + STUDENT_NUM))
HTTPS_PORT=$((8440 + STUDENT_NUM))
CONTAINER_IP="172.20.0.$((9 + STUDENT_NUM))"

echo "Resetting $CONTAINER..."

# Get password from credentials
PASSWORD=$(jq -r ".[$((STUDENT_NUM-1))].password" /opt/cloud-lab/credentials.json)

# Stop and remove existing container
docker stop "$CONTAINER" 2>/dev/null || true
docker rm "$CONTAINER" 2>/dev/null || true

# Create new container
docker run -d \
    --name "$CONTAINER" \
    --hostname "$CONTAINER-lab" \
    --network student-network \
    --ip "$CONTAINER_IP" \
    --memory="1024m" \
    --cpus="1" \
    --restart unless-stopped \
    -p "$SSH_PORT:22" \
    -p "$HTTP_PORT:80" \
    -p "$HTTPS_PORT:443" \
    -v "/opt/cloud-lab/shared:/shared:ro" \
    student-lab:latest

sleep 2

# Create student user
docker exec "$CONTAINER" bash -c "
    useradd -m -s /bin/bash -G sudo student
    echo 'student:$PASSWORD' | chpasswd
    chown -R student:student /home/student
    echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
"

echo "$CONTAINER has been reset successfully."
EOF
chmod +x /usr/local/bin/reset-student

# Configure firewall
echo "=== Configuring firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 2201:2210/tcp
ufw allow 8001:8010/tcp
ufw allow 8441:8450/tcp
ufw --force enable

# Configure fail2ban
echo "=== Configuring fail2ban ==="
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh,2201:2210
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF

systemctl restart fail2ban
systemctl enable fail2ban

# Setup automatic container restart on boot
echo "=== Configuring auto-start ==="
cat > /etc/systemd/system/student-containers.service << 'EOF'
[Unit]
Description=Student Lab Containers
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/restart-all-containers

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable student-containers.service

# Create MOTD for admin
cat > /etc/update-motd.d/99-cloud-lab << 'EOF'
#!/bin/bash
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              CLOUD LAB - ADMIN SERVER                         ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Useful Commands:                                             ║"
echo "║  • show-credentials     - View student login details          ║"
echo "║  • check-containers     - View container status               ║"
echo "║  • reset-student <num>  - Reset a student's container         ║"
echo "║  • restart-all-containers - Restart all containers            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
EOF
chmod +x /etc/update-motd.d/99-cloud-lab

echo "=== Cloud Lab Setup Completed at $(date) ==="
echo "=== Check /opt/cloud-lab/student_credentials.txt for student access details ==="
