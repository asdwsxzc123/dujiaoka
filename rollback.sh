#!/bin/bash

#######################################
# 独角数卡 Docker 回滚脚本
# 用法: bash rollback.sh
# 功能: 将系统恢复到上一次升级前的状态
# 依赖: upgrade.sh 生成的 backups/rollback_latest.sh
#######################################

set -e

# ========== 颜色 & 工具函数 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

# 容器名
WEB_CONTAINER="dujiaoka"
MYSQL_CONTAINER="dujiaoka-mysql"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

ROLLBACK_INFO="./backups/rollback_latest.sh"

echo "========================================="
echo "  独角数卡 - 回滚脚本"
echo "========================================="
echo ""

# ========== 1. 读取回滚信息 ==========
if [ ! -f "$ROLLBACK_INFO" ]; then
    log_error "未找到回滚信息文件: ${ROLLBACK_INFO}"
    log_error "请确认已执行过 upgrade.sh 且 backups 目录完整"
    exit 1
fi

# 加载回滚变量
source "$ROLLBACK_INFO"

log_info "回滚信息:"
log_info "  时间戳: ${ROLLBACK_TIMESTAMP}"
log_info "  数据库备份: ${ROLLBACK_DB_BACKUP}"
log_info "  .env 备份: ${ROLLBACK_ENV_BACKUP}"
log_info "  旧镜像 ID: ${ROLLBACK_OLD_IMAGE_ID:-无}"
log_info "  旧 Git Commit: ${ROLLBACK_OLD_COMMIT:-无}"
echo ""

# 确认
read -p "确认回滚到升级前状态？此操作不可逆 (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_warn "已取消"
    exit 0
fi
echo ""

# 读取数据库配置
ENV_DOCKER_FLAG=""
if [ -f ".env.docker" ]; then
    ENV_DOCKER_FLAG="--env-file .env.docker"
    DATA_DIR=$(grep "^DATA_DIR=" .env.docker | cut -d '=' -f2)
fi
APP_ENV="${DATA_DIR}/dujiaoka/.env"
DB_ROOT_PASSWORD="root123456"

if [ -f "$APP_ENV" ]; then
    DB_DATABASE=$(grep "^DB_DATABASE=" "$APP_ENV" | cut -d '=' -f2)
    DB_USERNAME=$(grep "^DB_USERNAME=" "$APP_ENV" | cut -d '=' -f2)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" "$APP_ENV" | cut -d '=' -f2)
fi

# ========== 2. 恢复 .env ==========
log_info "【1/5】恢复 .env"

if [ -f "$ROLLBACK_ENV_BACKUP" ]; then
    cp "$ROLLBACK_ENV_BACKUP" "$APP_ENV"
    log_ok ".env 已恢复"
else
    log_warn ".env 备份不存在，跳过"
fi
echo ""

# ========== 3. 恢复 Git 代码 ==========
log_info "【2/5】恢复代码"

if [ -n "$ROLLBACK_OLD_COMMIT" ] && [ -d ".git" ]; then
    CURRENT=$(git rev-parse --short HEAD)
    OLD_SHORT=$(echo "$ROLLBACK_OLD_COMMIT" | cut -c1-7)
    git checkout "$ROLLBACK_OLD_COMMIT" -- . 2>/dev/null
    log_ok "代码已恢复: ${CURRENT} → ${OLD_SHORT}"
else
    log_warn "无 Git 信息，跳过代码恢复"
fi
echo ""

# ========== 4. 恢复旧镜像并重建容器 ==========
log_info "【3/5】恢复旧镜像"

# 检查 rollback tag 是否存在
if docker image inspect asdwsxzc123/dujiaoka:rollback &>/dev/null; then
    # 把 rollback tag 重新标记为 latest，这样 docker compose up 会使用旧镜像
    docker tag asdwsxzc123/dujiaoka:rollback asdwsxzc123/dujiaoka:latest
    log_ok "旧镜像已恢复为 latest"
else
    log_warn "未找到 rollback 镜像标签，将使用当前 latest 镜像"
fi

log_info "【4/5】重建容器"

# 强制重建容器（使用恢复后的镜像）
docker compose ${ENV_DOCKER_FLAG} up -d --force-recreate web
sleep 5

if docker ps --format '{{.Names}}' | grep -q "^${WEB_CONTAINER}$"; then
    log_ok "Web 容器已重建（使用旧镜像）"
else
    log_error "Web 容器启动失败"
    exit 1
fi
echo ""

# ========== 5. 恢复数据库 ==========
log_info "【5/5】恢复数据库"

if [ -f "$ROLLBACK_DB_BACKUP" ]; then
    docker cp "$ROLLBACK_DB_BACKUP" "${MYSQL_CONTAINER}:/tmp/rollback.sql"
    docker exec "$MYSQL_CONTAINER" \
        sh -c "mysql -uroot -p'${DB_ROOT_PASSWORD}' '${DB_DATABASE}' < /tmp/rollback.sql" 2>/dev/null
    docker exec "$MYSQL_CONTAINER" rm -f /tmp/rollback.sql
    log_ok "数据库已恢复"
else
    log_error "数据库备份文件不存在: ${ROLLBACK_DB_BACKUP}"
    exit 1
fi

# 清除缓存
docker exec "$WEB_CONTAINER" php artisan config:clear 2>/dev/null || true
docker exec "$WEB_CONTAINER" php artisan cache:clear 2>/dev/null || true
log_ok "缓存已清理"

echo ""
echo "========================================="
log_ok "回滚完成! 系统已恢复到升级前状态"
echo "========================================="