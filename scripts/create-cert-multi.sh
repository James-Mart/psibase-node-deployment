#!/bin/bash

# Used when initially creating the tls certificate with certbot using IWantMyName DNS provider
# Only used during initial setup, after which the cert only needs to be renewed using `renew-cert.sh`

# CLI params:
# --dry-run         Test "renew" or "certonly" without saving any certificates 

# Parse command line arguments
DRY_RUN=""
if [ "$1" == "--dry-run" ]; then
    DRY_RUN="--dry-run"
fi

SCRIPT_DIR="$(dirname "$0")"

set -a
source "$SCRIPT_DIR/../.env"

docker pull ghcr.io/alexzorin/certbot-dns-multi:latest
docker tag ghcr.io/alexzorin/certbot-dns-multi:latest certbot

# Run certbot with dns-multi plugin
docker run -it --rm \
    --name certbot \
    -v "$SCRIPT_DIR/../letsencrypt/certs:/etc/letsencrypt" \
    -v "$SCRIPT_DIR/../iwantmyname-dns-multi.ini:/etc/letsencrypt/dns-multi.ini" \
    -v "$SCRIPT_DIR/../secrets/iwantmyname_username:/run/secrets/iwantmyname_username:ro" \
    -v "$SCRIPT_DIR/../secrets/iwantmyname_password:/run/secrets/iwantmyname_password:ro" \
    certbot certonly \
    -n \
    --agree-tos \
    -d $HOST,*.$HOST \
    --keep-until-expiring \
    --expand \
    --preferred-challenges dns \
    --authenticator dns-multi \
    --dns-multi-credentials /etc/letsencrypt/dns-multi.ini \
    --dns-multi-propagation-seconds 60 \
    $DRY_RUN

# Run `certbot --help all` to see a much more comprehensive help menu for all the above options.