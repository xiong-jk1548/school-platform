# 多阶段构建：Node 编译 → nginx:alpine 提供静态服务
FROM node:20-alpine AS build
WORKDIR /app

# ---- 前端运行时配置（编译时注入）----
# 默认 mock 模式；部署时传 --build-arg VITE_USE_REAL_SUPABASE=true
ARG VITE_USE_REAL_SUPABASE=false
ARG VITE_SUPABASE_URL=http://127.0.0.1:8000
ARG VITE_SUPABASE_ANON_KEY=
ENV VITE_USE_REAL_SUPABASE=${VITE_USE_REAL_SUPABASE}
ENV VITE_SUPABASE_URL=${VITE_SUPABASE_URL}
ENV VITE_SUPABASE_ANON_KEY=${VITE_SUPABASE_ANON_KEY}

# 先装依赖（利用 Docker build 缓存）
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci --registry=https://registry.npmmirror.com || npm install

# 再 copy 源码并 build
COPY frontend/ ./
RUN npm run build

# ---- 运行阶段 ----
FROM nginx:alpine
# 覆盖默认 nginx 配置（支持 Vue Router history 模式）
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
# 把构建产物丢到 nginx 的静态目录
COPY --from=build /app/dist /usr/share/nginx/html
# 暴露 80 端口
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
