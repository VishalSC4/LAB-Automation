#!/bin/bash

# DO NOT EXIT ON ERROR (important for debugging)
set -ex

# Log everything
exec > >(tee /var/log/cloud-lab-setup.log) 2>&1

echo "=== Cloud Lab Setup Started ==="

# Variables
STUDENT_COUNT=${student_count:-10}
CREDENTIALS_JSON=${credentials_json}
CONTAINER_MEMORY=${container_memory:-512m}
CONTAINER_CPU=${container_cpu:-0.5}

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Install dependencies
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    unzip

echo "=== Installing Docker ==="

# Install Docker
apt-get install -y docker.io
systemctl start docker
systemctl enable docker

# Wait for Docker to be ready
sleep 15

echo "=== Creating Docker Network ==="

docker network create student-network || true

echo "=== Creating Build Directory ==="

mkdir -p /opt/cloud-lab
cd /opt/cloud-lab

echo "=== Creating Dockerfile ==="

cat << 'EOF' > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    wget \
    vim \
    nano \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir /var/run/sshd

EXPOSE 22

CMD ["/usr/sbin/sshd","-D"]
EOF

echo "=== Building Docker Image ==="

docker build -t student-lab:latest .

echo "=== Creating Containers ==="

for i in $(seq 1 $STUDENT_COUNT); do

  STUDENT="student$i"
  SSH_PORT=$((2200 + i))

  echo "Creating $STUDENT..."

  docker run -d \
    --name $STUDENT \
    --network student-network \
    --memory=$CONTAINER_MEMORY \
    --cpus=$CONTAINER_CPU \
    -p $SSH_PORT:22 \
    student-lab:latest

  sleep 2

  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

  docker exec $STUDENT bash -c "
    useradd -m -s /bin/bash -G sudo student
    echo student:$PASSWORD | chpasswd
    echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  "

done

echo "=== Verifying Containers ==="
docker ps -a

echo "=== Setup Completed Successfully ==="
