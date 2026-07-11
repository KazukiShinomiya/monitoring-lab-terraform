# ビルドコンテキストは mcp/（親）を想定:
#   docker build -f prometheus-server/Dockerfile -t monitoring-lab-prometheus-mcp .
# 共通計装ヘルパー mcp/shared/telemetry.ts を src/ へ同梱する（016 / DRY）。
# 22.20.0 固定: node 22.23.x では OTLP exporter (grpc/http とも) の送出が
# サイレント不達となることを実測（2026-07 SC-002 検証）。詳細は specs/016 research.md
FROM node:22.20.0-alpine

WORKDIR /app
COPY prometheus-server/package*.json ./
RUN npm install
COPY prometheus-server/src/ ./src/
# 016: 共通計装ヘルパーを取り込む（index.ts は './telemetry.js' を import）
COPY shared/telemetry.ts ./src/telemetry.ts
COPY prometheus-server/tsconfig.json ./
RUN npm run build

CMD ["node", "dist/index.js"]
