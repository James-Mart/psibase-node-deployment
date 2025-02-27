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

### Set up basic authentication for admin subdomain

The `x-*.${HOST}` subdomains are protected with basic authentication. Run the setup script with your desired username and follow prompts to create the password file used for basic-auth.

For example:
```bash
./.setup/setup-admin-auth.sh psinode-admin
```

### After boot (or peering) is complete

### Set the psinode logger config

The default loggers are probably not sufficient for production use.


<details>
  <summary>Show logger config</summary>

```
[logger.stderr]
type   = console
filter = Severity >= info
format = [{TimeStamp}] [{Severity}]{?: [{RemoteEndpoint}]}: {Message}{?: {TransactionId}}{?: {BlockId}}{?RequestMethod:: {RequestMethod} {RequestHost}{RequestTarget}{?: {ResponseStatus}{?: {ResponseBytes}}}}{?: {ResponseTime} µs}{Indent:4:{TraceConsole}}

# Log all HTTP reqests to a separate file
[logger.http]
type         = file
filter       = ResponseStatus
format       = [{TimeStamp}] [{RemoteEndpoint}]: {RequestHost}: {RequestMethod} {RequestTarget}{?: {ResponseStatus}{?: {ResponseBytes}}}
filename     = http.log
target       = http-%3N.log
rotationSize = 64 MiB
rotationTime = R/2022-10-01T00:00:00Z/P1D
maxFiles     = 10
flush        = on
```  
</details>

# Management

- **(Re)Starting the node**: `.scripts/restart-node.sh`
- **Stopping the node**: `.scripts/stop-node.sh`
- **Viewing psinode server logs**: `.scripts/show-logs.sh`
- **Accessing admin dashboard**: Visit `https://x-admin.{HOST}`

## Updating psinode

Changing `PSINODE_IMAGE` in `.env` and redeploying the compose file is likely insufficient. It will work for backwards compatible updates, but not for new major versions because the psinode database is not automatically cleared.

To update and reset the database, you have to bring down compose, delete the volumes related to the psinode database, and then restart compose (with an updated `PSINODE_IMAGE`).
