#!/bin/bash

set -e

echo "===== CLOUD LAB SETUP STARTED ====="

########################################
# Load variables safely
########################################

source /root/lab.env

STUDENT_COUNT=${student_count:-10}
CONTAINER_MEMORY=${container_memory:-512m}
CONTAINER_CPU=${container_cpu:-0.5}

CREDENTIALS_JSON=$(cat /root/credentials.json)

########################################
# Ensure Docker ready
########################################

until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker..."
  sleep 5
done

########################################
# Network setup
########################################

docker network inspect student-network >/dev/null 2>&1 || docker network create student-network

########################################
# Workspace
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
# Build image (only if not exists)
########################################

docker image inspect student-lab:latest >/dev/null 2>&1 || docker build -t student-lab:latest .

########################################
# Create containers
########################################

echo "Creating student containers..."

for i in $(seq 1 $STUDENT_COUNT); do

  STUDENT="student$i"
  SSH_PORT=$((2200 + i))

  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")

  # FIX: never skip container
  if [[ -z "$PASSWORD" || "$PASSWORD" == "null" || ${#PASSWORD} -lt 8 ]]; then
    PASSWORD="Student@123"
    echo "Using default password for $STUDENT"
  fi

  echo "Creating $STUDENT..."

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
    -v /lab/$STUDENT:/home/student \
    student-lab:latest

  sleep 2

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
