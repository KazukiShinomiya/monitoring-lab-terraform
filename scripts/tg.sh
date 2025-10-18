#!/bin/bash
# ==========================================
# Terragrunt Container Wrapper Script
# ==========================================
# このスクリプトは、コンテナ内でTerragruntコマンドを実行します
# 使用方法: ./scripts/tg.sh <terragrunt-command>
# 例: ./scripts/tg.sh init
#     ./scripts/tg.sh plan
#     ./scripts/tg.sh run-all apply

# コンテナ名
CONTAINER_NAME="monitoring-lab-terragrunt"

# コンテナが起動しているか確認
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "Terragruntコンテナを起動しています..."
    docker-compose up -d terragrunt

    # コンテナの起動を待つ
    sleep 2
fi

# Terragruntコマンドを実行
docker exec -it "$CONTAINER_NAME" terragrunt "$@"
