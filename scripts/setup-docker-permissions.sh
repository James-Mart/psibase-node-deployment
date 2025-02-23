#!/bin/bash

echo "Checking if docker group exists..."
if ! getent group docker > /dev/null 2>&1; then
    echo "Creating docker group..."
    sudo groupadd docker
else
    echo "Docker group already exists"
fi

echo "Adding current user ($USER) to docker group..."
sudo usermod -aG docker "$USER"

echo "Setup complete! Please reboot your system for changes to take effect"
echo "You can reboot by running: sudo reboot" 