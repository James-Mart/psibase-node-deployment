#!/bin/bash
# setup-admin-auth.sh

# Check if username was provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <username>"
  echo "Example: $0 psinode-admin"
  exit 1
fi

USERNAME=$1

# Create directory for authentication files
mkdir -p ./traefik/auth

# Install apache2-utils for htpasswd utility
sudo apt-get update && sudo apt-get install -y apache2-utils

# Create the password file with the provided username
echo "Creating password file for user: $USERNAME"
echo "You will be prompted to enter and confirm a password."
htpasswd -c ./traefik/auth/users $USERNAME

# Set proper file permissions
chmod 600 ./traefik/auth/users

echo "Basic authentication setup complete for $USERNAME"
echo "Restart Docker Compose to apply changes: docker compose down && docker compose up -d" 