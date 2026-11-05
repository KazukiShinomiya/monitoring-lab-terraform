# Zabbix server の派生イメージ。外部スクリプト（check_switchbot.py）が使う Python を足す。
# 起動処理は公式の entrypoint に任せ、実行ユーザーも公式どおり 1997 に戻す。
ARG ZBX_IMAGE_TAG=alpine-8.0.0
FROM zabbix/zabbix-server-pgsql:${ZBX_IMAGE_TAG}

USER root
RUN apk add --no-cache python3 py3-requests
USER 1997
