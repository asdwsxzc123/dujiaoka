@php
    // 检查是否有筛选条件
    $hasFilters = !empty($filters['start_date']) || !empty($filters['end_date']) || !empty($filters['order_sn']) || !empty($filters['goods_id']);
    $filterLabel = $hasFilters ? ' (筛选结果)' : '';

    // 佣金计算
    $commissionRate = $affiliateCode->commission_rate ?? 0;
    $commissionAmount = $commissionRate > 0 ? round($stats['total_amount'] * $commissionRate / 100, 2) : 0;

    // 时段显示
    $periodText = '全部时段';
    if (!empty($filters['start_date']) && !empty($filters['end_date'])) {
        $periodText = $filters['start_date'] . ' ~ ' . $filters['end_date'];
    } elseif (!empty($filters['start_date'])) {
        $periodText = $filters['start_date'] . ' 起';
    } elseif (!empty($filters['end_date'])) {
        $periodText = '至 ' . $filters['end_date'];
    }
@endphp

<div class="row">
    <!-- 统计卡片 -->
    <div class="col-md-3">
        <div class="small-box bg-info">
            <div class="inner">
                <h3>{{ $stats['order_count'] }}</h3>
                <p>订单数量{{ $filterLabel }}</p>
            </div>
            <div class="icon">
                <i class="feather icon-shopping-cart"></i>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="small-box bg-success">
            <div class="inner">
                <h3>{{ number_format($stats['total_amount'], 2) }}</h3>
                <p>订单总金额 (元){{ $filterLabel }}</p>
            </div>
            <div class="icon">
                <i class="feather icon-dollar-sign"></i>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="small-box bg-warning">
            <div class="inner">
                <h3>{{ number_format($stats['discount_amount'], 2) }}</h3>
                <p>折扣总金额 (元){{ $filterLabel }}</p>
            </div>
            <div class="icon">
                <i class="feather icon-tag"></i>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="small-box bg-secondary">
            <div class="inner">
                <h3>{{ count($stats['goods_list']) }}</h3>
                <p>涉及商品数{{ $filterLabel }}</p>
            </div>
            <div class="icon">
                <i class="feather icon-package"></i>
            </div>
        </div>
    </div>
</div>

<!-- 佣金计算卡片 -->
<div class="card">
    <div class="card-header">
        <h3 class="card-title"><i class="feather icon-percent"></i> 佣金结算</h3>
    </div>
    <div class="card-body">
        <div class="row">
            <div class="col-md-3">
                <div class="commission-item">
                    <span class="commission-label">统计时段</span>
                    <span class="commission-value">{{ $periodText }}</span>
                </div>
            </div>
            <div class="col-md-3">
                <div class="commission-item">
                    <span class="commission-label">订单实付总额</span>
                    <span class="commission-value">¥{{ number_format($stats['total_amount'], 2) }}</span>
                </div>
            </div>
            <div class="col-md-3">
                <div class="commission-item">
                    <span class="commission-label">佣金比例</span>
                    <span class="commission-value">
                        @if($commissionRate > 0)
                            {{ $commissionRate }}%
                        @else
                            <span class="text-muted">未设置</span>
                        @endif
                    </span>
                </div>
            </div>
            <div class="col-md-3">
                <div class="commission-item">
                    <span class="commission-label">应返佣金</span>
                    <span class="commission-value commission-highlight">
                        @if($commissionRate > 0)
                            ¥{{ number_format($commissionAmount, 2) }}
                        @else
                            <span class="text-muted">-</span>
                        @endif
                    </span>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- 推广码信息 -->
<div class="card">
    <div class="card-header">
        <h3 class="card-title">推广码信息</h3>
    </div>
    <div class="card-body">
        <table class="table table-bordered">
            <tr>
                <th style="width: 150px;">推广码</th>
                <td>{{ $affiliateCode->code }}</td>
            </tr>
            <tr>
                <th>折扣类型</th>
                <td>
                    @if($affiliateCode->discount_type == 1)
                        固定金额减免
                    @else
                        百分比折扣
                    @endif
                </td>
            </tr>
            <tr>
                <th>折扣值</th>
                <td>
                    @if($affiliateCode->discount_type == 1)
                        {{ $affiliateCode->discount_value }} 元
                    @else
                        {{ $affiliateCode->discount_value }} %
                    @endif
                </td>
            </tr>
            <tr>
                <th>佣金比例</th>
                <td>
                    @if($commissionRate > 0)
                        {{ $commissionRate }}%
                    @else
                        <span class="text-muted">未设置</span>
                    @endif
                </td>
            </tr>
            <tr>
                <th>使用次数</th>
                <td>{{ $affiliateCode->use_count }}</td>
            </tr>
            <tr>
                <th>状态</th>
                <td>
                    @if($affiliateCode->is_open == 1)
                        <span class="badge badge-success">启用</span>
                    @else
                        <span class="badge badge-danger">禁用</span>
                    @endif
                </td>
            </tr>
            <tr>
                <th>备注</th>
                <td>{{ $affiliateCode->remark ?: '-' }}</td>
            </tr>
        </table>
    </div>
</div>

<!-- 筛选条件 -->
<div class="card">
    <div class="card-header">
        <h3 class="card-title">筛选查询</h3>
    </div>
    <div class="card-body">
        <!-- 快捷时间按钮 -->
        <div class="mb-3">
            <label class="mr-2">快捷选择：</label>
            <div class="btn-group" role="group">
                <button type="button" class="btn btn-sm btn-outline-primary quick-date-btn" data-range="this_week">本周</button>
                <button type="button" class="btn btn-sm btn-outline-primary quick-date-btn" data-range="last_week">上周</button>
                <button type="button" class="btn btn-sm btn-outline-primary quick-date-btn" data-range="last_month">上月</button>
            </div>
        </div>

        <form id="filterForm" method="GET" action="" class="form-inline">
            <div class="form-group mr-3 mb-2">
                <label class="mr-2">开始日期</label>
                <input type="date" name="start_date" id="startDate" class="form-control form-control-sm"
                       value="{{ $filters['start_date'] ?? '' }}">
            </div>
            <div class="form-group mr-3 mb-2">
                <label class="mr-2">结束日期</label>
                <input type="date" name="end_date" id="endDate" class="form-control form-control-sm"
                       value="{{ $filters['end_date'] ?? '' }}">
            </div>
            <div class="form-group mr-3 mb-2">
                <label class="mr-2">订单号</label>
                <input type="text" name="order_sn" class="form-control form-control-sm"
                       placeholder="订单号搜索" value="{{ $filters['order_sn'] ?? '' }}">
            </div>
            <div class="form-group mr-3 mb-2">
                <label class="mr-2">商品</label>
                <select name="goods_id" class="form-control form-control-sm">
                    <option value="">全部商品</option>
                    @foreach($goodsList as $gid => $gname)
                        <option value="{{ $gid }}" {{ ($filters['goods_id'] ?? '') == $gid ? 'selected' : '' }}>
                            {{ $gname }}
                        </option>
                    @endforeach
                </select>
            </div>
            <div class="form-group mb-2">
                <button type="submit" class="btn btn-primary btn-sm mr-2">
                    <i class="feather icon-search"></i> 查询
                </button>
                <a href="{{ request()->url() }}" class="btn btn-secondary btn-sm">
                    <i class="feather icon-refresh-cw"></i> 重置
                </a>
            </div>
        </form>
    </div>
</div>

<!-- 涉及商品 -->
@if(count($stats['goods_list']) > 0)
<div class="card">
    <div class="card-header">
        <h3 class="card-title">涉及商品 (当前筛选结果)</h3>
    </div>
    <div class="card-body">
        <ul class="list-group list-group-horizontal flex-wrap">
            @foreach($stats['goods_list'] as $goodsName)
                <li class="list-group-item">{{ $goodsName }}</li>
            @endforeach
        </ul>
    </div>
</div>
@endif

<!-- 订单明细 -->
<div class="card">
    <div class="card-header">
        <h3 class="card-title">订单明细</h3>
    </div>
    <div class="card-body">
        @if($orders->count() > 0)
        <table class="table table-bordered table-striped">
            <thead>
                <tr>
                    <th>订单号</th>
                    <th>商品名称</th>
                    <th>订单总价</th>
                    <th>折扣金额</th>
                    <th>实付金额</th>
                    <th>下单时间</th>
                </tr>
            </thead>
            <tbody>
                @foreach($orders as $order)
                <tr>
                    <td>{{ $order->order_sn }}</td>
                    <td>{{ $order->goods->gd_name ?? '-' }}</td>
                    <td>{{ number_format($order->total_price, 2) }}</td>
                    <td>{{ number_format($order->affiliate_discount_price, 2) }}</td>
                    <td>{{ number_format($order->actual_price, 2) }}</td>
                    <td>{{ $order->created_at }}</td>
                </tr>
                @endforeach
            </tbody>
        </table>
        @else
        <div class="text-center text-muted py-4">
            <i class="feather icon-inbox" style="font-size: 48px;"></i>
            <p class="mt-2">暂无订单数据</p>
        </div>
        @endif
    </div>
</div>

<style>
.small-box {
    border-radius: 0.25rem;
    box-shadow: 0 0 1px rgba(0,0,0,.125), 0 1px 3px rgba(0,0,0,.2);
    display: block;
    margin-bottom: 20px;
    position: relative;
}
.small-box > .inner {
    padding: 10px;
}
.small-box h3 {
    font-size: 2.2rem;
    font-weight: 700;
    margin: 0 0 10px 0;
    padding: 0;
    white-space: nowrap;
}
.small-box p {
    font-size: 1rem;
    margin-bottom: 0;
}
.small-box > .icon {
    color: rgba(0,0,0,.15);
    z-index: 0;
    font-size: 70px;
    position: absolute;
    right: 15px;
    top: 15px;
    transition: all .3s linear;
}
.bg-info {
    background-color: #17a2b8 !important;
    color: #fff;
}
.bg-success {
    background-color: #28a745 !important;
    color: #fff;
}
.bg-warning {
    background-color: #ffc107 !important;
    color: #212529;
}
.bg-secondary {
    background-color: #6c757d !important;
    color: #fff;
}
/* 佣金结算卡片样式 */
.commission-item {
    text-align: center;
    padding: 10px 0;
}
.commission-label {
    display: block;
    font-size: 0.85rem;
    color: #6c757d;
    margin-bottom: 6px;
}
.commission-value {
    display: block;
    font-size: 1.25rem;
    font-weight: 600;
    color: #333;
}
.commission-highlight {
    color: #dc3545;
    font-size: 1.5rem;
}
/* 快捷按钮选中态 */
.quick-date-btn.active {
    background-color: #007bff;
    color: #fff;
    border-color: #007bff;
}
</style>

<script>
document.addEventListener('DOMContentLoaded', function() {
    var startInput = document.getElementById('startDate');
    var endInput = document.getElementById('endDate');
    var form = document.getElementById('filterForm');
    var buttons = document.querySelectorAll('.quick-date-btn');

    /**
     * 格式化日期为 YYYY-MM-DD
     */
    function formatDate(date) {
        var y = date.getFullYear();
        var m = String(date.getMonth() + 1).padStart(2, '0');
        var d = String(date.getDate()).padStart(2, '0');
        return y + '-' + m + '-' + d;
    }

    /**
     * 根据快捷类型计算日期范围
     * this_week: 本周一 ~ 本周日
     * last_week: 上周一 ~ 上周日
     * last_month: 上月1号 ~ 上月最后一天
     */
    function getDateRange(range) {
        var now = new Date();
        var day = now.getDay() || 7; // 周日为7
        var start, end;

        if (range === 'this_week') {
            start = new Date(now);
            start.setDate(now.getDate() - day + 1); // 本周一
            end = new Date(start);
            end.setDate(start.getDate() + 6); // 本周日
        } else if (range === 'last_week') {
            start = new Date(now);
            start.setDate(now.getDate() - day - 6); // 上周一
            end = new Date(start);
            end.setDate(start.getDate() + 6); // 上周日
        } else if (range === 'last_month') {
            start = new Date(now.getFullYear(), now.getMonth() - 1, 1); // 上月1号
            end = new Date(now.getFullYear(), now.getMonth(), 0); // 上月最后一天
        }

        return { start: formatDate(start), end: formatDate(end) };
    }

    // 绑定快捷按钮点击事件
    buttons.forEach(function(btn) {
        btn.addEventListener('click', function() {
            var range = this.getAttribute('data-range');
            var dates = getDateRange(range);

            // 填入日期
            startInput.value = dates.start;
            endInput.value = dates.end;

            // 高亮当前按钮
            buttons.forEach(function(b) { b.classList.remove('active'); });
            this.classList.add('active');

            // 自动提交
            form.submit();
        });
    });

    // 页面加载时，根据当前日期回显按钮高亮
    var currentStart = startInput.value;
    var currentEnd = endInput.value;
    if (currentStart && currentEnd) {
        ['this_week', 'last_week', 'last_month'].forEach(function(range) {
            var dates = getDateRange(range);
            if (dates.start === currentStart && dates.end === currentEnd) {
                document.querySelector('.quick-date-btn[data-range="' + range + '"]').classList.add('active');
            }
        });
    }
});
</script>
