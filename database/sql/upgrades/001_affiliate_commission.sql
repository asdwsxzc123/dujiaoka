-- 001: 推广码功能 + 返佣比例
-- 适用于已部署项目的升级，所有语句都做了存在性检查，可重复执行

-- 1. 创建推广码表（如果不存在）
--    新项目通过 install.sql 不包含此表，需要手动创建
CREATE TABLE IF NOT EXISTS `affiliate_codes` (
  `id` int unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `code` varchar(100) NOT NULL COMMENT '推广码',
  `is_open` tinyint NOT NULL DEFAULT 1 COMMENT '是否启用 1启用 0禁用',
  `discount_type` tinyint NOT NULL DEFAULT 1 COMMENT '折扣类型 1固定金额 2百分比',
  `discount_value` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '折扣值',
  `commission_rate` decimal(5,2) NOT NULL DEFAULT 0.00 COMMENT '佣金比例(%)',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注说明',
  `use_count` int NOT NULL DEFAULT 0 COMMENT '使用次数统计',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='推广码表';

-- 2. 给已有的 affiliate_codes 表添加 commission_rate 字段（如果表已存在但缺少该字段）
--    用存储过程做字段存在性检查，避免重复添加报错
DELIMITER $$
CREATE PROCEDURE _upgrade_add_commission_rate()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'affiliate_codes'
          AND COLUMN_NAME = 'commission_rate'
    ) THEN
        ALTER TABLE `affiliate_codes`
            ADD COLUMN `commission_rate` decimal(5,2) NOT NULL DEFAULT 0.00
            COMMENT '佣金比例(%)' AFTER `discount_value`;
    END IF;
END$$
DELIMITER ;
CALL _upgrade_add_commission_rate();
DROP PROCEDURE IF EXISTS _upgrade_add_commission_rate;

-- 3. 给 orders 表添加推广码关联字段（如果缺少）
DELIMITER $$
CREATE PROCEDURE _upgrade_add_order_affiliate_fields()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'orders'
          AND COLUMN_NAME = 'affiliate_code_id'
    ) THEN
        ALTER TABLE `orders`
            ADD COLUMN `affiliate_code_id` int DEFAULT NULL COMMENT '关联推广码id';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'orders'
          AND COLUMN_NAME = 'affiliate_discount_price'
    ) THEN
        ALTER TABLE `orders`
            ADD COLUMN `affiliate_discount_price` decimal(10,2) NOT NULL DEFAULT 0.00
            COMMENT '推广码优惠价格';
    END IF;
END$$
DELIMITER ;
CALL _upgrade_add_order_affiliate_fields();
DROP PROCEDURE IF EXISTS _upgrade_add_order_affiliate_fields;

-- 4. 添加推广码管理菜单（如果不存在）
INSERT IGNORE INTO `admin_menu` (`id`, `parent_id`, `order`, `title`, `icon`, `uri`, `permission`, `show`, `created_at`, `updated_at`)
VALUES (26, 18, 17, 'Affiliate_Code', 'fa-share-alt', '/affiliate-code', '', 1, NOW(), NOW());
