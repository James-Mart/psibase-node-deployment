#!/bin/bash
set -euo pipefail

sudo apt update && sudo apt install -y systemd-coredump
sudo systemctl start systemd-coredump.socket