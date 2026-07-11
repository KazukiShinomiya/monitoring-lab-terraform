# ビルドコンテキストは mcp/（親）を想定:
#   docker build -f docker-server/Dockerfile -t monitoring-lab-docker-mcp .
# 共通計装ヘルパー mcp/shared/telemetry.ts を src/ へ同梱する（016 / DRY）。
# 22.20.0 固定: node 22.23.x では OTLP exporter の送出がサイレント不達となる
# ことを実測（2026-07 SC-002 検証）。詳細は specs/016 research.md
FROM node:22.20.0-alpine

RUN apk add --no-cache docker-cli openssh-client

WORKDIR /app
COPY docker-server/package*.json ./
RUN npm ci
COPY docker-server/src/ ./src/
# 016: 共通計装ヘルパーを取り込む（index.ts は './telemetry.js' を import）
COPY shared/telemetry.ts ./src/telemetry.ts
COPY docker-server/tsconfig.json ./
RUN npm run build

RUN mkdir -p /root/.ssh && echo "StrictHostKeyChecking no" > /root/.ssh/config

CMD ["node", "dist/index.js"]
