<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * 推广码表新增佣金比例字段
 */
class AddCommissionRateToAffiliateCodes extends Migration
{
    public function up()
    {
        Schema::table('affiliate_codes', function (Blueprint $table) {
            // 佣金比例（百分比，如 10 表示 10%）
            $table->decimal('commission_rate', 5, 2)
                  ->default(0.00)
                  ->after('discount_value')
                  ->comment('佣金比例(%)');
        });
    }

    public function down()
    {
        Schema::table('affiliate_codes', function (Blueprint $table) {
            $table->dropColumn('commission_rate');
        });
    }
}
