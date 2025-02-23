#!/bin/bash

# Used when initially creating the tls certificate with certbot. Only used during initial setup,
#   after which the cert only needs to be renewed using `renew-cert.sh` (from a cronjob).

set -a
source /home/ubuntu/stack-deployment-config.env

docker pull certbot/dns-google:latest
docker tag certbot/dns-google:latest certbot
docker run -it --rm \
    --name certbot \
    -v /home/ubuntu/letsencrypt/certs:/etc/letsencrypt \
    -v /home/ubuntu/$GOOGLE_DNS_CREDS_FILE_NAME:/.secrets/certbot/$GOOGLE_DNS_CREDS_FILE_NAME \
    certbot certonly \
    -n \
    --agree-tos \
    -d $NGINX_HOST,*.$NGINX_HOST \
    --keep-until-expiring \
    --expand \
    --preferred-challenges dns \
    --dns-google \
    --dns-google-credentials /.secrets/certbot/$GOOGLE_DNS_CREDS_FILE_NAME \
    --dns-google-propagation-seconds 60

# Run `certbot --help all` to see a much more comprehensive help menu for all the above options.

# certonly          Obtain or renew a certificate, but do not install it
# --test-cert       Obtain a test certificate from a staging server
# --dry-run         Test "renew" or "certonly" without saving any certificates
