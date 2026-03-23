#!/bin/bash
set -euo pipefail

CONTAINER_IMAGE="$1"
REDIS_URI="$2"
DB_URI="$3"
REGISTRY_SERVER="$4"
REGISTRY_USERNAME="$5"
REGISTRY_PASSWORD="$6"

echo "=== Starting setup ==="

if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker.io
  systemctl enable docker
  systemctl start docker
fi

mkdir -p /opt/app

cat <<EOF > /opt/app/.env
REDIS_URI=${REDIS_URI}
DB_URI=${DB_URI}
EOF

echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_SERVER" -u "$REGISTRY_USERNAME" --password-stdin

docker pull "$CONTAINER_IMAGE"

if docker ps -a --format '{{.Names}}' | grep -q '^app$'; then
  docker rm -f app
fi

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