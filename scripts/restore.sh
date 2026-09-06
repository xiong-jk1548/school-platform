#!/bin/bash
# ============================================================
# 一键恢复：新项目里把 .tar.gz 解开后跑
# 用法：
#   tar -xzf deploy-backup-XXXXXX.tar.gz
#   cd deploy-backup-XXXXXX
#   ./restore.sh
# ============================================================
set -euo pipefail

echo "=============================================="
echo "  1. 启动 Supabase 后端（不重建数据库）"
echo "=============================================="
# 先起 db / rest / auth / kong（不包含 web —— 前端可能要重新 build）
docker compose up -d db rest auth kong

# 等 db 就绪
echo "等待数据库就绪..."
for i in $(seq 1 30); do
  if docker exec supabase-db pg_isready -U supabase -d postgres 2>/dev/null | grep -q "accepting connections"; then
    echo "✔ DB ready"
    break
  fi
  sleep 2
done

echo ""
echo "=============================================="
echo "  2. 导入数据（覆盖现有表）"
echo "=============================================="
if [ -f database.sql ]; then
  echo "正在导入 database.sql..."
  docker exec -i supabase-db psql -U supabase -d postgres < database.sql
  echo "✔ 数据导入完成"
else
  echo "⚠ 找不到 database.sql，跳过数据导入"
fi

echo ""
echo "=============================================="
echo "  3. 启动前端（用当前 .env 重新 build）"
echo "=============================================="
docker compose up -d --build web

echo ""
echo "=============================================="
echo "  全部搞定！"
echo "  前端：http://服务器IP:8080"
echo "  后端：http://服务器IP:8000"
echo "=============================================="
