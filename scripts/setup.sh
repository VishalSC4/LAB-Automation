#!/bin/bash

set -e

echo "===== CLOUD LAB SETUP STARTED ====="

source /root/lab.env

STUDENT_COUNT=${student_count:-10}
CONTAINER_MEMORY=${container_memory:-512m}
CONTAINER_CPU=${container_cpu:-0.5}

CREDENTIALS_JSON=$(cat /root/credentials.json)

########################################
# Wait for Docker
########################################

until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker..."
  sleep 5
done

########################################
# Network
########################################

docker network inspect student-network >/dev/null 2>&1 || docker network create student-network

########################################
# Workspace
########################################

mkdir -p /opt/cloud-lab
cd /opt/cloud-lab

########################################
# Dockerfile (with nginx installed)
########################################

cat << 'EOF' > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    nginx \
    curl \
    vim \
    nano \
 && mkdir /var/run/sshd \
 && rm -rf /var/lib/apt/lists/*

EXPOSE 22 80

CMD service nginx start && /usr/sbin/sshd -D
EOF

########################################
# Build image
########################################

docker image inspect student-lab:latest >/dev/null 2>&1 || docker build -t student-lab:latest .

########################################
# Create containers
########################################

echo "Creating student containers..."

for i in $(seq 1 $STUDENT_COUNT); do

  STUDENT="student$i"
  SSH_PORT=$((2200 + i))
  HTTP_PORT=$((8000 + i))

  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

  if [[ -z "$PASSWORD" || "$PASSWORD" == "null" || ${#PASSWORD} -lt 8 ]]; then
    PASSWORD="Student@123"
    echo "Using default password for $STUDENT"
  fi

  echo "Creating $STUDENT (SSH:$SSH_PORT HTTP:$HTTP_PORT)..."

  mkdir -p /lab/$STUDENT

  docker rm -f $STUDENT >/dev/null 2>&1 || true

  docker run -d \
    --name $STUDENT \
    --hostname $STUDENT-lab \
    --network student-network \
    --memory=$CONTAINER_MEMORY \
    --cpus=$CONTAINER_CPU \
    --restart unless-stopped \
    -p $SSH_PORT:22 \
    -p $HTTP_PORT:80 \
    -v /lab/$STUDENT:/home/student \
    student-lab:latest

  sleep 3

  docker exec $STUDENT bash -c "
    useradd -m -s /bin/bash -G sudo student || true
    echo student:$PASSWORD | chpasswd
    echo 'student ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  "

done

########################################
# Done
########################################

echo "===== RUNNING CONTAINERS ====="
docker ps

echo "===== CLOUD LAB SETUP COMPLETED ====="
