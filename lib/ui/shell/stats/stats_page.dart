// 统计页 — DESIGN.md §8 + §21 + 票 04 + v1.2.0 票 07（区间系统）。
// 数据源只 watch providers 在 UI 层聚合（不新建 provider 层，与流水页同模式）。
// 环形图用显式圆弧路径（Canvas.drawArc），不用 dasharray（§8 明确要求）。
// 区间胶囊：默认只显 周/月，「编辑」弹层勾选加段（顺序固定，勾选持久化）；
// 周/月/季/年有分页条「← 当前区间标签 →」：箭头逐周期步进、只能落在有流水的
// 周期（当前周期特例：无流水也可停留），点标签弹列表倒序直达；
// 近7日/近30日/全部为滚动区间无分页。月→信封进度榜（仅当前月），其余→柱状；
// 粒度：周/近7日/近30日/历史月按日，季/年/全部按月；日历按钮自选区间保留。
// 统计一律日历口径（domain/stats_range.dart），与账本预算周期类型完全解耦（ADR-0013）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../domain/stats_range.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../common/format.dart';
import '../../copy.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  // 当前范围：默认月；胶囊段由偏好勾选决定（周/月恒显），自选区间经页头日历按钮进入
  StatsRange _range = StatsRange.month;

  // 分页锚点（票 07）：所看周期的锚点；null = 当前周期（规范形——步进落回
  // 当前周期时也归 null，使「当前周期」只有一种表示）
  DateTime? _anchor;

  // 自选区间的起止日（含首尾；仅自选范围使用）
  DateTime? _customStart;
  DateTime? _customEnd;

  // ── 区间与聚合 ──

  // 周期类区间看历史周期时用锚点做区间参考日；滚动/自由区间恒用 now
  DateTime _referenceDay(DateTime now) =>
      isPeriodRange(_range) && _anchor != null ? _anchor! : now;

  // 页头副行/分页条/卡片标题/直达列表共用的区间标签（[day] = 区间参考日）
  String _rangeLabel(DateTime day) {
    switch (_range) {
      case StatsRange.month:
        return '${day.year}年${day.month}月';
      case StatsRange.quarter:
        return '${day.year}年第${((day.month - 1) ~/ 3) + 1}季度';
      case StatsRange.year:
        return '${day.year}年';
      case StatsRange.all:
        return '全部时间';
      case StatsRange.week:
      case StatsRange.last7:
      case StatsRange.last30:
      case StatsRange.custom:
        final (start, end) = _bounds(day, null);
        final lastDay = end.subtract(const Duration(days: 1));
        // 跨年时起端带年份，同年只写月日
        final crossYear = start.year != lastDay.year;
        final s = crossYear
            ? '${start.year}年${start.month}月${start.day}日'
            : '${start.month}月${start.day}日';
        return '$s – ${lastDay.month}月${lastDay.day}日';
    }
  }

  // 当前范围 → 数据区间 [start, end)。周期类区间参考日取所看周期（锚点），
  // 滚动/自由区间恒用传入日；[allStart] 仅「全部时间」用（最早流水时刻）。
  (DateTime, DateTime) _bounds(DateTime day, DateTime? allStart) => statsBounds(
    _range,
    isPeriodRange(_range) && _anchor != null ? _anchor! : day,
    customStart: _customStart,
    customEnd: _customEnd,
    allStart: allStart,
  );

  // 分页条标签（周期类区间专用；与 build 的 now 同源，避免午夜跨日不一致）
  String _pagerLabel(DateTime now) => _rangeLabel(_anchor ?? now);

  // 步进一个周期（±1）：不可达（目标无流水且非当前周期）时静默不动
  void _stepPeriod(int steps) {
    final now = DateTime.now();
    final withTxns = _anchorsWithTxns();
    // 锚点恒取周期首日（now 不是锚点，直接平移周区间会落到非周一）
    final from = _anchor ?? periodAnchorOf(_range, now);
    if (!periodStepAllowed(_range, from, steps, withTxns, now)) return;
    final target = shiftPeriod(_range, from, steps);
    setState(() {
      // 落回当前周期 → 归 null（规范形，让总览卡走账面值分支）
      _anchor = target == periodAnchorOf(_range, now) ? null : target;
    });
  }

  // 有流水的周期锚点集（按当前范围；票 07「有流水的区间」判定）
  Set<DateTime> _anchorsWithTxns() {
    final txns = ref.read(txnsProvider).value ?? const <Txn>[];
    return periodAnchorsWithTxns(_range, txns.map((t) => t.at));
  }

  // 点标签：底部列表按时间倒序列出有流水的周期，点选直达
  Future<void> _openPeriodPicker() async {
    final now = DateTime.now();
    // 标签在页面侧生成（与分页条同口径，周标签跨年带年份）
    final entries = _anchorsWithTxns().toList()..sort((a, b) => b.compareTo(a));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: T.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(T.radiusSheet),
        ),
      ),
      builder: (_) => _PeriodPickerSheet(
        entries: [for (final a in entries) (a, _rangeLabel(a))],
        range: _range,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _anchor = picked == periodAnchorOf(_range, now) ? null : picked;
    });
  }

  // 胶囊「编辑」：勾选加入可选段的底部弹层（勾选即持久化，就地生效）
  Future<void> _editSegments() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.surface,
      isScrollControlled: true, // 五段 + 按钮在小屏上会顶到默认 9/16 高度上限
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(T.radiusSheet),
        ),
      ),
      builder: (_) => const _SegmentEditSheet(),
    );
    if (!mounted) return;
    // 当前段被勾掉时回落到恒显的「月」（周/月不可勾掉，月一定在）
    if (!ref.read(statsSegmentsProvider).contains(_range)) {
      setState(() {
        _range = StatsRange.month;
        _anchor = null;
      });
    }
  }

  // 页头日历按钮：弹出日历自选起止日，任意区间（选定后切到自选范围）
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _range == StatsRange.custom && _customStart != null
        ? DateTimeRange(start: _customStart!, end: _customEnd ?? _customStart!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      currentDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customStart = picked.start;
      _customEnd = picked.end;
      _range = StatsRange.custom;
      _anchor = null; // 自选无分页，清掉周期锚点
    });
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(txnsProvider).value ?? const <Txn>[];
    final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
    // 胶囊段偏好（票 07）：勾选的段按固定顺序渲染
    final segments = ref.watch(statsSegmentsProvider);
    // 当前账本货币符号（ADR-0017）：各卡金额共用
    final symbol = ref.watch(currencySymbolProvider);
    final now = DateTime.now();
    // 最早流水时刻（「全部时间」的起点用；无流水为 null 走兜底）
    final earliestTxnAt = txns.isEmpty
        ? null
        : txns.map((t) => t.at).reduce((a, b) => a.isBefore(b) ? a : b);
    final (start, end) = _bounds(now, earliestTxnAt);
    final lastDay = end.subtract(const Duration(days: 1)); // 最后一个覆盖到的日历日
    final today = DateTime(now.year, now.month, now.day);
    // 区间标签参考日：周期类区间看历史周期时用锚点
    final labelDay = _referenceDay(now);
    final rangeLabelText = _rangeLabel(labelDay);
    // 分页可达性（票 07）：周/月/季/年才有分页条
    final showPager = isPeriodRange(_range);
    var canLeft = false;
    var canRight = false;
    if (showPager) {
      final from = _anchor ?? periodAnchorOf(_range, now);
      final withTxns = _anchorsWithTxns();
      canLeft = periodStepAllowed(_range, from, -1, withTxns, now);
      canRight = periodStepAllowed(_range, from, 1, withTxns, now);
    }
    // 是否停在当前周期（规范形：_anchor == null ⇔ 当前周期）
    final isCurrentPeriod = _anchor == null;
    final isCurrentMonth = _range == StatsRange.month && isCurrentPeriod;

    // ── 区间聚合（只看 [start, end) 内的交易；转移零和不计收支，不变量③）──
    var usedInRange = 0.0; // 支出合计
    var assignedNet = 0.0; // 净分配（待规划 → 信封 为正，退回为负）
    final byEnv = <String, double>{}; // 信封 → 支出
    final byDay = <DateTime, double>{}; // 日 0 点 → 支出（分日柱状用）
    final byMonth = <DateTime, double>{}; // 月 1 号 → 支出（分月柱状用）
    for (final t in txns) {
      if (t.at.isBefore(start) || !t.at.isBefore(end)) continue;
      switch (t.type) {
        case TxType.expense:
          usedInRange = round2(usedInRange + t.amount);
          final id = t.envelopeId;
          if (id != null) {
            byEnv[id] = round2((byEnv[id] ?? 0) + t.amount);
          }
          final day = DateTime(t.at.year, t.at.month, t.at.day);
          byDay[day] = round2((byDay[day] ?? 0) + t.amount);
          final month = DateTime(t.at.year, t.at.month);
          byMonth[month] = round2((byMonth[month] ?? 0) + t.amount);
        case TxType.income:
          break; // 收入只在总览的备用口径里出现，v1 总览不展示
        case TxType.transfer:
          if (t.fromId == kToBudget) assignedNet += t.amount;
          if (t.toId == kToBudget) assignedNet -= t.amount;
        case TxType.refund:
          // 结转退回（ADR-0016）零和且是系统行为：不计入任何收支聚合与图表
          break;
      }
    }
    assignedNet = round2(assignedNet);

    // ── 总览三数（当前月用账面值=结转后的本月；历史周期与其余区间用区间聚合）──
    final plannedAccount = round2(envelopes.fold(0.0, (s, e) => s + e.planned));
    final usedAccount = round2(envelopes.fold(0.0, (s, e) => s + e.used));
    final planned = isCurrentMonth ? plannedAccount : assignedNet;
    final used = isCurrentMonth ? usedAccount : usedInRange;
    final remain = round2(planned - used);
    final pct = planned > 0 ? (used / planned).clamp(0.0, 1.0) : 0.0;

    // 距区间末还剩几天（自选历史区间不为负）
    final daysLeft = math.max(0, end.difference(now).inDays);

    // ── 第三卡柱列：当前月=进度榜；历史月/周/近7日/近30日分日；季/年/全部分月 ──
    List<_TrendCol>? trendCols;
    var trendKind = '分月柱状';
    if (!isCurrentMonth) {
      final useDaily = dailyBars(_range, start, lastDay);
      if (useDaily) {
        trendKind = '分日柱状';
        final days = dailyBuckets(start, lastDay);
        final cols = <_TrendCol>[];
        for (var i = 0; i < days.length; i++) {
          final d = days[i];
          final isToday = d == today;
          // 短区间逐日标注；自选长区间稀疏标注（每 7 根 + 今天 + 最后一根）
          final showLabel =
              days.length <= 10 ||
              i % 7 == 0 ||
              isToday ||
              i == days.length - 1;
          cols.add(
            _TrendCol(
              label: _range == StatsRange.week
                  ? const ['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]
                  : '${d.day}日',
              value: byDay[d] ?? 0,
              isCurrent: isToday,
              // 分日柱不画灰桩：未来天与零值天同为浅黄空桩（票 04 原文「其余 #FFD98A」）
              future: false,
              showLabel: showLabel,
            ),
          );
        }
        trendCols = cols;
      } else {
        trendKind = '分月柱状';
        final months = monthlyBuckets(start, lastDay);
        final curMonth = DateTime(now.year, now.month);
        final multiYear = months.first.year != months.last.year;
        final cols = <_TrendCol>[];
        for (var i = 0; i < months.length; i++) {
          final m = months[i];
          // 标注密度：年视图沿用 §21 隔月显示（当月恒显示）；
          // 其余分月（季/全部/自选跨月）全显，超长区间每 3 根 + 当月
          final showLabel = _range == StatsRange.year && isCurrentPeriod
              ? (m.month.isOdd || m == curMonth)
              : (months.length <= 15 || i % 3 == 0 || m == curMonth);
          // 跨年用「年/月」短标避免重名月份
          cols.add(
            _TrendCol(
              label: multiYear ? '${m.year % 100}/${m.month}' : '${m.month}月',
              value: byMonth[m] ?? 0,
              isCurrent: m == curMonth,
              future: m.isAfter(curMonth),
              showLabel: showLabel,
            ),
          );
        }
        trendCols = cols;
      }
    }

    // 柱状卡标题：当前周期用描述性标题，历史周期直接用区间标签（分页条同源）
    final trendTitle = switch (_range) {
      StatsRange.week => isCurrentPeriod ? '周 · 本周 7 天' : rangeLabelText,
      StatsRange.last7 => '近7日 · 滚动 7 天',
      StatsRange.last30 => '近30日 · 滚动 30 天',
      StatsRange.quarter => isCurrentPeriod ? '季 · 本季 3 个月' : rangeLabelText,
      StatsRange.year => isCurrentPeriod ? '年 · 12 个月' : rangeLabelText,
      StatsRange.all => '全部时间',
      StatsRange.month => rangeLabelText, // 历史月（当前月走进度榜，不在此）
      StatsRange.custom => '自定义区间',
    };

    // 总览卡标题
    final overviewTitle = switch (_range) {
      StatsRange.month =>
        isCurrentPeriod ? '本月预算' : '${labelDay.year}年${labelDay.month}月预算',
      StatsRange.quarter => isCurrentPeriod ? '本季度预算' : '区间预算',
      StatsRange.year => isCurrentPeriod ? '本年预算' : '区间预算',
      StatsRange.week => isCurrentPeriod ? '本周预算' : '区间预算',
      StatsRange.last7 => '近7日预算',
      StatsRange.last30 => '近30日预算',
      StatsRange.all => '全部预算',
      StatsRange.custom => '区间预算',
    };

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // 页头
            _Header(
              rangeLabel: rangeLabelText,
              percent: pct,
              calendarActive: _range == StatsRange.custom,
              onCalendar: _pickCustomRange,
            ),
            const SizedBox(height: 14),
            // 范围切换（段由偏好勾选决定，周/月恒显；尾部「编辑」管理段，票 07）
            _RangeSwitch(
              segments: segments,
              current: _range,
              onChanged: (r) => setState(() {
                _range = r;
                _anchor = null; // 换区间回到当前周期（各区间周期空间独立）
              }),
              onEdit: _editSegments,
            ),
            // 分页条（票 07）：周/月/季/年才显示；滚动/自选区间无分页
            if (showPager) ...[
              const SizedBox(height: 10),
              _PeriodPager(
                label: _pagerLabel(now),
                canLeft: canLeft,
                canRight: canRight,
                onLeft: () => _stepPeriod(-1),
                onRight: () => _stepPeriod(1),
                onLabel: _openPeriodPicker,
              ),
            ],
            const SizedBox(height: 14),
            // 本期总览（暖黄卡）
            _OverviewCard(
              title: overviewTitle,
              daysLeft: daysLeft,
              planned: planned,
              used: used,
              remain: remain,
              percent: pct,
              symbol: symbol,
            ),
            const SizedBox(height: 14),
            // 支出构成（白卡：图例 + 环形），随区间联动
            _ExpenseCard(
              envelopes: envelopes,
              byEnv: byEnv,
              usedTotal: used,
              symbol: symbol,
            ),
            const SizedBox(height: 14),
            // 第三卡：当前月 = 信封进度榜；其余（含历史月）= 柱状（§21 + 票 04/07）
            if (isCurrentMonth)
              _ProgressCard(envelopes: envelopes, symbol: symbol)
            else
              _TrendCard(
                title: trendTitle,
                kind: trendKind,
                cols: trendCols!,
                usedTotal: used,
                symbol: symbol,
              ),
          ],
        ),
      ),
    );
  }
}

// ── 页头 ─────────────────────────────────────

/// 页头：左「统计」+ 副行区间与执行率；右 36dp 圆形日历按钮（自选区间，票 04）
class _Header extends StatelessWidget {
  const _Header({
    required this.rangeLabel,
    required this.percent,
    required this.calendarActive,
    required this.onCalendar,
  });

  final String rangeLabel;
  final double percent;

  // 自选范围激活时按钮转黄实心提示
  final bool calendarActive;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '统计',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text(
                '$rangeLabel · 预算执行 ${(percent * 100).round()}%',
                style: const TextStyle(
                  fontSize: T.typeXs,
                  height: 15 / 11,
                  color: T.textTertiary,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: calendarActive ? T.primary : T.primarySoft,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onCalendar,
                child: Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: calendarActive ? T.textPrimary : T.primaryDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 范围切换（可定制胶囊 + 编辑入口，§8 单段式 + 票 04/07）──

// 胶囊段文案（短标签，固定顺序见 domain kStatsSegmentOrder）
const _segmentLabels = {
  StatsRange.week: '周',
  StatsRange.month: '月',
  StatsRange.quarter: '季',
  StatsRange.year: '年',
  StatsRange.last7: '近7日',
  StatsRange.last30: '近30日',
  StatsRange.all: '全部',
};

/// 段由偏好勾选决定（周/月恒显），选中段是 #FFC72C 圆角实心块；
/// 尾部「编辑」打开勾选弹层（票 07）。自选区间不在胶囊里（从页头日历按钮进入）。
class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({
    required this.segments,
    required this.current,
    required this.onChanged,
    required this.onEdit,
  });

  // 启用的段（已按固定顺序排好）
  final List<StatsRange> segments;
  final StatsRange current;
  final ValueChanged<StatsRange> onChanged;

  // 打开段管理弹层
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: T.surfaceSubtle,
        borderRadius: BorderRadius.circular(T.radiusPill),
      ),
      child: Row(
        children: [
          for (final r in segments)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == current ? T.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    _segmentLabels[r]!,
                    style: TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: r == current
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: r == current ? T.textPrimary : T.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          // 尾部编辑入口：勾选管理胶囊段（票 07）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '编辑',
                style: TextStyle(
                  fontSize: T.typeXs,
                  fontWeight: FontWeight.w500,
                  color: T.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 周期分页条（票 07）──────────────────────────

/// 「← 当前区间标签 →」：箭头逐周期步进（不可达时置灰），
/// 点标签弹底部列表直达有流水的周期。仅周/月/季/年显示。
class _PeriodPager extends StatelessWidget {
  const _PeriodPager({
    required this.label,
    required this.canLeft,
    required this.canRight,
    required this.onLeft,
    required this.onRight,
    required this.onLabel,
  });

  final String label;
  final bool canLeft;
  final bool canRight;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onLabel;

  // 步进箭头：36dp 圆角块，不可达时置灰
  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) => SizedBox(
    width: 36,
    height: 36,
    child: Material(
      color: T.surfaceSubtle,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? T.primaryDeep : const Color(0xFFCCC4B8),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, canLeft, onLeft),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onLabel,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, canRight, onRight),
        ],
      ),
    );
  }
}

// ── 胶囊段管理弹层（票 07）───────────────────────

/// 勾选加入胶囊的可选段（季/年/近7日/近30日/全部时间；周/月固定显示不在此列）。
/// 勾选即写偏好（就地生效并持久化），「完成」关闭。
class _SegmentEditSheet extends ConsumerWidget {
  const _SegmentEditSheet();

  // 弹层行文案：胶囊短标 + 全称（近7日胶囊里叫「近7日」，行里给全称更清楚）
  static const _rowLabels = {
    StatsRange.quarter: '季 · 自然季度',
    StatsRange.year: '年 · 自然年',
    StatsRange.last7: '近7日 · 滚动 7 天',
    StatsRange.last30: '近30日 · 滚动 30 天',
    StatsRange.all: '全部时间',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(statsSegmentsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        // 小屏保险：内容整体可滚（正常高度下滚不动）
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                statsSegmentSheetTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                statsSegmentEditHint,
                style: const TextStyle(
                  fontSize: T.typeXs,
                  color: T.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              for (final r in kStatsOptionalSegments)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      ref.read(statsSegmentsProvider.notifier).toggle(r),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Icon(
                          enabled.contains(r)
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 20,
                          color: enabled.contains(r)
                              ? T.primaryDeep
                              : T.textTertiary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _rowLabels[r]!,
                          style: const TextStyle(
                            fontSize: T.typeBase,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: T.primary,
                    foregroundColor: T.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(T.radiusKey),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '完成',
                    style: TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 周期直达列表弹层（票 07）─────────────────────

/// 有流水的周期倒序列表（点分页条标签弹出）；点选一条直达该周期。
/// [entries] = (周期锚点, 标签)，标签由页面用 `_rangeLabel` 生成（与分页条同口径）。
class _PeriodPickerSheet extends StatelessWidget {
  const _PeriodPickerSheet({required this.entries, required this.range});

  // 有流水的周期（已按时间倒序排好）
  final List<(DateTime, String)> entries;

  // 周期类区间（点选回传锚点用）
  final StatsRange range;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              statsPeriodSheetTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  statsPeriodPickerEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    color: T.textTertiary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final (anchor, label) = entries[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).pop(anchor),
                      child: SizedBox(
                        height: 44,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: T.typeBase,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 本期总览（暖黄卡）──

/// 暖黄卡：标题 + 还剩天数 + 三数并排 + 5dp 执行进度条
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.title,
    required this.daysLeft,
    required this.planned,
    required this.used,
    required this.remain,
    required this.percent,
    required this.symbol,
  });

  final String title;
  final int daysLeft;
  final double planned;
  final double used;
  final double remain;
  final double percent;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.primarySoft,
        borderRadius: BorderRadius.circular(T.radiusCardLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w600,
                  color: T.primaryDeep,
                ),
              ),
              const Spacer(),
              Text(
                '还剩 $daysLeft 天',
                style: const TextStyle(fontSize: T.typeXs, color: T.primaryMid),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 三数并排
          Row(
            children: [
              for (final (label, v) in [
                ('已规划', planned),
                ('已使用', used),
                ('剩余', remain),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$symbol${money(v)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: T.typeXs,
                          color: T.primaryMid,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 执行进度条（5dp：28% 黄底 + 黄实条）
          ClipRRect(
            borderRadius: BorderRadius.circular(T.radiusBar),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(color: T.primary.withValues(alpha: 0.28)),
                  FractionallySizedBox(
                    widthFactor: percent,
                    child: Container(color: T.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 支出构成（白卡）──

/// 一段环形/图例的描述
class _Seg {
  const _Seg({
    required this.color,
    required this.value,
    required this.label,
    this.red = false,
  });
  final Color color;
  final double value;
  final String label;

  // 透支行：图例与环段转红（§8 透支必须可见）
  final bool red;
}

/// 支出构成卡：左图例 5 行（前 4 信封 + 其他），右 108dp 环形
class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.envelopes,
    required this.byEnv,
    required this.usedTotal,
    required this.symbol,
  });

  final List<Envelope> envelopes;
  final Map<String, double> byEnv;
  final double usedTotal;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final envById = {for (final e in envelopes) e.id: e};
    // 按支出降序取前 4（只在用信封）；第 5 名起与停用信封的支出并入「其他」
    final sorted = byEnv.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top4 = <MapEntry<String, double>>[];
    var restCount = 0;
    var restValue = 0.0;
    for (final e in sorted) {
      if (top4.length < 4 && envById.containsKey(e.key)) {
        top4.add(e);
      } else {
        restCount++;
        restValue = round2(restValue + e.value);
      }
    }

    final segs = <_Seg>[];
    for (final e in top4) {
      final env = envById[e.key]!;
      // 透支信封整段转红（§8：超支必须可见，不许并进别的段）
      final overdraft = env.available < 0;
      segs.add(
        _Seg(
          color: overdraft ? T.overspend : envelopeColorById(env.color).main,
          value: e.value,
          label: env.name,
          red: overdraft,
        ),
      );
    }
    if (restCount > 0) {
      segs.add(
        _Seg(
          color: const Color(0xFFB0A79A),
          value: restValue,
          label: '其他 $restCount 个信封',
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radiusCardLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '支出构成',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '按信封 · 已使用 $symbol${money(usedTotal)}',
                style: const TextStyle(
                  fontSize: T.typeXs,
                  color: T.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (segs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                emptyExpenseTitle,
                style: TextStyle(fontSize: T.typeBase, color: T.textTertiary),
              ),
            )
          else
            Row(
              children: [
                // 图例（5 行）
                Expanded(
                  child: Column(
                    children: [
                      for (final s in segs)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: s.color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: T.typeBase,
                                    fontWeight: FontWeight.w500,
                                    color: s.red ? T.overspend : T.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '$symbol${money(s.value)}',
                                style: TextStyle(
                                  fontSize: T.typeBase,
                                  color: s.red ? T.overspend : T.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 108dp 环形图（显式圆弧路径）
                SizedBox(
                  width: 108,
                  height: 108,
                  child: CustomPaint(painter: _RingPainter(segs: segs)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 环形图画笔 — 显式 drawArc 分段（顶部起笔顺时针，段间留细缝）
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.segs});

  final List<_Seg> segs;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 24.0;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final total = segs.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) {
      // 没有数据：整环灰占位
      paint.color = const Color(0xFFE3DCD0);
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      return;
    }

    const gap = 0.035; // 段间白缝（弧度）
    var angle = -math.pi / 2; // 顶部起笔
    for (final s in segs) {
      final sweep = s.value / total * math.pi * 2;
      final drawn = math.max(sweep - (segs.length > 1 ? gap : 0), 0.02);
      paint.color = s.color;
      canvas.drawArc(rect, angle + gap / 2, drawn, false, paint);
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.segs.length != segs.length;
}

// ── 信封进度（月视图）──

/// 信封进度卡：已使用前 5 名，条长 = 已使用/已规划；透支铺满转红加「缺 ¥X」
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.envelopes, required this.symbol});

  final List<Envelope> envelopes;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final rows = [...envelopes]..sort((a, b) => b.used.compareTo(a.used));
    final top5 = rows.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radiusCardLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '信封进度',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              const Text(
                '已使用 / 已规划 · 取前 5',
                style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (top5.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                emptyEnvelopesForStats,
                style: TextStyle(fontSize: T.typeBase, color: T.textTertiary),
              ),
            )
          else
            for (final e in top5)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: _ProgressRow(envelope: e, symbol: symbol),
              ),
        ],
      ),
    );
  }
}

/// 单行：名称 + 8dp 进度槽 + 金额（透支整行转红并带「缺 X」）
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.envelope, required this.symbol});

  final Envelope envelope;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final e = envelope;
    final color = envelopeColorById(e.color);
    final over = e.available < 0;
    // 条长比例：透支铺满转红（§8）
    final ratio = over
        ? 1.0
        : (e.planned > 0 ? (e.used / e.planned).clamp(0.0, 1.0) : 0.0);

    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: T.typeBase,
              fontWeight: FontWeight.w500,
              color: over ? T.overspend : T.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(
                    color: over
                        ? T.overspend.withValues(alpha: 0.18)
                        : color.withAlpha(0.18),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: over ? T.overspend : color.main),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 金额列：透支两行（已使用 + 缺口），普通一行
        SizedBox(
          width: 76,
          child: over
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$symbol${money(e.used)}',
                      style: const TextStyle(
                        fontSize: T.typeBase,
                        fontWeight: FontWeight.w600,
                        color: T.overspend,
                      ),
                    ),
                    Text(
                      '缺 $symbol${money(-e.available)}',
                      style: const TextStyle(
                        fontSize: T.typeXs,
                        color: T.overspend,
                      ),
                    ),
                  ],
                )
              : Text(
                  '$symbol${money(e.used)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    color: T.textSecondary,
                  ),
                ),
        ),
      ],
    );
  }
}

// ── 支出趋势（周/近7日/季/年/自选，§21 + 票 04）──

/// 一列柱的描述：标注 / 金额 / 当期（今天或当月）实色 / 未来灰桩 / 是否显示标注
class _TrendCol {
  const _TrendCol({
    required this.label,
    required this.value,
    required this.isCurrent,
    required this.future,
    required this.showLabel,
  });

  // 底部标注文案（'17日' / '一' / '9月'）
  final String label;

  // 该柱金额
  final double value;

  // 当期（分日=今天，分月=当月）：实色 #FFC72C + 标注加粗
  final bool isCurrent;

  // 未到的月：6dp 灰短柱（§21：留空但不能不画；分日不用灰桩）
  final bool future;

  // 是否显示底部标注（窄柱稀疏标注防溢出）
  final bool showLabel;
}

/// 柱状卡：由 cols 描述驱动（分日/分月均可）；当期实色 #FFC72C、
/// 其余浅黄 #FFD98A、未来 6dp 灰短柱（§21：留空但不能不画）
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.kind,
    required this.cols,
    required this.usedTotal,
    required this.symbol,
  });

  final String title;
  final String kind; // '分日柱状' / '分月柱状'
  final List<_TrendCol> cols;
  final double usedTotal;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final maxV = cols.fold(0.0, (m, c) => math.max(m, c.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radiusCardLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$kind · 已使用 $symbol${money(usedTotal)}',
                style: const TextStyle(
                  fontSize: T.typeXs,
                  color: T.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in cols) _TrendColumn(col: c, maxV: maxV),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一列柱：标注（当期加粗深色）+ 柱体（底部对齐）
class _TrendColumn extends StatelessWidget {
  const _TrendColumn({required this.col, required this.maxV});

  final _TrendCol col;
  final double maxV;

  @override
  Widget build(BuildContext context) {
    // 柱高：按最大值比例；未来固定 6dp 灰；零值 2dp
    final barH = col.future
        ? 6.0
        : col.value <= 0
        ? 2.0
        : (maxV <= 0 ? 2.0 : (col.value / maxV * 96).clamp(8.0, 96.0));
    final barColor = col.future
        ? const Color(0xFFE3DCD0)
        : col.isCurrent
        ? T.primary
        : const Color(0xFFFFD98A);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            // 标注槽：FittedBox 缩放防窄列溢出（31 根柱时列宽只有 ~9px）
            SizedBox(
              height: 14,
              child: col.showLabel
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        col.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          color: col.isCurrent ? T.textPrimary : T.textTertiary,
                          fontWeight: col.isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              height: barH,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(
                  col.future ? 2 : math.min(barH / 2, 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
