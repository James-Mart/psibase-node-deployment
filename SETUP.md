# Setup

## EC2 setup

The following instructions are all handled in the AWS dashboard.

* Use an r7a family instance (memory optimized).
* Use Ubuntu 22.04 or later.
* SSH-access to the server
* Allow http/https web traffic (open ports 80/443).
* Allow SSH access (open port 22).
* Configure an elastic IP and associate it with the instance.

## Domain setup

* Buy a domain
* Create a cloudflare account
* Point domain at cloudflare nameservers
* In Cloudflare, add A records:
  | Type | Name    | Content     | Proxy Status | TTL  |
  |------|---------|-------------|--------------|------|
  | A    | domain  | elastic-IP  | proxied      | auto |
  | A    | *       | elastic-IP  | proxied      | auto |

* Create a cloudflare API key for the domain with the following permissions:
  * Zone - DNS - Edit
  * Zone - Zone - Read

* Go to TLS/SSL settings, change encryption mode from `Flexible` to `Full (Strict)`
  * If you don't do this, you will continually get "Error: Too many redirects" when trying to load the host in browser

## Server setup

The following instructions are handled on the server directly (ssh).

### Install prerequisites

  * [Docker install guide](https://docs.docker.com/engine/install/)
  * [Docker compose install guide](https://docs.docker.com/compose/install/)
  * `git`

### Clone this repo

From `/home/ubuntu` on your server, run `git clone https://github.com/James-Mart/psibase-node-deployment.git` to install this repository onto the server.
The rest of the instructions use paths relative to the `psibase-node-deployment` directory created by the clone operation.

### Set up `.env` file

Copy the `.env.template` file to a new file called `.env` and fill in the variables. These variables are automatically used to configure the deployment services.

### Set up docker permissions

To avoid Docker permissions errors, add your non-root user to the Docker group.
To do this, run the `.setup/docker-permissions.sh` script and reboot.

### Provision admin authentication credentials

The `x-*.${HOST}` subdomains require authentication. Run the setup script with your desired username and follow the password prompts. One password provisions both the Authelia session credential (authelia/users_database.yml) and the break-glass Basic credential (traefik/auth/users) together. The script uses Docker only — no host packages such as `apache2-utils` are required.

For example:
```bash
./.setup/setup-admin-auth.sh psinode-admin
```

For unattended provisioning (for example from automation), pass the username and read the password from standard input:
```bash
printf '%s\n' 'your-password' | ./.setup/setup-admin-auth.sh --username psinode-admin --password-stdin
```

To rotate the password, re-run the script with the same username and enter the new password, then restart Docker Compose.

If Authelia is down and every `x-*` surface returns 502, you can still reach the
log viewer with the Basic credential above — see
[Authelia down: break-glass access to x-logs](./TROUBLESHOOTING.md#authelia-down-break-glass-access-to-x-logs).

### Core Dump Configuration (Optional)

To enable core dump capture when the psinode process crashes, run the setup script:

```bash
./.setup/setup-systemd-coredumps.sh
```

This configures the psinode container to generate core dumps that can be analyzed for debugging crashes. See the [Core dumps section in TROUBLESHOOTING.md](./TROUBLESHOOTING.md#core-dumps) for usage instructions.

### After boot (or peering) is complete

### Set the psinode logger config

The default loggers are probably not sufficient for production use. Your needs may vary, consider taking time to study the psinode logging configurations and building the config that makes the most sense for your usecase.


<details>
  <summary>Show example logger configs</summary>

```
# Log non-http requests to stderr
[logger.stderr]
type   = console
filter = Severity >= debug & not ResponseStatus
format = [{TimeStamp}] [{Severity}]{?: [{RemoteEndpoint}]}: {Message}{?: {TransactionId}}{?: {BlockId}}{?RequestMethod:: {RequestMethod} {RequestHost}{RequestTarget}{?: {ResponseStatus}{?: {ResponseBytes}}}}{?: {ResponseTime} µs}{Indent:4:{TraceConsole}}

# Log all HTTP requests to a separate file
[logger.http]
type         = file
filter       = ResponseStatus
format       = [{TimeStamp}] [{RemoteEndpoint}]: {RequestHost}: {RequestMethod} {RequestTarget}{?: {ResponseStatus}{?: {ResponseBytes}}}
filename     = /root/psibase/db/http.log
target       = /root/psibase/db/http-%3N.log
rotationSize = 67108864
rotationTime = R/2022-10-01T00:00:00Z/P1D
maxFiles     = 10
flush        = on

# Log p2p traffic to a separate file
[logger.p2p]
type         = file
filter       = Severity >= debug & Channel = p2p
format       = [{TimeStamp}] [{Severity}]{?: [{RemoteEndpoint}]}: {Message}
filename     = /root/psibase/db/p2p.log
target       = /root/psibase/db/p2p-%3N.log
rotationSize = 67108864
rotationTime = R/2022-10-01T00:00:00Z/P1D
maxFiles     = 10
flush        = on

```  
</details>

# Management

- **(Re)Starting the node**: `.scripts/restart-node.sh`
- **Stopping the node**: `.scripts/stop-node.sh`
- **Viewing psinode server logs**: `.scripts/psinode-logs.sh`
- **Accessing admin dashboard**: Visit `https://x-admin.{HOST}` (first login redirects through the Authelia portal at `https://x-auth.{HOST}`)
- **Disk usage analysis**: Visit `https://x-disk.{HOST}`

## Migrating to Authelia session auth

For operators already running a node on an older revision of this repository (HTTP Basic on each `x-*` subdomain), follow these steps in order. They update the admin perimeter only — **nothing here touches chain data, the psinode database, or the HSM keys.** Do **not** use `.scripts/restart-node-fresh.sh`; that script wipes the psinode volume and is unrelated to this migration.

1. **Pull the latest changes** on your server (`git pull` in your clone of this repository).

2. **Add the new `.env` values** that `.env.template` now includes:
   - `AUTHELIA_IMAGE` — copy the default from `.env.template` if your `.env` does not have it yet
   - `AUTHELIA_SESSION_SECRET` and `AUTHELIA_STORAGE_ENCRYPTION_KEY` — generate each (run once per variable) with:
     ```bash
     docker run --rm ${AUTHELIA_IMAGE} authelia crypto rand --length 64 --charset alphanumeric
     ```
   Skipping these secrets is not a soft failure: Traefik fails closed and every `x-*` surface returns **502** until they are set. The fix is to populate them — do not bypass the proxy.

3. **Re-provision admin credentials** with the same username you used before:
   ```bash
   ./.setup/setup-admin-auth.sh <your-username>
   ```
   One password still provisions both the Authelia session store (authelia/users_database.yml) and the break-glass Basic file (traefik/auth/users). The Basic file is deliberately kept but is **no longer** the login path for the toolkit — you sign in through Authelia.

4. **Restart the stack:**
   ```bash
   ./.scripts/restart-node.sh
   ```

5. **Log in** at `https://x-auth.${HOST}` (use your domain in place of `${HOST}`). After that, every `x-*` tool shares that session.

The **Peers** panel in `x-admin` still needs a psinode build that includes psibase#1987 and a node-local package upgrade — see [Updating psinode](#updating-psinode). That is separate from this auth migration and does not wipe chain data.

**Auth posture.** A single password guards all admin surfaces — the same one-factor protection Basic gave you, now as a domain-scoped session. Authelia supports TOTP as a second factor; this deployment deliberately enables password-only login. For TOTP, see [Authelia's time-based one-time password documentation](https://www.authelia.com/configuration/second-factor/time-based-one-time-password/) rather than enabling it here without understanding the change.

**Sessions.** Authelia keeps its identity database on disk, but without Redis, active sessions live in the Authelia process. Restarting Authelia (for example when you run `.scripts/restart-node.sh`) ends them — log in again at `https://x-auth.${HOST}`.

**Credential rotation.** Re-run `./.setup/setup-admin-auth.sh` with the same username and restart — see [Provision admin authentication credentials](#provision-admin-authentication-credentials).

## Updating psinode

Changing `PSINODE_IMAGE` in `.env` and redeploying the compose file is likely insufficient. It will work for backwards compatible updates, but not for new major versions because the psinode database is not automatically cleared.

To update and reset the database, you have to bring down compose, delete the volumes related to the psinode database, and then restart compose (with an updated `PSINODE_IMAGE`).

### Peers panel: psinode version and node-local packages

The **Peers** panel in `x-admin` calls `x-peers` from the browser. That only works if the node is running a psinode build that includes [psibase#1987](https://github.com/gofractally/psibase/pull/1987), merged 2026-08-10.

No release includes that yet. The newest published tag is `v0.25.0-pre` (2026-08-05), which predates the merge. Watch [psibase releases](https://github.com/gofractally/psibase/releases) after that date and set `PSINODE_IMAGE` to a tag that contains the fix — do not assume a version that does not exist.

`XAdmin` and `XPeers` are node-local `.psi` packages stored in the psinode database. Changing the image does not replace packages already installed on an existing volume. After the node is running a build that includes the fix, upgrade those packages without wiping chain data:

1. Open `https://x-admin.{HOST}` (sign in at `https://x-auth.{HOST}` first if you have not already).
2. Open the **Packages** tab.
3. Update the node-local packages that show an update.

CLI alternative, from this repository on the server, **inside** the psinode container:

```bash
docker compose exec psinode psibase upgrade --local
```

Run it there, not from the host. `psibase upgrade --local` pushes packages to local service subdomains. Those hosts now sit behind the Authelia perimeter, so from the host the CLI would need a portal session. Inside the container it reaches psinode over loopback, which psinode already trusts.

Once the packages are updated, open the **Peers** panel in `x-admin`. It should list peers, and adding or disconnecting one should succeed.

If every other `x-*` surface works but the peers panel alone fails with a CORS or network error in the browser console, that is the packages, not the perimeter — see [Peers panel fails with a CORS or network error](./TROUBLESHOOTING.md#peers-panel-fails-with-a-cors-or-network-error).

## Restarting psinode

If you restart psinode and you are a block producer, you will need to unlock your hsm device again that holds your block signing keys. This can be done in the `x-admin` app.

# Optional 

## Dynamic DNS
Dynamic DNS with the existing Cloudflare token can be used in the event your server does not have a static IP address. 

- In `/ddclient` Rename `ddclient.conf.example` to `ddclient.conf` and add relevant variables.
- Uncomment ddclient in `docker-compose.yml`
- Restart with `.scripts/restart-node.sh`
