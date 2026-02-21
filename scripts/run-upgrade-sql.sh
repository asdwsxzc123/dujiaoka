#!/bin/bash

#######################################
# 独角数卡 - 独立执行升级 SQL
# 用法: bash scripts/run-upgrade-sql.sh
# 场景: upgrade.sh 中途失败后，手动补执行未完成的 SQL
# 已执行的 SQL 会自动跳过（通过 schema_upgrades 表跟踪）
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

# ========== 定位项目根目录 ==========
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 容器名（与 docker-compose.yml 一致）
MYSQL_CONTAINER="dujiaoka-mysql"
UPGRADES_DIR="database/sql/upgrades"
# MySQL root 密码（运行时输入，不存入代码仓库）
read -sp "请输入 MySQL root 密码: " DB_ROOT_PASSWORD
echo ""

# 读取数据库名
DATA_DIR=""
if [ -f ".env.docker" ]; then
    DATA_DIR=$(grep "^DATA_DIR=" .env.docker | cut -d '=' -f2)
fi
APP_ENV="${DATA_DIR}/dujiaoka/.env"
DB_DATABASE=""
if [ -f "$APP_ENV" ]; then
    DB_DATABASE=$(grep "^DB_DATABASE=" "$APP_ENV" | cut -d '=' -f2)
fi

if [ -z "$DB_DATABASE" ]; then
    log_error "无法读取数据库名，请检查 ${APP_ENV}"
    exit 1
fi

# ========== 检查 MySQL 容器 ==========
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    log_error "${MYSQL_CONTAINER} 未运行"
    exit 1
fi
log_ok "数据库: ${DB_DATABASE}"

# ========== 确保跟踪表存在 ==========
docker exec "$MYSQL_CONTAINER" mysql -uroot -p"${DB_ROOT_PASSWORD}" "$DB_DATABASE" -e "
CREATE TABLE IF NOT EXISTS schema_upgrades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE COMMENT '已执行的 SQL 文件名',
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '执行时间'
) COMMENT='升级 SQL 执行记录';" 2>/dev/null

# ========== 执行升级 SQL ==========
if [ ! -d "$UPGRADES_DIR" ]; then
    log_info "upgrades 目录不存在，无需执行"
    exit 0
fi

SQL_FILES=$(ls -1 "${UPGRADES_DIR}"/*.sql 2>/dev/null | sort)
if [ -z "$SQL_FILES" ]; then
    log_info "无升级 SQL 文件"
    exit 0
fi

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
        log_warn "请检查 SQL 文件后重新执行本脚本"
        exit 1
    fi
done

log_ok "升级 SQL 完成（执行: ${APPLIED}, 跳过: ${SKIPPED}）"
