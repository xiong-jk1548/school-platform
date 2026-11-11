@echo off
title 智慧校园管理平台 - 一键启动
echo.
echo =============================================================
echo           智慧校园管理平台 - 一键启动
echo =============================================================
echo.

echo [1/4] 检查 Docker Desktop ...
docker info >nul 2>&1
if not errorlevel 1 goto docker_ready
echo [!] Docker 未运行，尝试启动 ...
if not exist "C:\Program Files\Docker\Docker\Docker Desktop.exe" goto no_docker
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
echo     等待鲸鱼图标变绿（约 30-60 秒）...
set /a waited=0
:wait_docker
docker info >nul 2>&1
if not errorlevel 1 goto docker_ready
if %waited% geq 60 goto docker_timeout
set /a waited+=5
timeout /t 5 /nobreak >nul
goto wait_docker

:docker_timeout
echo [X] Docker 启动超时，请手动打开 Docker Desktop 后重试
pause
exit /b 1

:no_docker
echo [X] 找不到 Docker Desktop.exe，请手动打开 Docker Desktop 后重试
pause
exit /b 1

:docker_ready
echo     Docker 就绪 [OK]

cd /d "%~dp0"

if exist .env goto env_ok
echo [!] .env 不存在，从 .env.example 复制一份
copy .env.example .env >nul
echo     请编辑 .env 填入正确的密钥后重新运行
pause
exit /b 1
:env_ok

echo.
echo [2/4] 启动 Docker 容器 ...
docker compose -p school-platform up -d

echo.
echo [3/4] 等待数据库就绪 ...
set /a tries=0
:wait_db
docker exec supabase-db pg_isready -U supabase -d postgres >nul 2>&1
if not errorlevel 1 goto db_ready
set /a tries+=1
if %tries% lss 20 goto wait_db_short
echo [!] DB 启动较慢，继续等待 ...
:wait_db_short
timeout /t 2 /nobreak >nul
goto wait_db

:db_ready
echo     数据库就绪 [OK]

echo.
echo [4/4] 容器状态：
docker compose -p school-platform ps

echo.
set LOCAL_IP=127.0.0.1
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    for /f "tokens=1" %%b in ("%%a") do (
        if not "%%b"=="127.0.0.1" set LOCAL_IP=%%b
    )
)

echo.
echo -------------------------------------------------------------
echo   本机访问：http://127.0.0.1:8080
echo   局域网：  http://%LOCAL_IP%:8080
echo   API 端口：http://127.0.0.1:8000
echo.
echo   测试账号（统一密码 123456）：
echo     13800000001  admin@demo.com           sys_admin
echo     13800000002  school_admin@demo.com    school_admin
echo     13800000003  teacher@demo.com         teacher
echo     13800000004  teacher2@demo.com        teacher
echo -------------------------------------------------------------
echo.
echo   按任意键打开浏览器 ...
pause >nul
start "" "http://127.0.0.1:8080"
