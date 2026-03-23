#!/bin/bash
set -e

# --- CONFIG (injected via ARM or replace manually) ---
CONTAINER_IMAGE="${CONTAINER_IMAGE}"
REDIS_URI="${REDIS_URI}"
DB_URI="${DB_URI}"
REGISTRY_SERVER="${REGISTRY_SERVER}"
REGISTRY_USERNAME="${REGISTRY_USERNAME}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD}"

# --- Install Docker ---
apt-get update
apt-get install -y docker.io

systemctl enable docker
systemctl start docker

# --- Login to registry ---
echo "$REGISTRY_PASSWORD" | docker login $REGISTRY_SERVER -u $REGISTRY_USERNAME --password-stdin

# --- Pull image ---
docker pull $CONTAINER_IMAGE

# --- Run container (privileged + docker socket) ---
docker run -d \
  --name app \
  --restart always \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 80:80 \
  -p 8000:8000 \
  -p 60006:60006 \
  -e REDIS_URI="$REDIS_URI" \
  -e DB_URI="$DB_URI" \
  $CONTAINER_IMAGE