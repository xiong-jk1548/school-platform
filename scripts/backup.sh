#!/bin/bash
# ============================================================
# 一键备份：导出数据库 + 打包项目
# 用法：在部署过的服务器上跑
#   chmod +x scripts/backup.sh
#   ./scripts/backup.sh
# 产物：deploy-backup-YYYYMMDD-HHMM.tar.gz
#
# 前置条件：容器 supabase-db 处于运行状态（数据库导出走 docker exec，
#           不需要本机装 psql 客户端）
# 注意：脚本整体带 set -e，所有 cp 后面都接了 `2>/dev/null || true`，
#       让 deploy/、.env 这类可选文件缺失时不中断打包
# ============================================================
set -euo pipefail

BACKUP_STAMP=$(date +%Y%m%d-%H%M)
OUT_DIR="deploy-backup-${BACKUP_STAMP}"
mkdir -p "${OUT_DIR}"

echo "[1/3] 导出 PostgreSQL 数据（含 auth.users + 所有业务表）..."
docker exec supabase-db pg_dump \
  -U supabase \
  -d postgres \
  --no-owner \
  --no-privileges \
  --clean \
  --if-exists \
  > "${OUT_DIR}/database.sql"
echo "    ✔ database.sql ($(du -h ${OUT_DIR}/database.sql | cut -f1))"

echo "[2/3] 打包项目关键文件..."
cp -r deploy/               "${OUT_DIR}/" 2>/dev/null || true
cp -r docker/               "${OUT_DIR}/" 2>/dev/null || true
cp    docker-compose.yml    "${OUT_DIR}/" 2>/dev/null || true
cp    Dockerfile            "${OUT_DIR}/" 2>/dev/null || true
cp    .env                  "${OUT_DIR}/" 2>/dev/null || cp .env.example "${OUT_DIR}/.env"
cp    .env.example          "${OUT_DIR}/" 2>/dev/null || true
cp    deploy/nginx.conf     "${OUT_DIR}/deploy/" 2>/dev/null || true
# 保存前端当前 image 标签（方便新服务器 build 时对上）
docker images school-platform-web --format "{{.Tag}}" > "${OUT_DIR}/web-image-tag.txt" 2>/dev/null || echo "latest" > "${OUT_DIR}/web-image-tag.txt"

echo "[3/3] 打包..."
tar -czf "${OUT_DIR}.tar.gz" "${OUT_DIR}"
rm -rf "${OUT_DIR}"

echo ""
echo "=============================================="
echo "✔ 备份完成：${OUT_DIR}.tar.gz"
echo "大小：$(du -h ${OUT_DIR}.tar.gz | cut -f1)"
echo ""
echo "把这个 .tar.gz 拷到新服务器，然后："
echo "  tar -xzf ${OUT_DIR}.tar.gz"
echo "  cd ${OUT_DIR}"
echo "  ./scripts/restore.sh"
echo "=============================================="
