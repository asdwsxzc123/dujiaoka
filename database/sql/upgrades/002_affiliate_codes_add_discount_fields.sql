-- 002: 补齐 affiliate_codes 表的折扣字段
-- 适用场景：表已存在但缺少 discount_type、discount_value、commission_rate 字段
-- 所有语句做了存在性检查，可重复执行

DELIMITER $$
CREATE PROCEDURE _upgrade_add_affiliate_discount_fields()
BEGIN
    -- 补齐 discount_type 字段
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'affiliate_codes'
          AND COLUMN_NAME = 'discount_type'
    ) THEN
        ALTER TABLE `affiliate_codes`
            ADD COLUMN `discount_type` tinyint NOT NULL DEFAULT 1
            COMMENT '折扣类型 1固定金额 2百分比' AFTER `is_open`;
    END IF;

    -- 补齐 discount_value 字段
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'affiliate_codes'
          AND COLUMN_NAME = 'discount_value'
    ) THEN
        ALTER TABLE `affiliate_codes`
            ADD COLUMN `discount_value` decimal(10,2) NOT NULL DEFAULT 0.00
            COMMENT '折扣值' AFTER `discount_type`;
    END IF;

    -- 补齐 commission_rate 字段
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'affiliate_codes'
          AND COLUMN_NAME = 'commission_rate'
    ) THEN
        ALTER TABLE `affiliate_codes`
            ADD COLUMN `commission_rate` decimal(5,2) DEFAULT 0.00
            COMMENT 'KOL佣金比例(%)' AFTER `discount_value`;
    END IF;
END$$
DELIMITER ;

CALL _upgrade_add_affiliate_discount_fields();
DROP PROCEDURE IF EXISTS _upgrade_add_affiliate_discount_fields;
