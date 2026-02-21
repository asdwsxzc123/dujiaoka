# 推广码佣金比例功能升级文档

## 更新内容

1. 推广码新增「佣金比例」字段，创建/编辑推广码时可设置 KOL 返佣比例
2. 统计页新增快捷时间筛选按钮（本周、上周、上月）
3. 统计页新增佣金结算卡片，根据佣金比例自动计算应返佣金额

## 涉及文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `database/migrations/2026_02_17_000001_add_commission_rate_to_affiliate_codes.php` | 新增 | 迁移文件，`affiliate_codes` 表新增 `commission_rate` 字段 |
| `app/Models/AffiliateCode.php` | 修改 | `fillable` 和 `casts` 加入 `commission_rate` |
| `app/Admin/Controllers/AffiliateCodeController.php` | 修改 | 表单增加佣金比例输入，列表增加佣金比例列 |
| `resources/views/admin/affiliate_stats.blade.php` | 修改 | 快捷时间按钮 + 佣金结算卡片 |

## 数据库变更

`affiliate_codes` 表新增字段：

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `commission_rate` | decimal(5,2) | 0.00 | 佣金比例(%)，如 10 表示 10% |

## 升级步骤

### 1. 拉取最新代码

```bash
git pull origin master
```

### 2. 执行数据库迁移

```bash
docker exec -it dujiaoka php artisan migrate
```

### 3. 清除缓存（如有）

```bash
docker exec -it dujiaoka php artisan config:clear
docker exec -it dujiaoka php artisan view:clear
```

### 4. 验证

- 访问后台推广码列表，确认新增「佣金比例」列
- 编辑任意推广码，设置佣金比例
- 进入统计页，确认快捷时间按钮和佣金结算卡片正常显示

## 回滚方案

```bash
docker exec -it dujiaoka php artisan migrate:rollback --step=1
```

执行后 `commission_rate` 字段将被移除，不影响其他功能。
