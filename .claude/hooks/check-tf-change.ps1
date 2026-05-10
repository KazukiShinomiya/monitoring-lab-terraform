# PostToolUse hook: .tf/.hcl ファイル変更時に terragrunt plan 実行を促す
try {
    $json = [Console]::In.ReadToEnd()
    $data = $json | ConvertFrom-Json -ErrorAction Stop
    $filePath = $data.tool_input.file_path
    if ($filePath -match '\.(tf|hcl)$') {
        $fileName = Split-Path $filePath -Leaf
        Write-Host ""
        Write-Host "  Terraform/HCLファイルを変更しました: $fileName" -ForegroundColor Yellow
        Write-Host "  terragrunt plan で差分を確認してください。" -ForegroundColor Cyan
        Write-Host ""
    }
} catch {
    # JSON解析エラーは無視（非TFファイルの変更など）
}
