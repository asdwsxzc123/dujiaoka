#!/bin/bash

#######################################
# 独角数卡 Docker 升级脚本
# 用法: bash upgrade.sh
# 流程: 备份 → git pull → 拉取镜像 → 重建容器 → 执行升级SQL → 清缓存 → 验证
# 升级SQL: database/sql/upgrades/ 目录，按文件名排序执行
# 跟踪表: schema_upgrades 记录已执行的SQL，防止重复执行
#######################################

set -e

# ========== 颜色 & 工具函数 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"
LOG_FILE="upgrade_${TIMESTAMP}.log"

log()       { echo -e "$1" | tee -a "$LOG_FILE"; }
log_info()  { log "${BLUE}[INFO]${NC} $1"; }
log_ok()    { log "${GREEN}[ OK ]${NC} $1"; }
log_warn()  { log "${YELLOW}[WARN]${NC} $1"; }
log_error() { log "${RED}[FAIL]${NC} $1"; }

# 容器名（与 docker-compose.yml 一致）
WEB_CONTAINER="dujiaoka"
MYSQL_CONTAINER="dujiaoka-mysql"
UPGRADES_DIR="database/sql/upgrades"

# ========== 读取数据库配置 ==========
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# 从数据目录的 .env 读取配置（容器内使用的配置）
ENV_DOCKER_FLAG=""
if [ -f ".env.docker" ]; then
    ENV_DOCKER_FLAG="--env-file .env.docker"
    DATA_DIR=$(grep "^DATA_DIR=" .env.docker | cut -d '=' -f2)
fi

# 从应用 .env 读取数据库信息
APP_ENV="${DATA_DIR}/dujiaoka/.env"
if [ -f "$APP_ENV" ]; then
    DB_DATABASE=$(grep "^DB_DATABASE=" "$APP_ENV" | cut -d '=' -f2)
    DB_USERNAME=$(grep "^DB_USERNAME=" "$APP_ENV" | cut -d '=' -f2)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" "$APP_ENV" | cut -d '=' -f2)
fi

# 也尝试从 docker-compose.yml 获取 root 密码（用于创建跟踪表）
DB_ROOT_PASSWORD="root123456"

echo "========================================="
echo "  独角数卡 - 升级脚本"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""

# ========== 1. 环境检查 ==========
log_info "【1/6】环境检查"

if [ ! -f "docker-compose.yml" ]; then
    log_error "请在项目根目录执行此脚本"
    exit 1
fi

# 检查容器运行状态
for name in "$WEB_CONTAINER" "$MYSQL_CONTAINER"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        log_error "${name} 未运行，请先执行 install.sh"
        exit 1
    fi
    log_ok "${name} 运行中"
done

if [ -z "$DB_DATABASE" ] || [ -z "$DB_USERNAME" ]; then
    log_error "数据库配置不完整，请检查 ${APP_ENV}"
    exit 1
fi
log_ok "数据库: ${DB_DATABASE}"
echo ""

# ========== 2. 数据库备份 ==========
log_info "【2/6】数据库备份"

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql"

docker exec "$MYSQL_CONTAINER" \
    mysqldump -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "$DB_DATABASE" > "$BACKUP_FILE" 2>/dev/null

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log_ok "备份完成: ${BACKUP_FILE} (${BACKUP_SIZE})"
echo ""

# ========== 3. 拉取最新代码和镜像 ==========
log_info "【3/6】拉取更新"

# 拉取最新代码（获取新的升级 SQL 和脚本）
if [ -d ".git" ]; then
    CURRENT_COMMIT=$(git rev-parse --short HEAD)
    log_info "当前版本: ${CURRENT_COMMIT}"
    git pull --rebase 2>&1 | tee -a "$LOG_FILE"
    NEW_COMMIT=$(git rev-parse --short HEAD)
    log_ok "代码更新: ${CURRENT_COMMIT} → ${NEW_COMMIT}"
fi

# 拉取最新 Docker 镜像
log_info "拉取最新镜像..."
docker compose ${ENV_DOCKER_FLAG} pull web
log_ok "镜像已更新"
echo ""

# ========== 4. 重建 Web 容器 ==========
log_info "【4/6】重建 Web 容器"

docker compose ${ENV_DOCKER_FLAG} up -d web
sleep 5

if ! docker ps --format '{{.Names}}' | grep -q "^${WEB_CONTAINER}$"; then
    log_error "Web 容器重建失败"
    log_warn "回滚: docker exec ${MYSQL_CONTAINER} sh -c 'mysql -u${DB_USERNAME} -p*** ${DB_DATABASE} < /tmp/rollback.sql'"
    exit 1
fi
log_ok "Web 容器已重建"
echo ""

# ========== 5. 执行升级 SQL ==========
log_info "【5/6】执行升级 SQL"

# 确保跟踪表存在
docker exec "$MYSQL_CONTAINER" mysql -uroot -p"${DB_ROOT_PASSWORD}" "$DB_DATABASE" -e "
CREATE TABLE IF NOT EXISTS schema_upgrades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE COMMENT '已执行的 SQL 文件名',
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '执行时间'
) COMMENT='升级 SQL 执行记录';" 2>/dev/null

# 检查 upgrades 目录是否有 SQL 文件
if [ -d "$UPGRADES_DIR" ]; then
    # 获取所有 .sql 文件，按文件名排序
    SQL_FILES=$(ls -1 "${UPGRADES_DIR}"/*.sql 2>/dev/null | sort)

    if [ -n "$SQL_FILES" ]; then
        APPLIED=0
        SKIPPED=0

        for sql_file in $SQL_FILES; do
            filename=$(basename "$sql_file")

            # 检查是否已执行过（查询跟踪表）
            ALREADY_APPLIED=$(docker exec "$MYSQL_CONTAINER" \
                mysql -uroot -p"${DB_ROOT_PASSWORD}" "$DB_DATABASE" \
                -sNe "SELECT COUNT(*) FROM schema_upgrades WHERE filename='${filename}';" 2>/dev/null)

            if [ "$ALREADY_APPLIED" = "1" ]; then
                log_info "跳过（已执行）: ${filename}"
                SKIPPED=$((SKIPPED + 1))
                continue
            fi

            # 执行 SQL 文件
            log_info "执行: ${filename}"
            if docker cp "$sql_file" "${MYSQL_CONTAINER}:/tmp/${filename}" && \
               docker exec "$MYSQL_CONTAINER" \
                   sh -c "mysql -uroot -p'${DB_ROOT_PASSWORD}' '${DB_DATABASE}' < /tmp/${filename}" 2>/dev/null; then

                # 记录到跟踪表
                docker exec "$MYSQL_CONTAINER" mysql -uroot -p"${DB_ROOT_PASSWORD}" "$DB_DATABASE" \
                    -e "INSERT INTO schema_upgrades (filename) VALUES ('${filename}');" 2>/dev/null
                log_ok "成功: ${filename}"
                APPLIED=$((APPLIED + 1))
            else
                log_error "失败: ${filename}"
                log_warn "请手动检查并修复后重新运行升级脚本"
                log_warn "数据库备份: ${BACKUP_FILE}"
                exit 1
            fi
        done

        log_ok "升级 SQL 完成（执行: ${APPLIED}, 跳过: ${SKIPPED}）"
    else
        log_info "无升级 SQL 文件"
    fi
else
    log_info "upgrades 目录不存在，跳过"
fi
echo ""

# ========== 6. 清理缓存 & 验证 ==========
log_info "【6/6】清理缓存 & 验证"

# 清除缓存
docker exec "$WEB_CONTAINER" php artisan config:clear 2>/dev/null || true
docker exec "$WEB_CONTAINER" php artisan route:clear 2>/dev/null || true
docker exec "$WEB_CONTAINER" php artisan view:clear 2>/dev/null || true
docker exec "$WEB_CONTAINER" php artisan cache:clear 2>/dev/null || true
log_ok "缓存已清理"

# 验证容器状态
for name in "$WEB_CONTAINER" "$MYSQL_CONTAINER" "dujiaoka-redis"; do
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        log_ok "${name} 运行中"
    else
        log_warn "${name} 未运行"
    fi
done

# 验证队列进程
if docker exec "$WEB_CONTAINER" sh -c "ps aux | grep 'queue:work' | grep -v grep" &>/dev/null; then
    log_ok "队列进程运行中"
else
    log_warn "队列进程未检测到（非必须）"
fi

echo ""
echo "========================================="
log_ok "升级完成!"
echo "========================================="
echo ""
log_info "备份文件: ${BACKUP_FILE}"
log_info "日志文件: ${LOG_FILE}"
echo ""
log_info "手动回滚命令（如需要）:"
log_info "  docker cp ${BACKUP_FILE} ${MYSQL_CONTAINER}:/tmp/rollback.sql"
log_info "  docker exec ${MYSQL_CONTAINER} sh -c 'mysql -u${DB_USERNAME} -p*** ${DB_DATABASE} < /tmp/rollback.sql'"
echo "========================================="