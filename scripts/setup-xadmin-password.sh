#!/bin/bash

# Get the workspace root directory (parent of scripts directory)
WORKSPACE_ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Install apache2-utils for htpasswd command
sudo apt-get update
sudo apt-get install -y apache2-utils

read -p "Enter username for x-admin: " username

htpasswd -c "$WORKSPACE_ROOT/secrets/.htpasswd" "$username"