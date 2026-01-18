#!/bin/bash
#
# 推广码功能升级脚本
# 用于已部署系统的数据库升级
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  推广码功能 - 数据库升级脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 配置（可通过环境变量覆盖）
MYSQL_CONTAINER="${MYSQL_CONTAINER:-dujiaoka-mysql}"
MYSQL_DATABASE="${MYSQL_DATABASE:-dujiaoka}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    echo -e "${RED}错误: MySQL 容器 '${MYSQL_CONTAINER}' 未运行${NC}"
    echo ""
    echo "可用的容器:"
    docker ps --format "  - {{.Names}} ({{.Image}})" | grep -i mysql
    echo ""
    echo "请设置正确的容器名称:"
    echo "  MYSQL_CONTAINER=your-container-name ./scripts/upgrade-aff.sh"
    exit 1
fi

echo -e "${YELLOW}配置信息:${NC}"
echo "  容器: ${MYSQL_CONTAINER}"
echo "  数据库: ${MYSQL_DATABASE}"
echo "  用户: ${MYSQL_USER}"
echo ""

# 构建 MySQL 命令
if [ -n "$MYSQL_PASSWORD" ]; then
    MYSQL_CMD="docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}"
else
    MYSQL_CMD="docker exec -i ${MYSQL_CONTAINER} mysql -u${MYSQL_USER} ${MYSQL_DATABASE}"
fi

# 检查数据库连接
echo -e "${YELLOW}[1/4] 检查数据库连接...${NC}"
if ! echo "SELECT 1;" | $MYSQL_CMD > /dev/null 2>&1; then
    echo -e "${RED}错误: 无法连接到数据库${NC}"
    echo "请检查数据库配置或设置密码:"
    echo "  MYSQL_PASSWORD=your-password ./scripts/upgrade-aff.sh"
    exit 1
fi
echo -e "${GREEN}  ✓ 数据库连接成功${NC}"

# 检查是否已升级
echo -e "${YELLOW}[2/4] 检查升级状态...${NC}"
TABLE_EXISTS=$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}' AND table_name='affiliate_codes';" | $MYSQL_CMD -N 2>/dev/null)

if [ "$TABLE_EXISTS" = "1" ]; then
    echo -e "${GREEN}  ✓ affiliate_codes 表已存在，跳过创建${NC}"
else
    echo -e "${YELLOW}  → 需要创建 affiliate_codes 表${NC}"
fi

# 检查订单表字段
FIELD_EXISTS=$(echo "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='${MYSQL_DATABASE}' AND table_name='orders' AND column_name='affiliate_code_id';" | $MYSQL_CMD -N 2>/dev/null)

if [ "$FIELD_EXISTS" = "1" ]; then
    echo -e "${GREEN}  ✓ orders 表字段已存在，跳过添加${NC}"
else
    echo -e "${YELLOW}  → 需要添加 orders 表字段${NC}"
fi

# 执行升级
echo -e "${YELLOW}[3/4] 执行数据库升级...${NC}"

# 创建推广码表
if [ "$TABLE_EXISTS" != "1" ]; then
    echo "  创建 affiliate_codes 表..."
    cat <<'SQL' | $MYSQL_CMD
CREATE TABLE IF NOT EXISTS `affiliate_codes` (
  `id` int unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `code` varchar(100) NOT NULL COMMENT '推广码（自动生成，唯一）',
  `is_open` tinyint NOT NULL DEFAULT '1' COMMENT '是否启用 1启用 0禁用',
  `discount_type` tinyint NOT NULL DEFAULT '1' COMMENT '折扣类型 1固定金额 2百分比',
  `discount_value` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '折扣值',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注说明',
  `use_count` int NOT NULL DEFAULT '0' COMMENT '使用次数统计',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='推广码表';
SQL
    echo -e "${GREEN}  ✓ affiliate_codes 表创建成功${NC}"
fi

# 添加订单表字段
if [ "$FIELD_EXISTS" != "1" ]; then
    echo "  添加 orders 表字段..."
    cat <<'SQL' | $MYSQL_CMD
ALTER TABLE `orders`
ADD COLUMN IF NOT EXISTS `affiliate_code_id` int DEFAULT NULL COMMENT '关联推广码id' AFTER `coupon_id`,
ADD COLUMN IF NOT EXISTS `affiliate_discount_price` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '推广码优惠价格' AFTER `coupon_discount_price`;
SQL
    echo -e "${GREEN}  ✓ orders 表字段添加成功${NC}"
fi

# 添加后台菜单
echo -e "${YELLOW}[4/4] 添加后台菜单...${NC}"
MENU_EXISTS=$(echo "SELECT COUNT(*) FROM admin_menu WHERE uri='/affiliate-code';" | $MYSQL_CMD -N 2>/dev/null)

if [ "$MENU_EXISTS" = "0" ]; then
    cat <<'SQL' | $MYSQL_CMD
INSERT INTO `admin_menu` (`parent_id`, `order`, `title`, `icon`, `uri`, `extension`, `show`, `created_at`, `updated_at`)
SELECT 18, COALESCE(MAX(`order`), 0) + 1, 'Affiliate_Code', 'fa-share-alt', '/affiliate-code', '', 1, NOW(), NOW()
FROM `admin_menu` WHERE `parent_id` = 18;
SQL
    echo -e "${GREEN}  ✓ 后台菜单添加成功${NC}"
else
    echo -e "${GREEN}  ✓ 后台菜单已存在，跳过添加${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  升级完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "后续步骤:"
echo "  1. 清除缓存: php artisan cache:clear"
echo "  2. 刷新后台页面，即可看到「推广码」菜单"
echo ""
