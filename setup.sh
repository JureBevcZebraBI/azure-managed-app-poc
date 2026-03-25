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

# Install basic packages + Docker
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y universe || true
apt-get update
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# --- Create Docker network ---
docker network inspect zai-net >/dev/null 2>&1 || docker network create zai-net

# --- Start Redis container ---
docker rm -f redis 2>/dev/null || true
docker run -d \
  --name redis \
  --network zai-net \
  -p 6379:6379 \
  redis:7

echo "Redis started at redis://redis:6379 on network 'zai-net'"

# --- App config ---
mkdir -p /opt/app
cat <<EOF > /opt/app/.env
REDIS_URI=redis://redis:6379
DB_URI=${DB_URI}
EOF

# --- Login & pull app image ---
echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_SERVER" -u "$REGISTRY_USERNAME" --password-stdin
docker pull "$CONTAINER_IMAGE"

# --- Start app container ---
docker rm -f app 2>/dev/null || true
docker run -d \
  --name app \
  --restart always \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --env-file /opt/app/.env \
  --network zai-net \
  -p 80:80 \
  -p 8000:8000 \
  -p 60006:60006 \
  "$CONTAINER_IMAGE"

echo "=== Setup complete ==="