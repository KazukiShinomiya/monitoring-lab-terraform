FROM node:22-alpine

RUN apk add --no-cache openssh-client

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY src/ ./src/
COPY tsconfig.json ./
RUN npm run build

RUN mkdir -p /root/.ssh && echo "StrictHostKeyChecking no" > /root/.ssh/config

CMD ["node", "dist/index.js"]
