#!/bin/bash

DRY_RUN=""
if [ "$1" == "--dry-run" ]; then
    DRY_RUN="--dry-run"
fi

SCRIPT_DIR="$(dirname "$0")"

if [ "$DRY_RUN" == "" ]; then
    echo "RENEW CERT ATTEMPT"
else
    echo "[DRY RUN] RENEW CERT ATTEMPT"
fi
echo $(date +"%Y-%m-%d_%H-%M-%S")

docker pull ghcr.io/alexzorin/certbot-dns-multi:latest
docker tag ghcr.io/alexzorin/certbot-dns-multi:latest certbot

docker run --rm \
    --name certbot \
    -v "$SCRIPT_DIR/../iwantmyname-dns-multi.ini:/etc/letsencrypt/dns-multi.ini" \
    -v "$SCRIPT_DIR/../secrets/iwantmyname_username:/run/secrets/iwantmyname_username:ro" \
    -v "$SCRIPT_DIR/../secrets/iwantmyname_password:/run/secrets/iwantmyname_password:ro" \
    certbot renew \
    $DRY_RUN

if [ "$DRY_RUN" == "" ]; then
    $SCRIPT_DIR/reload-nginx.sh
fi