#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

CONTAINER_IMAGE="$1"
REDIS_URI="$2"
DB_URI="$3"
REGISTRY_SERVER="$4"
REGISTRY_USERNAME="$5"
REGISTRY_PASSWORD="$6"

echo "=== Starting setup ==="

# Basic packages + ensure repo works
apt-get update
apt-get install -y software-properties-common

# Ensure universe repo (fixes docker.io not found)
add-apt-repository -y universe || true
apt-get update

# Install Docker
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# App config
mkdir -p /opt/app

cat <<EOF > /opt/app/.env
REDIS_URI=${REDIS_URI}
DB_URI=${DB_URI}
EOF

# Login & pull
echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_SERVER" -u "$REGISTRY_USERNAME" --password-stdin
docker pull "$CONTAINER_IMAGE"

# Restart container
docker rm -f app 2>/dev/null || true

docker run -d \
  --name app \
  --restart always \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --env-file /opt/app/.env \
  -p 80:80 \
  -p 8000:8000 \
  -p 60006:60006 \
  "$CONTAINER_IMAGE"

echo "=== Setup complete ==="