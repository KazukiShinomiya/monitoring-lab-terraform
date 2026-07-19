# ビルドコンテキストは mcp/（親）を想定:
#   docker build -f terragrunt-server/Dockerfile -t monitoring-lab-terragrunt-mcp .
# 共通計装ヘルパー mcp/shared/telemetry.ts を src/ へ同梱する（016 / DRY）。
# 22.20.0 固定: node 22.23.x では OTLP exporter の送出がサイレント不達となる
# ことを実測（2026-07 SC-002 検証）。詳細は specs/016 research.md
FROM node:22.20.0-alpine

RUN apk add --no-cache openssh-client

WORKDIR /app
COPY terragrunt-server/package*.json ./
RUN npm ci
COPY terragrunt-server/src/ ./src/
# 016: 共通計装ヘルパーを取り込む（index.ts は './telemetry.js' を import）
COPY shared/telemetry.ts ./src/telemetry.ts
COPY terragrunt-server/tsconfig.json ./
RUN npm run build

# M-4: no → accept-new。known_hosts は実行時に readonly マウントされ、ホスト鍵の変化で接続が拒否される
RUN mkdir -p /root/.ssh && echo "StrictHostKeyChecking accept-new" > /root/.ssh/config

CMD ["node", "dist/index.js"]
