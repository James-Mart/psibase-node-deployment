#!/bin/bash

# Used when initially creating the tls certificate with certbot. Only used during initial setup,
#   after which the cert only needs to be renewed using `renew-cert.sh` (from a cronjob).
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

GOOGLE_DNS_CREDS_FILE_NAME="" #  e.g. google-dns-cred.json
if [ "$GOOGLE_DNS_CREDS_FILE_NAME" = "" ]; then
    echo "Error: GOOGLE_DNS_CREDS_FILE_NAME not set."
    exit 1
fi

docker pull certbot/dns-google:latest
docker tag certbot/dns-google:latest certbot
docker run -it --rm \
    --name certbot \
    -v "$SCRIPT_DIR/../secrets/$GOOGLE_DNS_CREDS_FILE_NAME:/.secrets/certbot/$GOOGLE_DNS_CREDS_FILE_NAME" \
    certbot certonly \
    -n \
    --agree-tos \
    -d $HOST,*.$HOST \
    --keep-until-expiring \
    --expand \
    --preferred-challenges dns \
    --dns-google \
    --dns-google-credentials /.secrets/certbot/$GOOGLE_DNS_CREDS_FILE_NAME \
    --dns-google-propagation-seconds 60

# Run `certbot --help all` to see a much more comprehensive help menu for all the above options.