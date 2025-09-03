#!/bin/bash
set -e

if [ ! -d "/root/psibase/db" ] || [ -z "$(ls -A /root/psibase/db)" ]; then
    echo "First run detected, initializing node"
    exec psinode db \
        -p "${PRODUCER_NAME}" \
        -o "${HOST}" \
        --p2p \
        -l 8090 \
        --database-cache-size="${DB_CACHE_SIZE}" \
        --pkcs11-module=/softhsm-lib/libsofthsm2.so
else
    echo "Existing data found, resuming node"
    exec psinode db \
        -p "${PRODUCER_NAME}" \
        -o "${HOST}" \
        --p2p \
        -l 8090 \
        --database-cache-size="${DB_CACHE_SIZE}"
fi