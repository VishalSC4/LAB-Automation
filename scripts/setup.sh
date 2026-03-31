#!/bin/bash

set -e

echo "===== CLOUD LAB SETUP STARTED ====="

# Load env variables
source /etc/environment

STUDENT_COUNT=${student_count:-10}
CONTAINER_MEMORY=${container_memory:-512m}
CONTAINER_CPU=${container_cpu:-0.5}

CREDENTIALS_JSON=$(cat /root/credentials.json)

########################################
# Ensure Docker is ready
########################################

systemctl restart docker

until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker inside script..."
  sleep 5
done

########################################
# Network setup
########################################

docker network inspect student-network >/dev/null 2>&1 || docker network create student-network

########################################
# Workspace setup
########################################

mkdir -p /opt/cloud-lab
cd /opt/cloud-lab

########################################
# Dockerfile
########################################

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

########################################
# Build image
########################################

docker build -t student-lab:latest .

########################################
# Create Containers
########################################

echo "Creating student containers..."

for i in $(seq 1 $STUDENT_COUNT); do

  STUDENT="student$i"
  SSH_PORT=$((2200 + i))

  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

  # FIX: fallback password instead of skipping
  if [[ -z "$PASSWORD" || "$PASSWORD" == "null" || ${#PASSWORD} -lt 8 ]]; then
    PASSWORD="Student@123"
    echo "⚠️ Using default password for $STUDENT"
  fi

  echo "Creating $STUDENT on port $SSH_PORT..."

  # Create persistent directory
  mkdir -p /lab/$STUDENT

  # Remove existing container (idempotent)
  docker rm -f $STUDENT >/dev/null 2>&1 || true

  # Run container
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

  # Configure user inside container
  docker exec $STUDENT bash -c "
    useradd -m -s /bin/bash -G sudo student || true
    echo student:$PASSWORD | chpasswd
    echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  "

done

########################################
# Status
########################################

echo "===== RUNNING CONTAINERS ====="
docker ps

echo "===== CLOUD LAB SETUP COMPLETED ====="
