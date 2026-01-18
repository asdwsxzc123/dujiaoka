#!/bin/bash
#
# 推广码功能回滚脚本
# 用于回滚数据库升级（谨慎使用！）
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}  推广码功能 - 数据库回滚脚本${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${RED}⚠️  警告: 此操作将删除推广码相关数据！${NC}"
echo ""

# 配置（可通过环境变量覆盖）
MYSQL_CONTAINER="${MYSQL_CONTAINER:-dujiaoka-mysql}"
MYSQL_DATABASE="${MYSQL_DATABASE:-dujiaoka}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    echo -e "${RED}错误: MySQL 容器 '${MYSQL_CONTAINER}' 未运行${NC}"
    exit 1
fi

echo -e "${YELLOW}配置信息:${NC}"
echo "  容器: ${MYSQL_CONTAINER}"
echo "  数据库: ${MYSQL_DATABASE}"
echo ""

# 构建 MySQL 命令
if [ -n "$MYSQL_PASSWORD" ]; then
    MYSQL_CMD="docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}"
else
    MYSQL_CMD="docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} ${MYSQL_DATABASE}"
fi

# 检查数据库连接
echo -e "${YELLOW}[1/5] 检查数据库连接...${NC}"
if ! echo "SELECT 1;" | $MYSQL_CMD > /dev/null 2>&1; then
    echo -e "${RED}错误: 无法连接到数据库${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ 数据库连接成功${NC}"

# 检查是否有数据
echo -e "${YELLOW}[2/5] 检查现有数据...${NC}"
DATA_COUNT=$(echo "SELECT COUNT(*) FROM affiliate_codes;" | $MYSQL_CMD -N 2>/dev/null || echo "0")
ORDER_COUNT=$(echo "SELECT COUNT(*) FROM orders WHERE affiliate_code_id IS NOT NULL;" | $MYSQL_CMD -N 2>/dev/null || echo "0")

if [ "$DATA_COUNT" != "0" ] || [ "$ORDER_COUNT" != "0" ]; then
    echo -e "${RED}  ⚠️  发现现有数据:${NC}"
    echo "     - 推广码数量: ${DATA_COUNT}"
    echo "     - 关联订单数: ${ORDER_COUNT}"
    echo ""
    echo -e "${RED}回滚将删除这些数据！${NC}"
fi

# 确认操作
echo ""
echo -e "${YELLOW}确认回滚操作？输入 'YES' 继续:${NC}"
read -r CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo -e "${YELLOW}已取消回滚操作${NC}"
    exit 0
fi

# 备份数据（可选）
echo -e "${YELLOW}[3/5] 备份现有数据...${NC}"
BACKUP_FILE="affiliate_backup_$(date +%Y%m%d_%H%M%S).sql"

if [ "$DATA_COUNT" != "0" ]; then
    echo "SELECT * FROM affiliate_codes;" | $MYSQL_CMD > "/tmp/${BACKUP_FILE}" 2>/dev/null || true
    echo -e "${GREEN}  ✓ 数据已备份到容器 /tmp/${BACKUP_FILE}${NC}"
else
    echo -e "${GREEN}  ✓ 无数据需要备份${NC}"
fi

# 执行回滚
echo -e "${YELLOW}[4/5] 执行数据库回滚...${NC}"

# 删除后台菜单
echo "  删除后台菜单..."
echo "DELETE FROM admin_menu WHERE uri='/affiliate-code';" | $MYSQL_CMD 2>/dev/null || true
echo -e "${GREEN}  ✓ 后台菜单已删除${NC}"

# 删除订单表字段
echo "  删除 orders 表字段..."
cat <<'SQL' | $MYSQL_CMD 2>/dev/null || true
ALTER TABLE `orders`
DROP COLUMN IF EXISTS `affiliate_code_id`,
DROP COLUMN IF EXISTS `affiliate_discount_price`;
SQL
echo -e "${GREEN}  ✓ orders 表字段已删除${NC}"

# 删除推广码表
echo "  删除 affiliate_codes 表..."
echo "DROP TABLE IF EXISTS affiliate_codes;" | $MYSQL_CMD 2>/dev/null || true
echo -e "${GREEN}  ✓ affiliate_codes 表已删除${NC}"

# 清除缓存提示
echo -e "${YELLOW}[5/5] 完成${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  回滚完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "后续步骤:"
echo "  1. 清除缓存: php artisan cache:clear"
echo "  2. 如需恢复数据，备份文件在: /tmp/${BACKUP_FILE}"
echo ""
