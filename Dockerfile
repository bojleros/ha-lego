FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache lego jq

COPY rootfs/ /

RUN chmod +x \
      /usr/local/bin/lego-renew.sh \
      /etc/cont-init.d/10-setup.sh \
      /etc/services.d/cron/run
