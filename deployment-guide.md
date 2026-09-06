# 多校学生积分管理平台 · 部署操作文档

> 适用环境：教育局内网 Linux 服务器（CentOS 7+ / Ubuntu 20.04+）
> 架构：单台服务器 Docker Compose 部署 Supabase 自托管后端 + Nginx 前端静态托管
> 前端代码：`frontend/` 目录，Vue3 + Vite，构建产物 `dist/`

---

## 目录

1. [服务器准备](#1-服务器准备)
2. [后端部署（Supabase）](#2-后端部署supabase)
3. [首次数据库初始化](#3-首次数据库初始化)
4. [创建 sys_admin 初始账号](#4-创建-sys_admin-初始账号)
5. [前端部署](#5-前端部署)
6. [验证登录](#6-验证登录)
7. [定时备份配置](#7-定时备份配置)
8. [升级流程](#8-升级流程)
9. [常见问题](#9-常见问题)

---

## 1. 服务器准备

### 1.1 安装 Docker 和 Docker Compose

**CentOS 7 / 8 / 9：**

```bash
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

**Ubuntu 20.04 / 22.04：**

```bash
apt update && apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

验证：

```bash
docker --version        # 需 >= 24.0
docker compose version  # 需 >= 2.20
```

### 1.2 准备 Nginx（可选，如果你不装 docker 版的 nginx）

```bash
# CentOS
yum install -y nginx
systemctl enable nginx

# Ubuntu
apt install -y nginx
```

---

## 2. 后端部署（Supabase）

### 2.1 上传配置

在本地把整个 `docker/` 目录拷到服务器：

```bash
# 本地执行（PowerShell / Git Bash 都可用）
scp -r docker/ root@服务器IP:/opt/supabase/
```

### 2.2 修改密钥

```bash
cd /opt/supabase/docker
cp .env.example .env
vi .env
```

**必须替换的字段：**

| 字段 | 生成命令 |
|---|---|
| `POSTGRES_PASSWORD` | 至少 16 位强密码 |
| `JWT_SECRET` | `openssl rand -base64 48` |
| `SUPABASE_ANON_KEY` | `openssl rand -base64 32` |
| `SUPABASE_SERVICE_ROLE_KEY` | `openssl rand -base64 64` |

`SITE_URL` 改成内网访问地址，例如：

```
SITE_URL=http://192.168.1.100:8000
```

### 2.3 启动服务

```bash
cd /opt/supabase/docker
docker compose up -d
```

等约 30 秒让数据库初始化，然后查看状态：

```bash
docker compose ps
docker compose logs -f db     # 看数据库日志
docker compose logs -f kong   # 看网关日志
```

所有容器状态应为 `Up (healthy)` 或 `Up`。

---

## 3. 首次数据库初始化

### 方式 A：命令行 psql（推荐）

```bash
# 执行 V1 初始化
docker exec -i supabase-db psql -U supabase -d postgres < docker/init/01_schema.sql

# 执行 V2 增量
docker exec -i supabase-db psql -U supabase -d postgres < docker/init/02_features_v2.sql
```

### 方式 B：Supabase Dashboard

浏览器打开 Kong 端口（因为没部署 Dashboard，可以直接用 psql 方式 A），或在 postgres 容器内进入 psql 手动粘贴执行。

### 验证表是否创建成功

```bash
docker exec -it supabase-db psql -U supabase -d postgres -c "\dt public.*"
```

应该能看到：`schools, profiles, classes, students, score_log, homework_subjects, homework_records, borrow_items, borrow_records`

---

## 4. 创建 sys_admin 初始账号

触发器会在 `auth.users` 插入新用户时自动在 `profiles` 里创建 `role='teacher'` 的记录，所以我们需要：

### 步骤 1：在 auth.users 里插入超级管理员（用 gotrue 的 admin API 或 psql）

**最简单方式 —— 直接 psql：**

```bash
docker exec -it supabase-db psql -U supabase -d postgres
```

```sql
-- 生成密码的 bcrypt hash（或者用 gotrue API，这里直接用 psql 插入）
-- 密码：Admin@123  （部署后立即改掉）
INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
) VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'admin@example.com',
    '$2a$10$Q7dH8qRZKvQIS.hXOQxz/.t2yVq8LmQdPq7wJ5s3KxXZ7r8K3M5bTK',  -- bcrypt("Admin@123")
    now(), now(), now(),
    '{"provider": "email", "providers": ["email"]}',
    '{"real_name": "系统管理员"}'
);
```

> 上面 bcrypt hash 对应的明文是 `Admin@123`，首次登录后请立即在前端修改密码。
> 或者用 gotrue admin API 创建（更标准）：
> `curl -X POST http://127.0.0.1:8000/auth/v1/admin/users?access-token=$SUPABASE_SERVICE_ROLE_KEY ...`

### 步骤 2：把 profiles 里自动创建的 role 改成 sys_admin

```sql
UPDATE public.profiles
SET role = 'sys_admin', real_name = '系统管理员'
WHERE email = 'admin@example.com';
```

### 步骤 3：验证

```sql
SELECT id, email, role, real_name FROM public.profiles;
```

---

## 5. 前端部署

### 5.1 本地构建

```bash
cd frontend
npm install
# 复制并编辑 .env.local，填入：
#   VITE_SUPABASE_URL=http://服务器IP:8000
#   VITE_SUPABASE_ANON_KEY=你的 anon key
copy .env.example .env.local
npm run build
```

构建产物在 `frontend/dist/` 目录。

### 5.2 上传到服务器

```bash
# 本地执行
scp -r frontend/dist/* root@服务器IP:/var/www/frontend/
```

如果目录不存在，先在服务器上：

```bash
mkdir -p /var/www/frontend
```

### 5.3 配置 Nginx

把 `nginx/nginx.conf` 拷到服务器：

```bash
scp nginx/nginx.conf root@服务器IP:/etc/nginx/conf.d/app.conf
# 或
scp nginx/nginx.conf root@服务器IP:/etc/nginx/nginx.conf
```

校验并重载：

```bash
nginx -t
nginx -s reload
```

### 5.4 验证

浏览器打开 `http://服务器IP/`，应看到登录页。

---

## 6. 验证登录

| 步骤 | 操作 | 预期 |
|---|---|---|
| 1 | 打开浏览器访问 `http://服务器IP/` | 显示登录页 |
| 2 | 用 sys_admin 账号 `admin@example.com / Admin@123` 登录 | 进入教育局首页，菜单：学校管理、积分配置、全区统计 |
| 3 | 在"学校管理"新增一所测试学校 | 创建成功 |
| 4 | 在"积分配置"新增一条积分规则 | 保存成功 |
| 5 | 退出后，在数据库 profiles 里手动创建一个 school_admin（role 字段） | 切换角色验证隔离 |
| 6 | 用 school_admin 登录 | 只能看到本校数据 |
| 7 | 用 teacher 登录 | 只能看到本班学生和作业 |

---

## 7. 定时备份配置

### 7.1 安装 PostgreSQL 客户端（服务器上）

```bash
# CentOS
yum install -y postgresql

# Ubuntu
apt install -y postgresql-client
```

### 7.2 设置密码

编辑 crontab：

```bash
crontab -e
```

在顶部加一行 export，然后加定时任务：

```
PGPASSWORD=你的POSTGRES_PASSWORD
0 2 * * * /opt/supabase/scripts/backup-db.sh >> /var/log/backup-db.log 2>&1
```

### 7.3 手动测试

```bash
bash scripts/backup-db.sh
# 看 /data/backup/ 下是否生成 postgres-YYYYMMDD_HHMMSS.sql.gz
```

### 7.4 恢复备份（如果需要）

```bash
pg_restore -h 127.0.0.1 -p 5432 -U supabase -d postgres --clean --if-exists postgres-20260905_020000.sql.gz
```

---

## 8. 升级流程

### 前端升级

```bash
# 本地
cd frontend
git pull                    # 或拉取新代码
npm install                 # 如果 package.json 有新增依赖
npm run build               # 生成新的 dist/

# 上传到服务器
rsync -avz --delete frontend/dist/ root@服务器IP:/var/www/frontend/

# Nginx 不需要 reload（HTML 有 no-cache，浏览器刷新即生效）
```

### 数据库升级

每次数据库结构变更，必须写增量 SQL 文件（如 `docker/init/03_new_feature.sql`），**禁止直接改生产表**：

```bash
# 在服务器上执行
docker exec -i supabase-db psql -U supabase -d postgres < docker/init/03_new_feature.sql
```

增量 SQL 规范：
- 所有 `CREATE TABLE` / `CREATE POLICY` / `CREATE INDEX` 必须用 `IF NOT EXISTS`
- 触发器用 `DROP TRIGGER IF EXISTS ...; CREATE TRIGGER ...`
- 函数用 `CREATE OR REPLACE FUNCTION`
- 升级前手动确认是否有需要备份的数据变更

### Docker Compose 升级

```bash
cd /opt/supabase/docker
docker compose pull           # 拉取最新镜像
docker compose up -d         # 重建容器（数据 volume 不会丢）
```

---

## 9. 常见问题

**Q：Kong 启动报错 `Error reading kong.yml`**
A：检查 `docker/kong.yml` 里服务名是否和 `docker-compose.yml` 一致。`docker compose config` 可以检查合并后的配置。

**Q：前端登录后报 `JWT expired` 或 `signature mismatch`**
A：前端的 `VITE_SUPABASE_ANON_KEY` / `VITE_SUPABASE_URL` 必须和服务器 `.env` 里的 `SUPABASE_ANON_KEY` / `JWT_SECRET` 对应。前端需要重新 `npm run build` 并上传。

**Q：浏览器打不开 Supabase REST API（`http://IP:8000/rest/v1/`）**
A：检查 Kong 端口绑定。默认只绑定 `127.0.0.1:8000`，局域网需要改成 `"8000:8000"`，然后重启 `docker compose up -d`。

**Q：定时备份脚本报 `pg_dump: command not found`**
A：服务器没装 PostgreSQL 客户端，执行 `yum install postgresql` 或 `apt install postgresql-client`。

**Q：忘记 sys_admin 密码**
A：用服务端密钥调 gotrue admin API 重置，或直接 psql 更新 `auth.users.encrypted_password`（重新生成 bcrypt hash）。

**Q：RLS 策略导致前端查询返回空**
A：绝大多数是 `profiles.school_id` / `profiles.class_id` 没绑定好。登录后查：
```sql
SELECT auth.uid();
SELECT * FROM public.profiles WHERE id = auth.uid();
```
