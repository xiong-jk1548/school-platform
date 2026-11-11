﻿# 一键备份（Windows PowerShell 版）
# 在部署过的服务器上执行：powershell -ExecutionPolicy Bypass -File scripts/backup.ps1
#
# .SYNOPSIS
#   导出 supabase-db 全库 + 打包项目配置，压缩成一个 zip 便于搬到新服务器。
# .NOTES
#   产物：deploy-backup-yyyyMMdd-HHmm.zip（中间目录打包后即删除）
#   $ErrorActionPreference = "Stop" 下，Copy-Item 用 -ErrorAction SilentlyContinue
#   让 .env 这类可选文件缺失时不中断；pg_dump 失败则会直接终止脚本。
$ErrorActionPreference = "Stop"

$Stamp     = Get-Date -Format "yyyyMMdd-HHmm"
$BackupDir = "deploy-backup-$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

Write-Host "[1/3] 导出数据库..." -ForegroundColor Cyan
docker exec supabase-db pg_dump -U supabase -d postgres --no-owner --no-privileges --clean --if-exists > "$BackupDir\database.sql"
Write-Host "    OK database.sql" -ForegroundColor Green

Write-Host "[2/3] 打包项目文件..." -ForegroundColor Cyan
Copy-Item -Recurse -Force deploy, docker, docker-compose.yml, Dockerfile, .env, .env.example $BackupDir\ -ErrorAction SilentlyContinue

Write-Host "[3/3] 压缩..." -ForegroundColor Cyan
Compress-Archive -Path "$BackupDir\*" -DestinationPath "$BackupDir.zip"
Remove-Item -Recurse -Force $BackupDir

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "✔ 备份完成：$BackupDir.zip" -ForegroundColor Green
Write-Host "拷到新服务器后："
Write-Host "  Expand-Archive $BackupDir.zip"
Write-Host "  cd $BackupDir"
Write-Host "  bash scripts/restore.sh   (Git Bash / WSL)"
Write-Host "==============================================" -ForegroundColor Green
