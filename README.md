# Description

The goal of this project is to create a docker compose setup that will maximally automate the setup of a production-ready psibase full-node.

# Requirements

* Ubuntu 22.04 or later
* SSH-access to the server
* Install prerequisites
    * [Docker install guide](https://docs.docker.com/engine/install/)
    * [Docker compose install guide](https://docs.docker.com/compose/install/)
    * git
* Domain name pointed at server IP

## Set up docker permissions

Run the `scripts/setup-docker-permissions.sh` script and reboot.

<details>
  <summary>Why?</summary>

  Docker must run as root due to [overlay network requirements](https://docs.docker.com/engine/security/rootless/#known-limitations) in Docker Swarm. To avoid using `sudo` for every Docker command, add your non-root user to the Docker group. Otherwise you'll get permissions errors when running commands like `docker container ls`.
</details>

## Set up the x-admin password

Run the `scripts/setup-xadmin-password.sh` script, follow the prompts to create a username and password.

<details>
  <summary>Why?</summary>

  The X-Admin area is used to manage the node. It should be protected from being accessed by the public and therefore needs password authentication.
</details>


## Set up DNS



