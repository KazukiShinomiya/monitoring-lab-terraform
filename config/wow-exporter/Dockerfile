FROM python:3.12-alpine

RUN apk add --no-cache rsync openssh-client dcron bash

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY exporter/ ./exporter/
COPY scripts/sync-logs.sh ./scripts/sync-logs.sh
COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x ./scripts/sync-logs.sh ./docker-entrypoint.sh

ENV LOG_DIR=/data/wow-logs \
    GEOIP_DB=/data/geoip/GeoLite2-Country.mmdb \
    GEOIP_ASN_DB=/data/geoip/GeoLite2-ASN.mmdb \
    EXPORTER_PORT=9200 \
    SCRAPE_INTERVAL=300 \
    TOP_N=20

EXPOSE 9200

ENTRYPOINT ["/app/docker-entrypoint.sh"]
