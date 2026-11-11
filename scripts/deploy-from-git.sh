#!/bin/bash
# ============================================================
# 新服务器：从 GitHub 一键部署（代码走 git clone，数据走 pg_dump）
#
# 使用前：
#   1) 确保新服务器已装 Docker Desktop / docker + docker-compose
#   2) 准备好 pg_dump 出来的 database.sql（从旧服务器 scripts/backup.sh 里拿）
#   3) 准备好 .env（从旧服务器拷，或用 .env.example + 自己改密钥）
#
# 用法：
#   GIT_URL=https://github.com/你的用户名/school-platform.git \
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/你的用户名/school-platform/main/scripts/deploy-from-git.sh)"
# 或直接：
#   git clone https://github.com/你的用户名/school-platform.git /opt/school-platform
#   cd /opt/school-platform && bash scripts/deploy-from-git.sh
#
# 可覆盖的环境变量：
#   GIT_URL    仓库地址；未设置且目标目录不是 git 仓库时直接报错退出
#   CLONE_DIR  代码落地目录，默认 /opt/school-platform
#   BRANCH     分支名，默认 main，clone 与 pull 都用它
# ============================================================
set -euo pipefail

GIT_URL="${GIT_URL:-}"
CLONE_DIR="${CLONE_DIR:-/opt/school-platform}"
BRANCH="${BRANCH:-main}"

if [ ! -d "$CLONE_DIR/.git" ]; then
  if [ -z "$GIT_URL" ]; then
    echo "❌ 请先指定 GIT_URL 或手动 git clone"
    echo "   bash scripts/deploy-from-git.sh  # 必须已在项目目录"
    exit 1
  fi
  echo "📥 clone 代码..."
  git clone -b "$BRANCH" "$GIT_URL" "$CLONE_DIR"
  cd "$CLONE_DIR"
else
  cd "$CLONE_DIR"
  echo "📥 pull 最新代码..."
  git pull origin "$BRANCH"
fi

chmod +x scripts/*.sh

# ---- .env ----
if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    echo "⚠ .env 不存在，从 .env.example 复制"
    cp .env.example .env
    echo "👉 请编辑 .env 改好密钥后再跑："
    echo "   cd $CLONE_DIR"
    echo "   vi .env"
    echo "   docker compose -p school-platform up -d --build"
    exit 0
  fi
  echo "❌ 找不到 .env 也找不到 .env.example"
  exit 1
fi

# ---- 起后端 ----
echo "=============================================="
echo "🚀 启动后端（db / rest / auth / kong）"
echo "=============================================="
docker compose -p school-platform up -d db rest auth kong

echo "⏳ 等待 DB ready..."
for attempt in $(seq 1 30); do
  if docker exec supabase-db pg_isready -U supabase -d postgres 2>/dev/null | grep -q "accepting"; then
    echo "✔ DB ready"
    break
  fi
  sleep 2
done

# ---- 数据（可选导入） ----
if [ -f "database.sql" ]; then
  echo "=============================================="
  echo "📦 导入 database.sql"
  echo "=============================================="
  docker exec -i supabase-db psql -U supabase -d postgres < database.sql
  echo "✔ 数据导入完成"
else
  echo "ℹ 未找到 database.sql —— 跑空库（之后可以跑前端的 Excel 导入造种子数据）"
  echo "  旧服务器上导出：docker exec supabase-db pg_dump -U supabase -d postgres > database.sql"
fi

# ---- 起前端 ----
echo "=============================================="
echo "🌐 启动前端 + 重新 build"
echo "=============================================="
docker compose -p school-platform up -d --build web

echo ""
echo "=============================================="
echo "✔ 全部搞定"
echo "   前端：http://$(hostname -I | awk '{print $1}'):8080"
echo "   后端：http://$(hostname -I | awk '{print $1}'):8000"
echo "=============================================="
