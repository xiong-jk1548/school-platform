@echo off
title 智慧校园管理平台 - 一键停止
echo.
echo =============================================================
echo           智慧校园管理平台 - 一键停止
echo =============================================================
echo.

cd /d "%~dp0"

echo [1/2] 停止所有容器 ...
docker compose -p school-platform down

echo.
echo [2/2] 容器已停止。（Docker Desktop 仍在运行，如需退出请手动关闭）
echo.
pause
