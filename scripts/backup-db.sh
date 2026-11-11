#!/bin/bash
# ============================================================
# PostgreSQL 定时备份脚本
# 每天凌晨 02:00 执行，保留 7 天自动清理
#
# 用法：
#   直接运行：      bash backup-db.sh
#   定时任务：      crontab -e，添加下面一行
#                    0 2 * * * /path/to/backup-db.sh >> /var/log/backup-db.log 2>&1
#
# 环境变量（都有默认值，可在 crontab 或 shell 里 export 覆盖）：
#   PGHOST     数据库主机，默认 127.0.0.1
#   PGPORT     数据库端口，默认 5432
#   PGUSER     连接用户，默认 supabase
#   PGDATABASE 库名，默认 postgres
#   PGPASSWORD 连接密码；留空时 pg_dump 会转成交互式输入密码，
#              在 crontab 下没有终端，必须先 export 再跑
# ============================================================

set -euo pipefail

# ---------------------- 配置区 ----------------------
BACKUP_DIR="/data/backup"
RETENTION_DAYS=7

# 数据库连接（默认本机 docker 内的 supabase-db，按需替换）
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-supabase}"
PGDATABASE="${PGDATABASE:-postgres}"
# 密码优先从环境变量读，也可硬编码（不推荐）
PGPASSWORD="${PGPASSWORD:-}"
# ----------------------------------------------------

DATE_STR=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/postgres-${DATE_STR}.sql.gz"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== 开始数据库备份 =========="
echo "目标文件: ${BACKUP_FILE}"
echo "连接: ${PGUSER}@${PGHOST}:${PGPORT}/${PGDATABASE}"

mkdir -p "${BACKUP_DIR}"

# 检查 pg_dump 是否可用
if ! command -v pg_dump >/dev/null 2>&1; then
    echo "[错误] 未找到 pg_dump 命令，请先安装 PostgreSQL 客户端"
    echo "       CentOS: yum install postgresql"
    echo "       Ubuntu: apt install postgresql-client"
    exit 1
fi

# 如果密码没给，提示（或从 docker-compose .env 里读）
if [ -z "${PGPASSWORD}" ]; then
    echo "[警告] PGPASSWORD 未设置，pg_dump 会提示输入密码"
    echo "       建议在 crontab 之前 export PGPASSWORD='你的密码'"
fi

# 执行备份（自定义格式 + 压缩，体积小且可恢复单表）
if pg_dump \
    -h "${PGHOST}" \
    -p "${PGPORT}" \
    -U "${PGUSER}" \
    -d "${PGDATABASE}" \
    -Fc \
    -Z 9 \
    -f "${BACKUP_FILE}"; then
    echo "[成功] 备份完成: ${BACKUP_FILE} ($(du -h ${BACKUP_FILE} | cut -f1))"
else
    # 处于 if 的 else 分支，$? 保留的仍是刚失败的 pg_dump 的退出码
    echo "[失败] pg_dump 退出码 $?"
    exit 1
fi

# 清理超过 RETENTION_DAYS 天的旧备份
DELETED_COUNT=0
if [ -d "${BACKUP_DIR}" ]; then
    DELETED_COUNT=$(find "${BACKUP_DIR}" -name "postgres-*.sql.gz" -type f -mtime +${RETENTION_DAYS} -print -delete | wc -l)
fi
echo "[清理] 已删除超过 ${RETENTION_DAYS} 天的旧备份 ${DELETED_COUNT} 个"

# 列出当前保留的备份
echo "--- 当前备份列表 ---"
ls -lh "${BACKUP_DIR}" 2>/dev/null || true

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========== 备份流程结束 =========="
echo
