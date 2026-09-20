// 统计区间与聚合桶 — 纯日历口径（ADR-0013 的解耦原则）。
// 统计只认自然周 / 自然月 / 自然季 / 自然年 / 滚动 7 天 / 滚动 30 天 / 全部时间 /
// 自选区间，完全不读账本的预算周期类型；结转按周期边界走，统计按日历聚合，
// 互不干扰。周期分页（v1.2.0 票 07）的锚点/平移/可达判定也在这里保持纯函数可测。
import 'period_logic.dart' show dateOnly, monthStart, nextMonthStart;

/// 统计范围：月 / 季 / 年 / 周（周一起的自然周）/ 近7日（含今天的滚动 7 天）/
/// 近30日（含今天的滚动 30 天）/ 全部时间 / 自选区间。
/// 周/月/季/年为周期类区间（可分页步进）；近7日/近30日/全部/自选为滚动或自由区间（无分页）。
enum StatsRange { month, quarter, year, week, last7, last30, all, custom }

/// 胶囊段的固定顺序（票 07：不支持排序）——渲染与持久化解析都按它收敛
const List<StatsRange> kStatsSegmentOrder = [
  StatsRange.week,
  StatsRange.month,
  StatsRange.quarter,
  StatsRange.year,
  StatsRange.last7,
  StatsRange.last30,
  StatsRange.all,
];

/// 可勾选加入胶囊的段（周/月默认恒显、不可勾掉）
const List<StatsRange> kStatsOptionalSegments = [
  StatsRange.quarter,
  StatsRange.year,
  StatsRange.last7,
  StatsRange.last30,
  StatsRange.all,
];

/// 周期类区间（周/月/季/年）判定——只有这些有分页条
bool isPeriodRange(StatsRange r) =>
    r == StatsRange.week ||
    r == StatsRange.month ||
    r == StatsRange.quarter ||
    r == StatsRange.year;

/// [d] 所在自然周的周一 0 点（weekday：周一=1…周日=7，天数减法由 DateTime 归一化跨月）
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// [d] 所在周期的锚点（周期首日 0 点）。仅周期类区间（周/月/季/年）可调用。
DateTime periodAnchorOf(StatsRange r, DateTime d) {
  switch (r) {
    case StatsRange.week:
      return mondayOf(d);
    case StatsRange.month:
      return monthStart(d);
    case StatsRange.quarter:
      // 自然季：Q1=1–3 月，Q2=4–6 月，Q3=7–9 月，Q4=10–12 月
      return DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1);
    case StatsRange.year:
      return DateTime(d.year, 1);
    case StatsRange.last7:
    case StatsRange.last30:
    case StatsRange.all:
    case StatsRange.custom:
      throw ArgumentError('非周期类区间没有周期锚点: $r');
  }
}

/// 周期类区间：锚点所在周期 ± [steps] 期的锚点（steps 可负）。仅周期类区间可调用。
DateTime shiftPeriod(StatsRange r, DateTime anchor, int steps) {
  switch (r) {
    case StatsRange.week:
      // 锚点恒为周一 0 点，天数加减由 DateTime 归一化跨月/跨年
      return DateTime(anchor.year, anchor.month, anchor.day + 7 * steps);
    case StatsRange.month:
      return DateTime(anchor.year, anchor.month + steps);
    case StatsRange.quarter:
      return DateTime(anchor.year, anchor.month + 3 * steps);
    case StatsRange.year:
      return DateTime(anchor.year + steps, anchor.month);
    case StatsRange.last7:
    case StatsRange.last30:
    case StatsRange.all:
    case StatsRange.custom:
      throw ArgumentError('非周期类区间不可步进: $r');
  }
}

/// 有流水的周期锚点集：流水记账时间 → 所在周期锚点（票 07「有流水的区间」判定）。
/// 仅周期类区间可调用；由调用方传全量流水的 at（统计页本就内存过滤，不新建查询）。
Set<DateTime> periodAnchorsWithTxns(StatsRange r, Iterable<DateTime> ats) => {
  for (final at in ats) periodAnchorOf(r, at),
};

/// 从 [anchor] 步进 [steps] 期（±1）是否可达：
/// 目标周期有流水即可达；或目标是当前周期——当前周期即使暂无流水也可停留
/// （票 07：右边界 = max(当前周期, 最晚流水周期)，本判定与「目标有流水」
/// 合起来已隐含该边界——有流水的目标必不晚于最晚流水周期）。
bool periodStepAllowed(
  StatsRange r,
  DateTime anchor,
  int steps,
  Set<DateTime> withTxns,
  DateTime now,
) {
  final target = shiftPeriod(r, anchor, steps);
  return withTxns.contains(target) || target == periodAnchorOf(r, now);
}

/// 范围 → 数据区间 [start, end)（start 为 0 点，end 为Exclusive）。
/// 自选区间需传 [customStart]/[customEnd]；缺失时回落本月（防崩兜底）。
/// 全部时间需传 [allStart]（当前账本最早流水的记账时刻）；缺失时同样回落本月。
(DateTime, DateTime) statsBounds(
  StatsRange r,
  DateTime now, {
  DateTime? customStart,
  DateTime? customEnd,
  DateTime? allStart,
}) {
  switch (r) {
    case StatsRange.month:
      return (monthStart(now), nextMonthStart(now));
    case StatsRange.quarter:
      final qStart = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1);
      return (qStart, DateTime(qStart.year, qStart.month + 3));
    case StatsRange.year:
      return (DateTime(now.year, 1), DateTime(now.year + 1, 1));
    case StatsRange.week:
      final mon = mondayOf(now);
      return (mon, mon.add(const Duration(days: 7)));
    case StatsRange.last7:
      // 含今天的滚动 7 天：起点 = 今天 − 6 天，终点 = 明天 0 点（Exclusive）
      final today = dateOnly(now);
      return (
        today.subtract(const Duration(days: 6)),
        today.add(const Duration(days: 1)),
      );
    case StatsRange.last30:
      // 含今天的滚动 30 天：起点 = 今天 − 29 天，终点 = 明天 0 点（Exclusive）
      final today = dateOnly(now);
      return (
        today.subtract(const Duration(days: 29)),
        today.add(const Duration(days: 1)),
      );
    case StatsRange.all:
      // 全部时间：起点 = 最早流水日 0 点，终点 = 明天 0 点（覆盖到今天）
      if (allStart == null) {
        return (monthStart(now), nextMonthStart(now));
      }
      return (dateOnly(allStart), dateOnly(now).add(const Duration(days: 1)));
    case StatsRange.custom:
      if (customStart == null || customEnd == null) {
        return (monthStart(now), nextMonthStart(now));
      }
      final s = dateOnly(customStart);
      final e = dateOnly(customEnd);
      // 起止颠倒时交换，保证区间恒有效
      return e.isBefore(s)
          ? (e, s.add(const Duration(days: 1)))
          : (s, e.add(const Duration(days: 1)));
  }
}

/// 第三卡柱状粒度：按日 = true。周/近7日/近30日恒按日；季/年/全部按月；
/// 自选 ≤31 天按日（>31 按月，票 04 现状）；历史月（当前月走进度榜，不会到此）
/// 单月 ≤31 天按日。
bool dailyBars(StatsRange r, DateTime start, DateTime lastDay) => switch (r) {
  StatsRange.week ||
  StatsRange.last7 ||
  StatsRange.last30 ||
  StatsRange.month => true,
  StatsRange.quarter || StatsRange.year || StatsRange.all => false,
  StatsRange.custom => spanDays(start, lastDay) <= 31,
};

/// 自选区间天数（含首尾）。聚合方式分界：≤31 天按日出柱，>31 天按月聚合
int spanDays(DateTime start, DateTime end) =>
    dateOnly(end).difference(dateOnly(start)).inDays + 1;

/// 区间内的日桶序列（每天 0 点，升序；[end] 当天含在内）
List<DateTime> dailyBuckets(DateTime start, DateTime end) {
  final s = dateOnly(start);
  final e = dateOnly(end);
  final days = <DateTime>[];
  for (var d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
    days.add(d);
  }
  return days;
}

/// 区间覆盖的月桶序列（每月 1 号，升序；跨年也正确）
List<DateTime> monthlyBuckets(DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month);
  final e = DateTime(end.year, end.month);
  final months = <DateTime>[];
  for (var m = s; !m.isAfter(e); m = DateTime(m.year, m.month + 1)) {
    months.add(m);
  }
  return months;
}
