# Troubleshooting

## No HSM detected

This error typically means that you did the following:
1. Launched the node
2. Did not boot or peer with another node
3. Restarted the node

This is a bug/limitation with the current setup. If you restart the node before actually booting or peering, you need to do a fresh restart (`.scripts/restart-node-fresh.sh`).

## Core dumps

> **Note**: This section is only applicable if you completed the optional "Core Dump Configuration" step in [SETUP.md](./SETUP.md#core-dump-configuration-optional).

The psinode container is configured to generate core dumps when the process crashes. Since the container shares the host kernel, core dumps are captured by the host's systemd-coredump service.

### Checking for core dumps

List all available core dumps:
```bash
coredumpctl list
```

### Extracting core dumps

To extract a specific core dump to a file:
```bash
# Extract by PID
coredumpctl dump <PID> > core-psinode-<PID>.dump

# Extract the most recent coredump
coredumpctl dump > core-psinode-latest.dump
```

### Getting crash information

View details about a specific coredump:
```bash
coredumpctl info <PID>
```

### Filtering for psinode crashes

To see only psinode-related coredumps:
```bash
coredumpctl list | grep psinode
```

### Cleaning up old coredumps

Remove coredumps older than a specified number of days:
```bash
coredumpctl clean <days>
```
