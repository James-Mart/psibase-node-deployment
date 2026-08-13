# Troubleshooting

## Authelia down: break-glass access to x-logs

When Authelia is missing, unprovisioned, or unhealthy, Traefik's `forwardAuth`
middleware fails closed: every `x-*` surface answers **502 Bad Gateway**. That is
the right default for `x-admin`, but it is exactly when you most need the log
viewer.

The repository ships an incident-only override that swaps session auth on
`x-logs` for the Basic credential provisioned by
`.setup/setup-admin-auth.sh`. It lives in `traefik/break-glass/logs.yml`, which
is committed but **not** loaded until you copy it into the watched config
directory.

### Enable (no restart)

```bash
cp traefik/break-glass/logs.yml traefik/config/
```

Traefik's file provider watches `traefik/config/`; the change takes effect
immediately.

Log in with the username and password from when you ran
`./.setup/setup-admin-auth.sh` — the same prompt that provisioned Authelia.

**Leaving this file in place leaves a second, weaker perimeter on the log
viewer.** Use it only while diagnosing the auth outage.

### Disable

```bash
rm traefik/config/logs.yml
```

After Authelia is healthy again, `https://x-logs.{HOST}` should redirect to the
portal at `https://x-auth.{HOST}` instead of prompting for Basic auth.

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

### Initial Authentication

Intended to work like this 

```mermaid
sequenceDiagram
    participant Client
    participant Traefik
    participant Authelia
    participant Psinode

    Client->>Traefik: GET x-admin.host (may include Remote-User)
    Note over Traefik: strip-auth-header blanks Remote-User and X-Auth-User
    Traefik->>Authelia: forwardAuth (HOST-scoped session cookie)
    alt no session
        Authelia-->>Traefik: redirect to x-auth.host
        Traefik-->>Client: 302 to portal
        Note over Client,Authelia: operator logs in; Authelia sets HOST-scoped session cookie
        Client->>Traefik: GET x-admin.host (session cookie)
        Traefik->>Authelia: forwardAuth
    end
    Authelia-->>Traefik: 200 + Remote-User
    Traefik->>Psinode: Request with Remote-User header
    Note over Psinode: PSIBASE_USERNAME_FIELD=Remote-User
    Psinode->>Client: Response
```