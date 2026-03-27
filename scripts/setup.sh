#!/bin/bash
set -e

# Log output
exec > >(tee /var/log/cloud-lab-setup.log) 2>&1
echo "=== Cloud Lab Setup Started at $(date) ==="

# Variables passed from Terraform user_data
STUDENT_COUNT=${student_count:-10}
CREDENTIALS_JSON=${credentials_json}
CONTAINER_MEMORY=${container_memory:-1024m}
CONTAINER_CPU=${container_cpu:-1}

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install base packages
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
    ufw \
    unzip

echo "=== Installing Docker ==="

mkdir -p /usr/share/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
 | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu

echo "=== Creating docker network ==="

docker network create \
 --driver bridge \
 --subnet 172.20.0.0/16 \
 student-network || true

echo "=== Creating container build directory ==="

mkdir -p /opt/cloud-lab
cd /opt/cloud-lab

cat << 'EOF' > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

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
    nodejs \
    npm \
    default-jdk \
    maven \
    build-essential \
    nginx \
    jq \
    tmux \
    screen \
    locales \
    tzdata \
 && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
 -o awscliv2.zip \
 && unzip awscliv2.zip \
 && ./aws/install \
 && rm -rf awscliv2.zip aws

RUN wget -O- https://apt.releases.hashicorp.com/gpg \
 | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

RUN echo \
"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \
$(lsb_release -cs) main" \
| tee /etc/apt/sources.list.d/hashicorp.list

RUN apt-get update && apt-get install -y terraform

RUN curl -LO \
"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

RUN install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

RUN mkdir /var/run/sshd

EXPOSE 22

CMD ["/usr/sbin/sshd","-D"]
EOF

echo "=== Building container image ==="

docker build -t student-lab:latest .

echo "$CREDENTIALS_JSON" > /opt/cloud-lab/credentials.json

echo "=== Creating student containers ==="

for i in $(seq 1 $STUDENT_COUNT); do

STUDENT="student$i"
SSH_PORT=$((2200 + i))
HTTP_PORT=$((8000 + i))
IP="172.20.0.$((9 + i))"

PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

docker run -d \
--name $STUDENT \
--hostname $STUDENT-lab \
--network student-network \
--ip $IP \
--memory=$CONTAINER_MEMORY \
--cpus=$CONTAINER_CPU \
--restart unless-stopped \
-p $SSH_PORT:22 \
-p $HTTP_PORT:80 \
student-lab:latest

sleep 2

docker exec $STUDENT bash -c "
useradd -m -s /bin/bash -G sudo student
echo student:$PASSWORD | chpasswd
echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
"

done

echo "=== Creating shared directory ==="

mkdir -p /opt/cloud-lab/shared

echo "Cloud Lab Shared Directory" > /opt/cloud-lab/shared/README.txt

echo "=== Generating credentials ==="

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

cat <<EOF > /opt/cloud-lab/student_credentials.txt

CLOUD LAB ACCESS

Server IP: $PUBLIC_IP

EOF

for i in $(seq 1 $STUDENT_COUNT); do

PORT=$((2200 + i))
PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

cat <<EOF >> /opt/cloud-lab/student_credentials.txt

Student $i

Username : student
Password : $PASSWORD
SSH Port : $PORT

SSH Command:

ssh -p $PORT student@$PUBLIC_IP

---------------------------------------

EOF

done

chmod 600 /opt/cloud-lab/student_credentials.txt

echo "=== Configuring firewall ==="

ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp
ufw allow 2201:2210/tcp
ufw allow 8001:8010/tcp

ufw --force enable

echo "=== Setup completed ==="
