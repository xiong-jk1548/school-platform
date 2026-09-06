# 一键备份（Windows PowerShell 版）
# 在部署过的服务器上执行：powershell -ExecutionPolicy Bypass -File scripts/backup.ps1
$ErrorActionPreference = "Stop"

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$out   = "deploy-backup-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "[1/3] 导出数据库..." -ForegroundColor Cyan
docker exec supabase-db pg_dump -U supabase -d postgres --no-owner --no-privileges --clean --if-exists > "$out\database.sql"
Write-Host "    OK database.sql" -ForegroundColor Green

Write-Host "[2/3] 打包项目文件..." -ForegroundColor Cyan
Copy-Item -Recurse -Force deploy, docker, docker-compose.yml, Dockerfile, .env, .env.example $out\ -ErrorAction SilentlyContinue

Write-Host "[3/3] 压缩..." -ForegroundColor Cyan
Compress-Archive -Path "$out\*" -DestinationPath "$out.zip"
Remove-Item -Recurse -Force $out

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "✔ 备份完成：$out.zip" -ForegroundColor Green
Write-Host "拷到新服务器后："
Write-Host "  Expand-Archive $out.zip"
Write-Host "  cd $out"
Write-Host "  bash scripts/restore.sh   (Git Bash / WSL)"
Write-Host "==============================================" -ForegroundColor Green
