#!/bin/bash

# =========================================
# DEBUG + LOGGING
# =========================================
set -ex
exec > >(tee /var/log/cloud-lab-setup.log) 2>&1

echo "===== CLOUD LAB SETUP STARTED ====="

# =========================================
# VARIABLES
# =========================================
STUDENT_COUNT=${student_count:-10}
CREDENTIALS_JSON=${credentials_json}
CONTAINER_MEMORY=${container_memory:-512m}
CONTAINER_CPU=${container_cpu:-0.5}

# =========================================
# UPDATE SYSTEM
# =========================================
apt-get update -y

# =========================================
# INSTALL DOCKER
# =========================================
apt-get install -y docker.io
systemctl start docker
systemctl enable docker

sleep 15

# =========================================
# CREATE NETWORK
# =========================================
docker network create student-network || true

# =========================================
# SETUP DIRECTORY
# =========================================
mkdir -p /opt/cloud-lab
cd /opt/cloud-lab

# =========================================
# DOCKERFILE
# =========================================
cat << 'EOF' > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    vim \
    nano \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir /var/run/sshd

EXPOSE 22

CMD ["/usr/sbin/sshd","-D"]
EOF

# =========================================
# BUILD IMAGE
# =========================================
docker build -t student-lab:latest .

# =========================================
# CREATE CONTAINERS
# =========================================
echo "Creating student containers..."

for i in $(seq 1 $STUDENT_COUNT); do

  STUDENT="student$i"
  SSH_PORT=$((2200 + i))
  HTTP_PORT=$((8000 + i))

  echo "Creating $STUDENT..."

  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

  docker run -d \
    --name $STUDENT \
    --hostname $STUDENT-lab \
    --network student-network \
    --memory=$CONTAINER_MEMORY \
    --cpus=$CONTAINER_CPU \
    --restart unless-stopped \
    -p $SSH_PORT:22 \
    -p $HTTP_PORT:80 \
    student-lab:latest

  sleep 3

  docker exec $STUDENT bash -c "
    useradd -m -s /bin/bash -G sudo student
    echo student:$PASSWORD | chpasswd
    echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  "

done

# =========================================
# VERIFY
# =========================================
docker ps -a

echo "===== CLOUD LAB SETUP COMPLETED ====="
