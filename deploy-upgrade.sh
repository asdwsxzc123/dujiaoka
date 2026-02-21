#!/bin/bash

#######################################
# 独角数卡 - 增量升级部署脚本 (Docker)
# 用法: bash deploy-upgrade.sh
# 功能: 数据库备份 → 重建容器 → 迁移 → 缓存清理 → 验证
# 适用: 代码已更新后的增量升级（非首次部署）
#######################################

set -e

# ---------- 颜色 & 工具函数 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"
LOG_FILE="deploy_upgrade_${TIMESTAMP}.log"

# Web / MySQL 容器名（与 docker-compose.yml 一致）
WEB_CONTAINER="dujiaoka"
MYSQL_CONTAINER="dujiaoka-mysql"

# 从 .env 读取数据库配置
DB_DATABASE=$(grep "^DB_DATABASE=" .env | cut -d '=' -f2)
DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d '=' -f2)
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d '=' -f2)

log()         { echo -e "$1" | tee -a "$LOG_FILE"; }
log_ok()      { log "${GREEN}[OK]${NC} $1"; }
log_warn()    { log "${YELLOW}[WARN]${NC} $1"; }
log_err()     { log "${RED}[FAIL]${NC} $1"; }
log_info()    { log "${BLUE}[INFO]${NC} $1"; }

# ---------- 回滚函数 ----------
rollback() {
    log_err "部署失败，开始回滚..."

    # 恢复数据库
    if [ -f "${BACKUP_FILE}" ]; then
        log_info "恢复数据库..."
        docker cp "${BACKUP_FILE}" "${MYSQL_CONTAINER}:/tmp/rollback.sql"
        docker exec "${MYSQL_CONTAINER}" \
            sh -c "mysql -u${DB_USERNAME} -p${DB_PASSWORD} ${DB_DATABASE} < /tmp/rollback.sql" 2>/dev/null
        log_ok "数据库已恢复"
    fi

    # 恢复代码并重建容器
    if [ -n "${ROLLBACK_TAG}" ]; then
        log_info "恢复代码到 ${ROLLBACK_TAG}..."
        git checkout "${ROLLBACK_TAG}" -- . 2>/dev/null || true
        docker compose --env-file .env.docker up -d --build 2>/dev/null || true
    fi

    # 容器内清缓存
    docker exec "${WEB_CONTAINER}" php artisan cache:clear 2>/dev/null || true
    docker exec "${WEB_CONTAINER}" php artisan config:clear 2>/dev/null || true

    log_err "回滚完成，系统已恢复到升级前状态"
    exit 1
}

trap 'rollback' ERR

# ---------- 开始 ----------
log "========================================="
log "  独角数卡 - 增量升级部署"
log "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
log "========================================="
echo ""

# ========== 1. 环境检查 ==========
log_info "【1/7】环境检查"

# 项目目录
if [ ! -f "artisan" ] || [ ! -f "docker-compose.yml" ]; then
    log_err "请在项目根目录执行此脚本"
    exit 1
fi

# Docker 环境
if ! command -v docker &> /dev/null; then
    log_err "Docker 未安装"
    exit 1
fi

# 容器运行状态
if ! docker ps --format '{{.Names}}' | grep -q "^${WEB_CONTAINER}$"; then
    log_err "Web 容器 (${WEB_CONTAINER}) 未运行，请先执行 install.sh 完成首次部署"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    log_err "MySQL 容器 (${MYSQL_CONTAINER}) 未运行"
    exit 1
fi

log_ok "Docker: $(docker --version | grep -oP 'Docker version \K[^,]+')"
log_ok "容器 ${WEB_CONTAINER} 运行中"
log_ok "容器 ${MYSQL_CONTAINER} 运行中"

# 数据库配置
if [ -z "$DB_DATABASE" ] || [ -z "$DB_USERNAME" ]; then
    log_err ".env 中数据库配置不完整"
    exit 1
fi
log_ok "数据库: ${DB_DATABASE}"
echo ""

# ========== 2. 变更确认 ==========
log_info "【2/7】变更确认"

# 显示待部署的代码变更
log_info "本次变更文件:"
git diff --stat HEAD 2>/dev/null || true
echo ""
# 显示未跟踪的新文件
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null)
if [ -n "$UNTRACKED" ]; then
    log_info "新增文件:"
    echo "$UNTRACKED"
    echo ""
fi

# 检测迁移文件
MIGRATION_FILES=$(find database/migrations -name "*.php" -newer .git/index 2>/dev/null || \
                  git ls-files --others --exclude-standard database/migrations/ 2>/dev/null)
if [ -n "$MIGRATION_FILES" ]; then
    log_warn "检测到新迁移文件:"
    echo "$MIGRATION_FILES"
else
    log_info "无新迁移文件"
fi
echo ""

read -p "确认执行升级？[y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    log_warn "升级已取消"
    exit 0
fi
echo ""

# ========== 3. 数据库备份 ==========
log_info "【3/7】数据库备份"

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql"

# 在 MySQL 容器内执行 mysqldump，输出到宿主机
docker exec "${MYSQL_CONTAINER}" \
    mysqldump -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${DB_DATABASE}" > "${BACKUP_FILE}" 2>/dev/null

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log_ok "备份完成: ${BACKUP_FILE} (${BACKUP_SIZE})"
echo ""

# ========== 4. 代码备份 (Git Tag) ==========
log_info "【4/7】代码备份"

ROLLBACK_TAG="backup-before-upgrade-${TIMESTAMP}"
if [ -d ".git" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    CURRENT_COMMIT=$(git rev-parse --short HEAD)
    git tag "${ROLLBACK_TAG}" 2>/dev/null || true
    log_ok "当前: ${CURRENT_BRANCH}@${CURRENT_COMMIT}"
    log_ok "回滚标签: ${ROLLBACK_TAG}"
else
    log_warn "非 Git 仓库，跳过代码标签"
    ROLLBACK_TAG=""
fi
echo ""

# ========== 5. 重建 Web 容器 ==========
log_info "【5/7】重建 Web 容器"

# 检查 .env.docker 是否存在
ENV_DOCKER_FLAG=""
if [ -f ".env.docker" ]; then
    ENV_DOCKER_FLAG="--env-file .env.docker"
fi

log_info "构建镜像并重启容器..."
docker compose ${ENV_DOCKER_FLAG} up -d --build web

# 等待容器就绪
log_info "等待容器启动..."
sleep 5

# 验证容器健康
if ! docker ps --format '{{.Names}}' | grep -q "^${WEB_CONTAINER}$"; then
    log_err "Web 容器重建后未正常启动"
    exit 1
fi
log_ok "Web 容器已重建并启动"
echo ""

# ========== 6. 数据库迁移 + 缓存清理 ==========
log_info "【6/7】数据库迁移 & 缓存清理"

# 执行迁移（--force 跳过生产环境确认）
log_info "执行数据库迁移..."
MIGRATE_OUTPUT=$(docker exec "${WEB_CONTAINER}" php artisan migrate --force 2>&1)
echo "$MIGRATE_OUTPUT" | tee -a "$LOG_FILE"

# 判断迁移结果
if echo "$MIGRATE_OUTPUT" | grep -qiE "migrated|nothing to migrate"; then
    log_ok "数据库迁移完成"
else
    log_err "数据库迁移异常，请检查输出"
    exit 1
fi

# 清除全部缓存
log_info "清除缓存..."
docker exec "${WEB_CONTAINER}" php artisan config:clear
docker exec "${WEB_CONTAINER}" php artisan route:clear
docker exec "${WEB_CONTAINER}" php artisan view:clear
docker exec "${WEB_CONTAINER}" php artisan cache:clear

# 重建缓存
log_info "重建缓存..."
docker exec "${WEB_CONTAINER}" php artisan config:cache
docker exec "${WEB_CONTAINER}" php artisan route:cache

log_ok "缓存已清理并重建"
echo ""

# ========== 7. 部署验证 ==========
log_info "【7/7】部署验证"

VERIFY_PASS=true

# 验证路由
ROUTE_COUNT=$(docker exec "${WEB_CONTAINER}" php artisan route:list 2>/dev/null | grep -c affiliate || echo "0")
if [ "$ROUTE_COUNT" -gt "0" ]; then
    log_ok "路由: 已注册 (${ROUTE_COUNT} 条 affiliate 路由)"
else
    log_err "路由: affiliate 路由未找到"
    VERIFY_PASS=false
fi

# 验证迁移字段（commission_rate 列是否存在）
COLUMN_CHECK=$(docker exec "${MYSQL_CONTAINER}" \
    mysql -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${DB_DATABASE}" \
    -se "SHOW COLUMNS FROM affiliate_codes LIKE 'commission_rate';" 2>/dev/null || echo "")
if [ -n "$COLUMN_CHECK" ]; then
    log_ok "数据库: commission_rate 字段已存在"
else
    log_warn "数据库: commission_rate 字段未检测到（可能迁移未生效）"
    VERIFY_PASS=false
fi

# 验证容器进程
QUEUE_RUNNING=$(docker exec "${WEB_CONTAINER}" sh -c "ps aux | grep 'queue:work' | grep -v grep" 2>/dev/null || echo "")
if [ -n "$QUEUE_RUNNING" ]; then
    log_ok "队列: queue:work 进程运行中"
else
    log_warn "队列: queue:work 进程未检测到（非必须）"
fi

echo ""

# ========== 完成 ==========
if [ "$VERIFY_PASS" = true ]; then
    log "========================================="
    log_ok "升级部署成功!"
    log "========================================="
else
    log "========================================="
    log_warn "升级完成，但部分验证未通过，请手动检查"
    log "========================================="
fi

echo ""
log_info "部署摘要:"
log_info "  备份文件: ${BACKUP_FILE}"
log_info "  回滚标签: ${ROLLBACK_TAG}"
log_info "  日志文件: ${LOG_FILE}"
echo ""
log_info "手动回滚命令（如需要）:"
log_info "  git checkout ${ROLLBACK_TAG} -- ."
log_info "  docker cp ${BACKUP_FILE} ${MYSQL_CONTAINER}:/tmp/rollback.sql"
log_info "  docker exec ${MYSQL_CONTAINER} sh -c 'mysql -u${DB_USERNAME} -p${DB_PASSWORD} ${DB_DATABASE} < /tmp/rollback.sql'"
log_info "  docker compose ${ENV_DOCKER_FLAG} up -d --build web"
echo ""
log_info "验证地址:"
log_info "  后台: https://your-domain.com/admin → 优惠码管理 → Affiliate_Code"
log_info "  检查佣金比例字段是否显示"
echo ""
