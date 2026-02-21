#!/bin/bash

#######################################
# 独角数卡 Docker 一键安装脚本
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- /自定义目录
#   或本地执行: bash install.sh
# 前提: 已安装 Docker 和 Git
#######################################

set -e

# ========== 颜色 & 工具函数 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 配置默认值 ==========
REPO_URL="https://github.com/asdwsxzc123/dujiaoka.git"
REPO_BRANCH="master"
# 支持通过参数指定安装目录，默认 ~/dujiaoka
PROJECT_DIR="${1:-$HOME/dujiaoka}"
DATA_DIR="${PROJECT_DIR}/data"
DOMAIN="pay.xxx.cn"
DB_NAME="dujiaoka"
DB_USER="dujiaoka"
DB_PASSWORD="dujiaoka123456"
DB_ROOT_PASSWORD=""

# 容器名（与 docker-compose.yml 一致）
WEB_CONTAINER="dujiaoka"
MYSQL_CONTAINER="dujiaoka-mysql"

echo "========================================"
echo "   独角数卡 Docker 一键安装脚本"
echo "========================================"
echo ""

# ========== 1. 环境检查 ==========
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装，请先安装: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! command -v git &> /dev/null; then
    log_error "Git 未安装，请先安装 Git"
    exit 1
fi

log_info "Docker: $(docker --version)"

# 如果项目目录不存在或缺少 docker-compose.yml，自动克隆
if [ ! -f "${PROJECT_DIR}/docker-compose.yml" ]; then
    log_info "克隆项目到 ${PROJECT_DIR}..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$PROJECT_DIR"
    log_info "项目已克隆"
fi

cd "$PROJECT_DIR"

# ========== 2. 交互式配置 ==========
echo ""
log_warn "请确认配置信息（回车使用默认值）："
read -p "域名 [${DOMAIN}]: " input && DOMAIN=${input:-$DOMAIN}
read -p "数据库名 [${DB_NAME}]: " input && DB_NAME=${input:-$DB_NAME}
read -p "数据库用户 [${DB_USER}]: " input && DB_USER=${input:-$DB_USER}
read -p "数据库密码 [${DB_PASSWORD}]: " input && DB_PASSWORD=${input:-$DB_PASSWORD}
read -sp "MySQL root 密码（必填）: " DB_ROOT_PASSWORD && echo ""
if [ -z "$DB_ROOT_PASSWORD" ]; then
    log_error "MySQL root 密码不能为空"
    exit 1
fi
read -p "数据目录 [${DATA_DIR}]: " input && DATA_DIR=${input:-$DATA_DIR}

echo ""
log_info "域名: ${DOMAIN}"
log_info "数据库: ${DB_NAME} / ${DB_USER}"
log_info "数据目录: ${DATA_DIR}"
echo ""
read -p "确认部署？(y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_warn "已取消"
    exit 0
fi

# ========== 3. 创建目录结构 ==========
log_info "创建数据目录..."
mkdir -p "${DATA_DIR}/dujiaoka/public/uploads/"{images,files}
mkdir -p "${DATA_DIR}/dujiaoka/"{mysql,redis}
chmod -R 777 "${DATA_DIR}/dujiaoka/public/uploads"

# ========== 4. 生成配置文件 ==========
log_info "生成 .env.docker..."
cat > .env.docker <<EOF
# Docker Compose 环境变量
DATA_DIR=${DATA_DIR}
EOF

# 基于 .env.example 生成应用配置
log_info "生成应用 .env..."
if [ ! -f ".env.example" ]; then
    log_error ".env.example 不存在"
    exit 1
fi

# 生成随机 APP_KEY
APP_KEY=$(openssl rand -base64 32)

# 用 .env.example 模板生成 .env，写入到数据目录
sed -e "s|{title}|独角数卡|g" \
    -e "s|{app_key}|base64:${APP_KEY}|g" \
    -e "s|{app_url}|https://${DOMAIN}|g" \
    -e "s|{db_host}|mysql|g" \
    -e "s|{db_port}|3306|g" \
    -e "s|{db_database}|${DB_NAME}|g" \
    -e "s|{db_username}|${DB_USER}|g" \
    -e "s|{db_password}|${DB_PASSWORD}|g" \
    -e "s|{redis_host}|redis|g" \
    -e "s|{redis_password}||g" \
    -e "s|{redis_port}|6379|g" \
    -e "s|{admin_path}|admin|g" \
    -e "s|ADMIN_HTTPS=false|ADMIN_HTTPS=true|g" \
    .env.example > "${DATA_DIR}/dujiaoka/.env"

log_info "配置文件已生成"

# ========== 5. 拉取镜像并启动 ==========
log_info "拉取最新镜像..."
docker compose --env-file .env.docker pull

log_info "启动服务..."
docker compose --env-file .env.docker up -d

# ========== 6. 等待服务就绪 ==========
log_info "等待服务启动..."
sleep 10

# 检查容器状态
FAIL=false
for name in "$WEB_CONTAINER" "$MYSQL_CONTAINER" "dujiaoka-redis"; do
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        log_info "${name} 运行中"
    else
        log_error "${name} 启动失败"
        FAIL=true
    fi
done

if [ "$FAIL" = true ]; then
    log_error "部分容器启动失败，请检查: docker compose --env-file .env.docker logs"
    exit 1
fi

# ========== 7. 初始化升级跟踪表 ==========
log_info "初始化数据库升级跟踪表..."
# 等待 MySQL 完全就绪
for i in $(seq 1 30); do
    if docker exec "$MYSQL_CONTAINER" mysqladmin -uroot -p"${DB_ROOT_PASSWORD}" ping &>/dev/null; then
        break
    fi
    sleep 2
done

# 创建 schema_upgrades 表，用于记录已执行的升级 SQL
docker exec "$MYSQL_CONTAINER" mysql -uroot -p"${DB_ROOT_PASSWORD}" "$DB_NAME" -e "
CREATE TABLE IF NOT EXISTS schema_upgrades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE COMMENT '已执行的 SQL 文件名',
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '执行时间'
) COMMENT='升级 SQL 执行记录';" 2>/dev/null

log_info "跟踪表已就绪"

# ========== 8. 完成 ==========
echo ""
echo "========================================"
log_info "安装完成!"
echo "========================================"
echo ""
log_info "前台: https://${DOMAIN}"
log_info "后台: https://${DOMAIN}/admin"
log_info "默认账号: admin / admin"
echo ""
log_info "数据目录: ${DATA_DIR}/dujiaoka/"
echo ""
log_warn "请立即登录后台修改默认密码!"
log_warn "首次访问可能需要完成安装向导"
log_warn "确保域名 DNS 已解析到本服务器"
echo "========================================"
