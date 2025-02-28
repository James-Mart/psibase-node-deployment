#!/bin/bash

# Restart docker compose services with a fresh psinode volume
echo "Bringing down all containers..."
docker compose down --remove-orphans

echo "Removing psinode volume..."
docker volume rm psibase-node_psinode-volume || echo "[Warning] Volume doesn't exist or cannot be removed"

echo "Starting services with clean volume..."
docker compose up -d

echo "Node restarted with fresh psinode volume." 