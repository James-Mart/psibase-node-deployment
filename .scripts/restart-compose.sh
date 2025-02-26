#!/bin/bash

# Restart docker compose services
docker compose down --remove-orphans && docker compose up -d 