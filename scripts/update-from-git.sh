#!/bin/bash
# ============================================================
# 已部署服务器：更新到 GitHub 最新代码
# 代码有改动时（例如改了 bug、加了新功能），在已部署服务器上跑这条
#
# 用法：./scripts/update-from-git.sh
# 行为：先切到脚本上一级（项目根目录）再 git pull，当前分支由
#       git rev-parse --abbrev-ref HEAD 现取，不写死 main；
#       只重建 web 服务，db/rest/auth/kong 不重启，数据库数据不受影响
# ============================================================
set -euo pipefail

# 从项目根目录执行，保证 git pull 与 docker compose 读到的都是根目录的配置
cd "$(dirname "$0")/.."
echo "📥 git pull ..."
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🔁 重建前端 + 重启（后端不动，数据无损）"
docker compose -p school-platform up -d --build web

echo "✔ 前端已更新"
echo "   数据库数据未动"
