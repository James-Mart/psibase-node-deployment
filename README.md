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
  * Create an `A record` mapping `yourdomain.com` to the elastic IP
  * Create an `A record` mapping the wildcard subdomain `*.yourdomain.com` to the elastic IP
* Install prerequisites
    * [Docker install guide](https://docs.docker.com/engine/install/)
    * [Docker compose install guide](https://docs.docker.com/compose/install/)
    * `git`

## Set up .env file

Copy the `.env.template` file to `.env` and fill in the variables. These variables are used by various scripts to configure the services used for deployment.

## Set up docker permissions

Run the `scripts/setup-docker-permissions.sh` script and reboot.

<details>
  <summary>Why?</summary>

  Docker must run as root due to [overlay network requirements](https://docs.docker.com/engine/security/rootless/#known-limitations) in Docker Swarm. To avoid using `sudo` for every Docker command, add your non-root user to the Docker group. Otherwise you'll get permissions errors when running commands like `docker container ls`.
</details>

## Create certificate

Run the `scripts/create-cert.sh` script.

<details>
  <summary>Why?</summary>

  This generates the certificate for the domain name.
</details>

