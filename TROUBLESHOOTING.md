# Troubleshooting

## No HSM detected

This error typically means that you did the following:
1. Launched the node
2. Did not boot or peer with another node
3. Restarted the node

This is a bug/limitation with the current setup. If you restart the node before actually booting or peering, you need to do a fresh restart (`.scripts/restart-node-fresh.sh`).
