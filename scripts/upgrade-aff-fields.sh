#!/bin/bash
#
# 推广码字段升级脚本（Docker 环境）
# 为 affiliate_codes 表补齐 discount_type、discount_value、commission_rate 字段
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  推广码字段升级脚本（Docker版）${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 配置（可通过环境变量覆盖）
MYSQL_CONTAINER="${MYSQL_CONTAINER:-dujiaoka-mysql}"
MYSQL_USER="${MYSQL_USER:-dujiaoka}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-dujiaoka123456}"
MYSQL_DATABASE="${MYSQL_DATABASE:-dujiaoka}"

# 获取脚本所在目录，定位 SQL 文件
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../database/sql/upgrades/002_affiliate_codes_add_discount_fields.sql"

# [1/5] 检查容器状态
echo -e "${YELLOW}[1/5] 检查 Docker 容器状态...${NC}"
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    echo -e "${RED}错误: MySQL 容器 '${MYSQL_CONTAINER}' 未运行${NC}"
    echo ""
    echo "可用的容器:"
    docker ps --format "  - {{.Names}} ({{.Image}})" | grep -i mysql
    echo ""
    echo "请设置正确的容器名称:"
    echo "  MYSQL_CONTAINER=your-container-name bash scripts/upgrade-aff-fields.sh"
    exit 1
fi
echo -e "${GREEN}  ✓ 容器 ${MYSQL_CONTAINER} 运行中${NC}"

# [2/5] 检查数据库连接
echo -e "${YELLOW}[2/5] 检查数据库连接...${NC}"
if ! docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${RED}错误: 无法连接到数据库${NC}"
    echo "请检查配置或设置密码:"
    echo "  MYSQL_PASSWORD=your-password bash scripts/upgrade-aff-fields.sh"
    exit 1
fi
echo -e "${GREEN}  ✓ 数据库连接成功${NC}"

# [3/5] 检查当前字段状态
echo -e "${YELLOW}[3/5] 检查 affiliate_codes 表字段状态...${NC}"

# 检查表是否存在
TABLE_EXISTS=$(docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -sN -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}' AND table_name='affiliate_codes';" 2>/dev/null)

if [ "$TABLE_EXISTS" != "1" ]; then
    echo -e "${RED}错误: affiliate_codes 表不存在，请先执行 001_affiliate_commission.sql${NC}"
    exit 1
fi

# 逐个检查字段
NEED_UPGRADE=0
for FIELD in discount_type discount_value commission_rate; do
    EXISTS=$(docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -sN -e \
        "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='${MYSQL_DATABASE}' AND table_name='affiliate_codes' AND column_name='${FIELD}';" 2>/dev/null)
    if [ "$EXISTS" = "1" ]; then
        echo -e "${GREEN}  ✓ ${FIELD} 已存在${NC}"
    else
        echo -e "${YELLOW}  → ${FIELD} 缺失，需要添加${NC}"
        NEED_UPGRADE=1
    fi
done

if [ "$NEED_UPGRADE" = "0" ]; then
    echo ""
    echo -e "${GREEN}所有字段已存在，无需升级。${NC}"
    exit 0
fi

# [4/5] 执行 SQL 升级脚本
echo -e "${YELLOW}[4/5] 执行字段升级...${NC}"

if [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}错误: SQL 文件不存在: ${SQL_FILE}${NC}"
    exit 1
fi

docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} < "$SQL_FILE" 2>&1
echo -e "${GREEN}  ✓ SQL 执行完成${NC}"

# [5/5] 验证升级结果
echo -e "${YELLOW}[5/5] 验证升级结果...${NC}"

ALL_OK=1
for FIELD in discount_type discount_value commission_rate; do
    EXISTS=$(docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -sN -e \
        "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='${MYSQL_DATABASE}' AND table_name='affiliate_codes' AND column_name='${FIELD}';" 2>/dev/null)
    if [ "$EXISTS" = "1" ]; then
        echo -e "${GREEN}  ✓ ${FIELD} 验证通过${NC}"
    else
        echo -e "${RED}  ✗ ${FIELD} 添加失败${NC}"
        ALL_OK=0
    fi
done

echo ""
if [ "$ALL_OK" = "1" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  升级成功！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "当前 affiliate_codes 表结构:"
    docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -e "DESCRIBE affiliate_codes;" 2>/dev/null
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  升级失败，请检查错误日志${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
