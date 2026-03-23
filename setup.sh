#!/bin/bash
set -euo pipefail

echo "=== Starting setup ==="

# Install Docker if missing
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker.io
  systemctl enable docker
  systemctl start docker
fi

mkdir -p /opt/app

# Write .env file
cat <<EOF > /opt/app/.env
REDIS_URI=${REDIS_URI}
DB_URI=${DB_URI}
EOF

# Login to registry
echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_SERVER" -u "$REGISTRY_USERNAME" --password-stdin

# Pull the image
docker pull "$CONTAINER_IMAGE"

# Remove existing container if exists
if docker ps -a --format '{{.Names}}' | grep -q '^app$'; then
  docker rm -f app
fi

# Run container
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