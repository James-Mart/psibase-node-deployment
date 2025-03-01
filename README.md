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
   |    |  Main Router     |      |  Subdomain Router  |      |  Admin Router       |  |  Traefik Router      |          |
   |    |  Host(`{HOST}`)  |      |  Host(`*.{HOST}`)  |      |  Host(`x-admin.*`)  |  |  Host(`x-traefik.*`) |          |
   |    |                  |      |                    |      |                     |  |                      |          |
   |    +------------------+      +--------------------+      +---------------------+  +----------------------+          |
   |              |                          |                         |                         |                       |
   |              |                          |                         |                         |                       |
   |              +------------+-------------+-------------------------+                         |                       |
   |                                         |                                                   |                       |
   |                                         v                                                   v                       |
   |                               +------------------+                                +---------------------+           |
   |                               |                  |                                |                     |           |
   |                               |  psinode:8090    |                                |  traefik dashboard  |           |
   |                               |  +BasicAuth      |                                |  +BasicAuth         |           |
   |                               |                  |                                |                     |           |
   |                               +------------------+                                +---------------------+           |
   |                                                                                                                     |
   '---------------------------------------------------------------------------------------------------------------------'
```

The deployment currently consists of two main services:

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
   - Enforces security headers and authentication for protected apps (x-admin, x-traefik, etc.)

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
- `x-admin.{HOST}`: Admin interface for the node (protected by basic auth)
- `x-traefik.{HOST}`: Traefik dashboard (protected by basic auth)

## Security Features

- HTTPS encryption using Let's Encrypt with Cloudflare DNS verification
- Basic authentication for admin interfaces
- Security headers for all HTTP responses
- SoftHSM2 for secure key management
- Automatic HTTP to HTTPS redirection

## Data Persistence

The deployment uses Docker volumes for persistent data:

- `psinode-volume`: Stores blockchain data and configuration
- `softhsm-keys`: Stores cryptographic keys for the node

## Setup

See [SETUP.md](./SETUP.md).