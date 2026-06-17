# ビルドコンテキストは mcp/（親）を想定:
#   docker build -f prometheus-server/Dockerfile -t monitoring-lab-prometheus-mcp .
# 共通計装ヘルパー mcp/shared/telemetry.ts を src/ へ同梱する（016 / DRY）。
FROM node:22-alpine

WORKDIR /app
COPY prometheus-server/package*.json ./
RUN npm install
COPY prometheus-server/src/ ./src/
# 016: 共通計装ヘルパーを取り込む（index.ts は './telemetry.js' を import）
COPY shared/telemetry.ts ./src/telemetry.ts
COPY prometheus-server/tsconfig.json ./
RUN npm run build

CMD ["node", "dist/index.js"]
