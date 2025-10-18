@echo off
REM ==========================================
REM Container Environment Setup Script (Windows)
REM ==========================================
REM このスクリプトは、Terraform/Terragruntコンテナ環境を
REM セットアップします

echo [STEP] Terraform/Terragrunt開発環境を起動しています...

REM Docker Composeでコンテナを起動
docker-compose up -d

REM コンテナの起動を待つ
echo [INFO] コンテナの起動を待っています...
timeout /t 5 /nobreak >nul

REM Vaultの起動確認
echo [STEP] Vaultの起動確認...
docker exec monitoring-lab-vault-dev vault status

REM Terragruntバージョン確認
echo [STEP] Terragruntのバージョン確認...

echo [INFO] Terragrunt (includes Terraform):
docker exec monitoring-lab-terragrunt terragrunt --version
docker exec monitoring-lab-terragrunt terraform version

REM 完了メッセージ
echo.
echo [INFO] セットアップが完了しました！
echo.
echo ==================================
echo   使用方法
echo ==================================
echo.
echo Terragruntコマンド実行 (推奨):
echo   scripts\tg.bat ^<command^>
echo   例: scripts\tg.bat run-all init
echo.
echo Vaultへのアクセス:
echo   URL: http://localhost:8200
echo   Token: root
echo.
echo Terragruntコンテナシェルに入る:
echo   docker exec -it monitoring-lab-terragrunt sh
echo.
echo コンテナを停止:
echo   docker compose down
echo.
echo ==================================
