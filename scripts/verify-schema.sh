#!/bin/bash
# ============================================================
# 离线部署包自检：验证 docker/init 脚本能否还原出与运行库一致的结构
#
# 原理：建一个临时库 verify_init，把 docker/init 的 01~15 脚本从零跑一遍，
#       再与运行库 postgres 做「结构指纹」对比（表/字段/默认值/RLS/策略/函数/触发器/约束/索引）。
#       对比前会剔除 schema_migrations（GoTrue 自建表）及无信息的节标题行，
#       避免行数位移造成假差异。
#
# 用法：bash scripts/verify-schema.sh
# 预期：除 schema_migrations（GoTrue 自建表）外完全一致；其余差异说明运行库与脚本不同步。
#      脚本结尾会输出 PASS/FAIL 结论，可直接用于交付前自检。
# 注意：脚本会创建/删除临时数据库 verify_init，不影响 postgres 库的数据。
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INIT_DIR="$PROJECT_DIR/docker/init"
DB_CTN="supabase-db"
LIVE_DB="postgres"
TEST_DB="verify_init"
FP=/tmp/_schema_fingerprint.sql

if ! docker exec "$DB_CTN" true 2>/dev/null; then
  echo "错误：容器 $DB_CTN 未运行，请先启动 Docker Desktop 并执行 docker compose -p school-platform up -d"
  exit 1
fi

echo "===== 0. 准备结构指纹 SQL ====="
cat > "$FP" <<'SQL'
\echo '### TABLES'
SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY 1;
\echo '### COLUMNS'
SELECT table_name||'.'||column_name||' : '||data_type||' null='||is_nullable||' def='||COALESCE(column_default,'-')
FROM information_schema.columns WHERE table_schema='public' ORDER BY 1;
\echo '### RLS_ENABLED'
SELECT relname||' rls='||relrowsecurity FROM pg_class
WHERE relnamespace='public'::regnamespace AND relkind='r' ORDER BY 1;
\echo '### POLICIES'
SELECT tablename||'.'||policyname||' cmd='||cmd FROM pg_policies WHERE schemaname='public' ORDER BY 1;
\echo '### FUNCTIONS'
SELECT p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind='f' ORDER BY 1;
\echo '### TRIGGERS'
SELECT event_object_table||'.'||trigger_name||' '||action_timing||' '||event_manipulation
FROM information_schema.triggers WHERE trigger_schema='public' ORDER BY 1;
\echo '### CONSTRAINTS'
SELECT conrelid::regclass||'.'||conname||' '||contype
FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY 1;
\echo '### INDEXES'
SELECT tablename||'.'||indexname FROM pg_indexes WHERE schemaname='public' ORDER BY 1;
SQL

fp() { docker exec -i "$DB_CTN" psql -U supabase -d "$1" -At -F'|' -f - < "$FP" 2>&1; }

echo "===== 1. 重建临时库 ====="
docker exec -i "$DB_CTN" psql -U supabase -d postgres -qc "DROP DATABASE IF EXISTS $TEST_DB;" >/dev/null 2>&1
docker exec "$DB_CTN" pg_dump -U supabase -d postgres --schema=auth --schema-only --no-owner --no-privileges > /tmp/_auth_only.sql 2>/tmp/_auth_err.txt
if [ $? -ne 0 ]; then echo "  auth schema 导出失败："; head -3 /tmp/_auth_err.txt; exit 1; fi
docker exec -i "$DB_CTN" psql -U supabase -d postgres -qc "CREATE DATABASE $TEST_DB;" >/dev/null 2>&1
docker exec -i "$DB_CTN" psql -U supabase -d "$TEST_DB" -q < /tmp/_auth_only.sql >/dev/null 2>&1
docker exec -i "$DB_CTN" psql -U supabase -d "$TEST_DB" -qc "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null 2>&1
echo "  临时库 $TEST_DB 已就绪（含 auth schema 模拟）"

echo "===== 2. 按文件名顺序执行 docker/init 全部脚本 ====="
FAIL=0
for f in "$INIT_DIR"/*.sql; do
  base=$(basename "$f")
  case "$base" in
    [0-9][0-9]_*) ;;
    *) echo "  [跳过] $base"; continue ;;
  esac
  docker exec -i "$DB_CTN" psql -U supabase -d "$TEST_DB" -v ON_ERROR_STOP=1 -q -f - < "$f" > "/tmp/_log_$base.txt" 2>&1
  if [ $? -ne 0 ]; then
    FAIL=1; echo "  [失败] $base"
    grep -iE '^psql|ERROR' "/tmp/_log_$base.txt" | head -3
  else
    echo "  [成功] $base"
  fi
done
[ $FAIL -eq 1 ] && echo "  注意：存在执行失败的脚本（见上）"

echo "===== 3. 与运行库对比 ====="
fp "$LIVE_DB" > /tmp/_fp_live.txt
fp "$TEST_DB" > /tmp/_fp_fresh.txt
# 归一化：剔除 GoTrue 自建的 schema_migrations 相关行，
# 以及 '### SECTION' 节标题行（本身不含结构信息，仅因行数位移产生假差异）
normalize() { grep -v 'schema_migrations' "$1" | grep -v '^### '; }
normalize /tmp/_fp_live.txt  > /tmp/_fp_live_n.txt
normalize /tmp/_fp_fresh.txt > /tmp/_fp_fresh_n.txt
diff /tmp/_fp_live_n.txt /tmp/_fp_fresh_n.txt > /tmp/_fp_diff.txt
if [ -s /tmp/_fp_diff.txt ]; then
  echo "  发现差异（< 运行库 / > 脚本重建）："
  echo "  ----------------------------------------------------------"
  cat /tmp/_fp_diff.txt | sed 's/^/  /'
  echo "  ----------------------------------------------------------"
  echo "  以上差异说明运行库与 docker/init 脚本不同步，需要补执行对应脚本。"
  echo "  **********************************************************"
  echo "  *  结论：FAIL —— 脚本无法还原当前运行库结构               *"
  echo "  **********************************************************"
  VERDICT=1
else
  DIFF_N=$(diff /tmp/_fp_live.txt /tmp/_fp_fresh.txt | grep -c '^[<>]' || true)
  echo "  结构指纹一致（已忽略 $DIFF_N 行 schema_migrations / 节标题噪声）。"
  echo "  **********************************************************"
  echo "  *  结论：PASS —— 脚本可 100% 还原当前运行库结构           *"
  echo "  **********************************************************"
  VERDICT=0
fi

echo "===== 4. 清理临时库 ====="
docker exec -i "$DB_CTN" psql -U supabase -d postgres -qc "DROP DATABASE IF EXISTS $TEST_DB;" >/dev/null 2>&1
echo "  已删除 $TEST_DB"

[ "${FAIL:-0}" -eq 1 ] && exit 1
exit "${VERDICT:-1}"
