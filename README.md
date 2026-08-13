## Project Overview

This repository contains a Docker Compose-based deployment solution for running a production-ready Psibase full node. The project provides an automated setup for deploying and managing a Psibase blockchain node with proper networking, security, and infrastructure configurations.

> **Warning**
> This deployment tool is still in active development, and there are no security guarantees. You are responsible for auditing all configurations and scripts before using in a production environment.

## Purpose

The primary goal of this project is to simplify the deployment of a Psibase blockchain node by providing:

1. Automated setup of a production-grade containerized psibase full node
2. Secure access to the node's API and services
3. Secure access to ancillary tooling (traefik dashboards, prometheus, grafana, etc.)
4. Proper network configuration and container routing

## Technical Stack

The project uses the following technologies:

- **Docker & Docker Compose**: For containerization and service orchestration
- **Psibase**: The blockchain node software (psinode)
- **Traefik v3.3**: Reverse proxy for routing, SSL termination, and authentication
- **Cloudflare**: For DNS management and SSL certificate issuance
- **SoftHSM2**: For secure key management
- **Bash Scripts**: For automation and setup procedures

## Architecture

```svgbob
                                                     Node Architecture
   .---------------------------------------------------------------------------------------------------------------------.
   |                                                                                                                     |
   |                                                                                                                     |
   |                                 +------------------+                                                                |
   |                                 |                  |                                                                |
------Incoming Request (HTTP) ------>|    HTTP:80       |                                                                |
   |                                 |    Entrypoint    |                                                                |
   |                                 |                  |                                                                |
   |                                 +------------------+                                                                |
   |                                         |                                                                           |
   |                                         | redirect                                                                  |
   |                                         v                                                                           |
   |                                 +------------------+                                                                |
   |                                 |                  |                                                                |
------Incoming Request (HTTPS) ----->|    HTTPS:443     |                                                                |
   |                                 |    Entrypoint    |                                                                |
   |                                 |                  |                                                                |
   |                                 +------------------+                                                                |
   |                                         |                                                                           |
   |              +--------------------------+--------------------------+------------------------+                       |
   |              |                          |                          |                        |                       |
   |              v                          v                          v                        v                       |
   |    +------------------+      +--------------------+      +---------------------+  +----------------------+          |
   |    |                  |      |                    |      |                     |  |                      |          |
   |    |  Main Router     |      |  Subdomain Router  |      |  x-* Routers        |  |  Auth Router         |          |
   |    |  Host(`{HOST}`)  |      |  Host(`*.{HOST}`)  |      |  Host(`x-admin.*`)  |  |  Host(`x-auth.*`)    |          |
   |    |                  |      |                    |      |                     |  |                      |          |
   |    +------------------+      +--------------------+      +---------------------+  +----------------------+          |
   |              |                          |                         |                         |                       |
   |              |                          |                         |                         |                       |
   |              +------------+-------------+                         |                         |                       |
   |                           |                                       |                         |                       |
   |                           v                                       v                         v                       |
   |                 +------------------+                    +---------------------+   +---------------------+           |
   |                 |                  |                    |                     |   |                     |           |
   |                 |  psinode:8090    |                    |  Authelia session   |   |  Authelia portal    |           |
   |                 |                  |                    |  (fails closed)     |   |                     |           |
   |                 |                  |                    |                     |   |                     |           |
   |                 +------------------+                    +---------------------+   +---------------------+           |
   |                                                                                                                     |
   '---------------------------------------------------------------------------------------------------------------------'
```

The deployment currently consists of three main services:

1. **psinode**: The Psibase blockchain node container
   - Runs the Psibase node software
   - Manages blockchain data
   - Endpoints only exposed internally on port 8090
   - Uses SoftHSM2 for key management

2. **reverse-proxy** (Traefik): 
   - Handles all incoming HTTP/HTTPS traffic
   - Manages SSL certificates via Cloudflare DNS challenge
   - Routes traffic to appropriate services
   - Provides dashboard access for monitoring
   - Enforces security headers and the Authelia session for protected apps (x-admin, x-traefik, etc.)

3. **authelia**:
   - Login portal at `x-auth.{HOST}`
   - Domain-scoped session that is the perimeter for all `x-*` admin surfaces
   - Mandatory; Traefik fails closed (502) if Authelia is missing or down

## File Structure

```
├── .cursor/                   # Cursor editor-specific files
├── .scripts/                  # Utility scripts
│   ├── initialize-git.sh      # Git initialization script
│   ├── restart-node-fresh.sh  # Script to restart services with a fresh psinode volume
│   ├── restart-node.sh        # Script to restart Docker Compose services
│   ├── psinode-logs.sh        # Script to display psinode logs
│   ├── traefik-logs.sh        # Script to display traefik (reverse-proxy) logs
│   └── stop-node.sh           # Script to stop all Docker Compose services
├── .setup/                    # Setup scripts (run once)
│   ├── docker-permissions.sh  # Sets up Docker permissions
│   └── setup-admin-auth.sh    # Sets up basic authentication file for authorization to private apps
├── .vscode/                   # VSCode editor-specific files
├── ddclient/                  # DDClient configuration
│   └── ddclient.conf.example  # Config file with cloudflare token 
├── softhsm/                   # SoftHSM configuration
│   └── Dockerfile             # Dockerfile for building SoftHSM container with initialized token
├── traefik/                   # Traefik configuration
│   ├── acme/                  # Directory for storing SSL certificates
│   ├── auth/                  # Authentication files for admin access
│   ├── config/                # Traefik dynamic routing and middleware configuration
│   │   ├── middlewares.yml    # Traefik middleware configuration
│   │   └── routers.yml        # Traefik routing rules
│   └── traefik.yml            # Main Traefik static configuration
├── .env.template              # Template for environment variables
├── .gitignore                 # Git ignore file
├── docker-compose.psinode.yml # Psinode service configuration
├── docker-compose.proxy.yml   # Traefik proxy configuration
├── docker-compose.softhsm.yml # SoftHSM service configuration
├── docker-compose.yml         # Main Docker Compose file that includes other compose files
├── psinode-entrypoint.sh      # Custom entrypoint script for the psinode container
├── README.md                  # This file
├── SETUP.md                   # Documentation and setup instructions
└── TROUBLESHOOTING.md         # Troubleshooting guide for common issues
```

## Deployment Configuration

### Network Configuration

The deployment sets up the following network endpoints:

- HTTP on port 80 (redirects to HTTPS)
- HTTPS on port 443
- Internal psinode listens on port 8090

### Routing and Security

Traefik currently manages the following routes:

- `{HOST}`: Main access to the Psibase node
- `*.{HOST}`: Subdomains routed to the Psibase node (except admin subdomains)
- `x-auth.{HOST}`: Authelia login portal
- `x-admin.{HOST}`: Admin interface for the node (Authelia session)
- `x-traefik.{HOST}`: Traefik dashboard (Authelia session)

## Security Features

- HTTPS encryption using Let's Encrypt with Cloudflare DNS verification
- Single Authelia session perimeter for all `x-*` admin surfaces; if Authelia is missing or down, Traefik fails closed (502) rather than serving them
- CORS preflight `OPTIONS` to psinode-served `x-*` hosts (for example `x-peers.{HOST}`) bypass Authelia session checks so the request reaches psinode; this deployment's own tool hosts (`x-auth`, `x-traefik`, `x-logs`, `x-disk`) and all non-`OPTIONS` requests still require a session. Bypassing Authelia authorizes nothing: psinode still applies its own `checkAuth`, so a service that pre-handles `OPTIONS` answers with CORS headers and an empty body, and one that does not answers its own 401. Those CORS headers come back only when `Origin` is HTTPS and matches `x-admin.{HOST}`, and no reply depends on the request target, so a bare `curl` gets nothing usable and no way to enumerate paths
- Security headers for all HTTP responses
- SoftHSM2 for secure key management
- Automatic HTTP to HTTPS redirection

## Data Persistence

The deployment uses Docker volumes for persistent data:

- `psinode-volume`: Stores blockchain data and configuration
- `softhsm-keys`: Stores cryptographic keys for the node

## Setup

See [SETUP.md](./SETUP.md). Operators already running a node and upgrading from HTTP Basic auth should follow [Migrating to Authelia session auth](./SETUP.md#migrating-to-authelia-session-auth).