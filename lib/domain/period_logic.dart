// 预算周期与结转 — 周期类型每账本独立四选一（ADR-0013），结转是信封属性（ADR-0004）。
// 本文件分两层：
// 1) 日历口径（自然月区间）— 统计页与日历文案用，不感知预算周期；
// 2) 预算周期口径（类型/起点/边界/结转）— 引擎与仓库用，不感知统计。
// 两者解耦：跨月周周期（如 9月28日–10月4日）结转按周期边界走，统计仍按日历月聚合。
import 'models.dart';

// ── 日历口径（统计/文案用）──────────────────────

/// 月 key，形如 '2026-09'，统计查询与展示用
String monthKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 本月第一天 0 点
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// 下个月同结构的「本月第一天」
DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1);

/// 本月天数
int daysInMonth(DateTime d) {
  final next = nextMonthStart(d);
  return next.difference(monthStart(d)).inDays;
}

/// 月末最后一天 23:59:59.999
DateTime monthEnd(DateTime d) =>
    nextMonthStart(d).add(const Duration(milliseconds: -1));

/// 一个月度区间（统计页用）
class MonthRange {
  const MonthRange(this.year, this.month);

  /// 区间的年份与月份（1–12）
  final int year;
  final int month;

  String get key => '$year-${month.toString().padLeft(2, '0')}';
  DateTime get start => DateTime(year, month);
  DateTime get end => monthEnd(start);
  MonthRange previous() =>
      month == 1 ? MonthRange(year - 1, 12) : MonthRange(year, month - 1);
  MonthRange next() =>
      month == 12 ? MonthRange(year + 1, 1) : MonthRange(year, month + 1);
}

/// 某天所在的自然月区间
MonthRange rangeOf(DateTime d) => MonthRange(d.year, d.month);

// ── 预算周期口径（ADR-0013）─────────────────────

/// 预算周期类型，每账本独立四选一：
/// - naturalMonth 自然月：每月 1 号起
/// - weekly 每周：每周一起
/// - customStartDay 自定义起始日：每月 X 号起（X ∈ 1–28）
/// - free 自由周期：不按日历，用户手动结束（永不自动结转）
enum BudgetPeriodType { naturalMonth, weekly, customStartDay, free }

/// 周期类型 ↔ 存库字符串（Ledgers.periodType）。
/// 读侧容错：未知/空值（坏备份、降级打开新库）一律回退自然月，不让打开账本直接崩。
BudgetPeriodType periodTypeFromDb(String? v) {
  for (final t in BudgetPeriodType.values) {
    if (t.name == v) return t;
  }
  return BudgetPeriodType.naturalMonth;
}

/// 周期类型 → 存库字符串
String periodTypeToDb(BudgetPeriodType t) => t.name;

/// 自定义起始日合法范围：1–28（每月都存在，边界计算无需对 2 月/小月特判）
bool isValidCustomStartDay(int day) => day >= 1 && day <= 28;

/// 去掉时分秒，只留当天 0 点
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// DateTime → ISO 日期 'yyyy-MM-dd'（存库与 .jx 备份用）
String isoDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// ISO 日期 → 本地 0 点；解析失败返回 null（容错旧数据/坏备份）
DateTime? tryParseIsoDate(String? s) {
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : dateOnly(d);
}

/// 推算「[now] 所在周期」的起点（0 点）。
/// [startDay] 仅自定义起始日类型使用；[storedStart] 仅自由周期使用
/// （自由=已存起点，不按日历推算；为空时兜底为今天）。
DateTime periodStartOf({
  required BudgetPeriodType type,
  int? startDay,
  required DateTime now,
  DateTime? storedStart,
}) {
  switch (type) {
    case BudgetPeriodType.naturalMonth:
      return monthStart(now); // 每月 1 号
    case BudgetPeriodType.weekly:
      // 本周一 0 点（weekday：周一=1…周日=7），天数减法由 DateTime 归一化跨月
      return DateTime(now.year, now.month, now.day - (now.weekday - 1));
    case BudgetPeriodType.customStartDay:
      final day = startDay ?? 1;
      // 本月已到起始日 → 本月 X 号；还没到 → 上月 X 号（X ≤ 28 每月都存在）
      return now.day >= day
          ? DateTime(now.year, now.month, day)
          : DateTime(now.year, now.month - 1, day);
    case BudgetPeriodType.free:
      return storedStart != null ? dateOnly(storedStart) : dateOnly(now);
  }
}

/// [periodStart] 所在周期的下期边界 = 下一周期的起点（0 点）。
/// 自由周期没有自动边界，返回 null。
DateTime? nextPeriodBoundary({
  required BudgetPeriodType type,
  int? startDay,
  required DateTime periodStart,
}) {
  switch (type) {
    case BudgetPeriodType.naturalMonth:
      return nextMonthStart(periodStart);
    case BudgetPeriodType.weekly:
      return dateOnly(periodStart).add(const Duration(days: 7));
    case BudgetPeriodType.customStartDay:
      // 下月同号；startDay ≤ 28 保证每月都存在，无 2 月/小月末特判
      return DateTime(periodStart.year, periodStart.month + 1, startDay ?? 1);
    case BudgetPeriodType.free:
      return null;
  }
}

/// 结转触发判定（打开/切换账本时用）：今天是否已越过下期边界。
/// - 自由周期**永不**自动触发（ADR-0013 §5）；
/// - 已存起点为空说明尚未初始化（新账本/迁移兜底），返回 false，
///   由调用方写入起点而不做结转。
bool hasCrossedPeriodBoundary({
  required BudgetPeriodType type,
  int? startDay,
  required DateTime? storedStart,
  required DateTime now,
}) {
  if (type == BudgetPeriodType.free || storedStart == null) return false;
  final boundary = nextPeriodBoundary(
    type: type,
    startDay: startDay,
    periodStart: storedStart,
  );
  if (boundary == null) return false;
  return !now.isBefore(boundary); // 边界日当天任意时刻都算已越过
}

/// 切换周期设置是否需要立即结转（ADR-0013 §4）：新规则下今天所在周期起点
/// 与已存起点不同。自由类型切换永不结转（§5：自由只手动）；起点未初始化
/// 只写不结转。UI 的确认框预告与 repo 保存时共用本判定——预告什么就发生什么。
bool switchRequiresCarryover({
  required BudgetPeriodType newType,
  int? newStartDay,
  required DateTime? storedStart,
  required DateTime now,
}) {
  if (newType == BudgetPeriodType.free || storedStart == null) return false;
  final newStart = periodStartOf(
    type: newType,
    startDay: newStartDay,
    now: now,
    storedStart: storedStart,
  );
  return dateOnly(newStart) != dateOnly(storedStart);
}

// ── 周期相关的展示文案（纯函数，DESIGN.md §3/§9 v1.1.0）──

// 中文短日期：9月17日
String _cnDate(DateTime d) => '${d.month}月${d.day}日';

/// 我的页「预算周期与结转」行的右侧值：自然月 / 每周 / 每月 X 号 / 自由周期
String periodTypeShortLabel(BudgetPeriodType type, int? startDay) {
  switch (type) {
    case BudgetPeriodType.naturalMonth:
      return '自然月';
    case BudgetPeriodType.weekly:
      return '每周';
    case BudgetPeriodType.customStartDay:
      return '每月 ${startDay ?? 1} 号';
    case BudgetPeriodType.free:
      return '自由周期';
  }
}

/// 首页日期行小字（DESIGN.md §3 v1.1.0）：本期区间随周期类型。
/// 自动类型 = 「起点 – 本期最后一天」；自由 = 「起点 – 至今」。
/// 起点未存时按今天推算兜底。
String periodRangeLabel({
  required BudgetPeriodType type,
  int? startDay,
  required DateTime? storedStart,
  required DateTime now,
}) {
  final start = storedStart == null
      ? periodStartOf(type: type, startDay: startDay, now: now)
      : dateOnly(storedStart);
  if (type == BudgetPeriodType.free) return '${_cnDate(start)} – 至今';
  final boundary = nextPeriodBoundary(
    type: type,
    startDay: startDay,
    periodStart: start,
  );
  if (boundary == null) return '${_cnDate(start)} – 至今';
  final lastDay = boundary.subtract(const Duration(days: 1)); // 本期最后一天
  return '${_cnDate(start)} – ${_cnDate(lastDay)}';
}

/// 我的页月度概览条前缀文案（DESIGN.md §9 v1.1.0）：
/// - 自动类型「本期还剩 N 天」（按周期边界算，N 不含边界日）；
/// - 自由周期「本期已进行 N 天」（含今天）。
String periodOverviewLabel({
  required BudgetPeriodType type,
  int? startDay,
  required DateTime? storedStart,
  required DateTime now,
}) {
  if (type == BudgetPeriodType.free) {
    final start = storedStart == null ? dateOnly(now) : dateOnly(storedStart);
    final days = dateOnly(now).difference(start).inDays + 1; // 含今天
    return '本期已进行 $days 天';
  }
  final start = periodStartOf(type: type, startDay: startDay, now: now);
  // 自动类型：剩余 = 距下期边界天数 − 1（边界日属于新一期）
  final boundary = nextPeriodBoundary(
    type: type,
    startDay: startDay,
    periodStart: start,
  );
  final left = boundary == null
      ? 0
      : boundary.difference(dateOnly(now)).inDays - 1;
  return '本期还剩 $left 天';
}

// ── 结转（铁律，ADR-0013 §6 + ADR-0015/0016，适用于所有周期类型）──

/// 结转的决定（三条铁律，第一条行为由 ADR-0015 修订）：
/// - 正结余：结转开 → 带入下期 planned；结转关 → 账面清零并**退回待规划**
///   （钱守恒：单入口单出口，剩余不凭空消失，ADR-0015 取代 ADR-0004 作废语义；
///   退回的金额流动自 v1.2.0 起按信封逐笔写入 refund 流水，ADR-0016）。
/// - 负缺口：**无论开关都带入下期 planned**（planned 为负即透支欠账）。
///   理由：钱已经真实花出去了，缺口不能凭空消失——呼应不变量①「透支必须一直看得见」。
/// - used 一律归零。
/// 结转语义与周期类型无关（纯函数，输入输出一一对应）。
Envelope carryEnvelope(Envelope e) {
  final remaining = e.available;
  final plannedNext = remaining > 0 && !e.carryover ? 0.0 : remaining;
  return e.copyWith(planned: round2(plannedNext), used: 0);
}

/// 结转退款额（ADR-0015）：关开关信封的正结余应退回待规划的金额，
/// 其余情况（开关开 / 透支 / 零结余）为 0。与 [carryEnvelope] 的清零决策配套。
double carryRefund(Envelope e) =>
    e.available > 0 && !e.carryover ? round2(e.available) : 0.0;

/// 关结转信封的正结余清单（结转退回流水的数据源，ADR-0015/0016）：
/// 每个应退款的信封一项（信封本身 + 退款额），无退款时为空列表。
/// 金额流动由仓库层按信封逐笔生成 refund 流水并经引擎施加，这里只出数据。
List<(Envelope, double)> carryRefundsOf(LedgerState s) => [
  for (final e in s.envelopes.values)
    if (carryRefund(e) > 0) (e, carryRefund(e)),
];

/// 对整份状态做周期结转（只做信封面三铁律，**不动待规划**）。
/// 退款（关开关的正结余 → 待规划）不在本函数内直接加 toBudget——
/// 由仓库层先生成 refund 流水、经 applyTx 引擎施加（v1.2.0 票 01，
/// 「余额变更必经引擎」闭环），再调用本函数收尾信封账面。
/// 注意顺序：先施加 refund 流水再结转（refund 先把正结余退出信封，
/// 结转时 available 已归 0，planned 清零不会重复退钱）。
/// [envelopes] 是上期末的信封列表；[carryoverDefault] 不在此处使用
/// （它只影响新建信封的初始值，见 Settings）。
LedgerState carryOverEnvelopes(LedgerState s) {
  final rolled = s.envelopes.map((k, v) => MapEntry(k, carryEnvelope(v)));
  return LedgerState(toBudget: s.toBudget, envelopes: rolled);
}
