# Description

The goal of this project is to create a docker compose setup that will maximally automate the setup of a production-ready psibase full-node.

# EC2 Server setup instructions

* Use an r7a family instance (memory optimized).
* Use Ubuntu 22.04 or later.
* SSH-access to the server
* Allow http/https web traffic (open ports 80/443).
* Allow SSH access (open port 22).
* Configure an elastic IP and associate it with the instance.
* Buy a domain name
  * Set the nameservers to point to a cloudflare account, so DNS can be managed by cloudflare.
  * Create a cloudflare API key for the domain with the following permissions:
    * Zone - DNS - Edit
    * Zone - Zone - Read
* Install prerequisites
    * [Docker install guide](https://docs.docker.com/engine/install/)
    * [Docker compose install guide](https://docs.docker.com/compose/install/)
    * `git`

## Set up .env file

Copy the `.env.template` file to `.env` and fill in the variables. These variables are used by various scripts to configure the services used for deployment.

## Set up docker permissions

Run the `.setup/docker-permissions.sh` script and reboot.

<details>
  <summary>Why?</summary>

  Docker must run as root due to [overlay network requirements](https://docs.docker.com/engine/security/rootless/#known-limitations) in Docker Swarm. To avoid using `sudo` for every Docker command, add your non-root user to the Docker group. Otherwise you'll get permissions errors when running commands like `docker container ls`.
</details>

## Set up basic authentication for admin subdomain

The `x-admin.${HOST}` subdomain is protected with basic authentication. Run the setup script with your desired username:

```bash
./.setup/setup-admin-auth.sh psinode-admin
```

You will be prompted to enter and confirm a password for the user.

The script automatically creates the necessary directories, installs required utilities, creates the password file, and sets appropriate permissions. After running the script, you'll need to restart Docker Compose to apply the changes.

## After boot (or peering) is complete

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

### Updating psinode version

Changing `PSINODE_IMAGE` in `.env` and redeploying the compose file is likely insufficient. It will work for backwards compatible updates, but not for new major versions because the psinode database is not automatically cleared.

To update and reset the database, you have to bring down compose, delete the volumes related to the psinode database, and then restart compose (with an updated `PSINODE_IMAGE`).
