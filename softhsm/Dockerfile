FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y softhsm2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/softhsm/tokens && \
    chmod 777 /var/lib/softhsm/tokens

ARG SOFTHSM_PIN
RUN softhsm2-util --init-token --slot 0 --label "psibase production SoftHSM" --pin ${SOFTHSM_PIN} --so-pin ${SOFTHSM_PIN}

CMD ["sleep", "infinity"] 