#!/bin/bash

set -e

echo "===== CLOUD LAB SETUP STARTED ====="

# Load environment variables
source /etc/environment

STUDENT_COUNT=${student_count:-10}
CONTAINER_MEMORY=${container_memory:-512m}
CONTAINER_CPU=${container_cpu:-0.5}

CREDENTIALS_JSON=$(cat /root/credentials.json)

# Install Docker if not exists
apt-get update -y
apt-get install -y docker.io jq

systemctl enable docker
systemctl start docker

sleep 10

# Create network
docker network inspect student-network >/dev/null 2>&1 || docker network create student-network

# Create base directory
mkdir -p /opt/cloud-lab

cd /opt/cloud-lab

# Dockerfile
cat << 'EOF' > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    vim \
    nano \
 && mkdir /var/run/sshd \
 && rm -rf /var/lib/apt/lists/*

EXPOSE 22

CMD ["/usr/sbin/sshd","-D"]
EOF

# Build image
docker build -t student-lab:latest .

echo "Creating student containers..."

for i in $(seq 1 $STUDENT_COUNT); do

  STUDENT="student$i"
  SSH_PORT=$((2200 + i))

  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

  # Validate password
  if [[ -z "$PASSWORD" || ${#PASSWORD} -lt 8 ]]; then
    echo "Skipping $STUDENT due to invalid password"
    continue
  fi

  echo "Creating $STUDENT..."

  # Create persistent volume
  mkdir -p /lab/$STUDENT

  docker run -d \
    --name $STUDENT \
    --hostname $STUDENT-lab \
    --network student-network \
    --memory=$CONTAINER_MEMORY \
    --cpus=$CONTAINER_CPU \
    --restart unless-stopped \
    -p $SSH_PORT:22 \
    -v /lab/$STUDENT:/home/student \
    student-lab:latest

  sleep 2

  # Configure user
  docker exec $STUDENT bash -c "
    useradd -m -s /bin/bash -G sudo student || true
    echo student:$PASSWORD | chpasswd
    echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  "

done

echo "===== RUNNING CONTAINERS ====="
docker ps

echo "===== CLOUD LAB SETUP COMPLETED ====="
