#!/bin/bash
# ============================================================
# 已部署服务器：更新到 GitHub 最新代码
# 代码有改动时（例如改了 bug、加了新功能），在已部署服务器上跑这条
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
echo "📥 git pull ..."
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🔁 重建前端 + 重启（后端不动，数据无损）"
docker compose -p school-platform up -d --build web

echo "✔ 前端已更新"
echo "   数据库数据未动"
