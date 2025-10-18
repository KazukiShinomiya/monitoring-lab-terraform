@echo off
REM ==========================================
REM Terragrunt Container Wrapper Script (Windows)
REM ==========================================
REM このスクリプトは、コンテナ内でTerragruntコマンドを実行します
REM 使用方法: scripts\tg.bat <terragrunt-command>
REM 例: scripts\tg.bat init
REM     scripts\tg.bat plan
REM     scripts\tg.bat run-all apply

SET CONTAINER_NAME=monitoring-lab-terragrunt

REM コンテナが起動しているか確認
docker ps | findstr /C:"%CONTAINER_NAME%" >nul
IF %ERRORLEVEL% NEQ 0 (
    echo Terragruntコンテナを起動しています...
    docker-compose up -d terragrunt
    timeout /t 2 /nobreak >nul
)

REM Terragruntコマンドを実行
docker exec -it %CONTAINER_NAME% terragrunt %*
