// 统计卡片的数据计算（v1.3.0 票 09 / ADR-0021 · ADR-0013）：
// 口径与 App 统计页完全一致——纯日历区间聚合（转移零和不计收支、
// 结转退回跳过）、当前月用账面值（结转后的本月 planned/used）、
// 其余区间用净分配/区间支出；可视化数据（环形占比、柱状桶）一并算好。
// 纯函数，供同步控制器在推送时调用，原生侧只显示。
import 'package:flutter/material.dart' show Color;

import '../../domain/models.dart';
import '../../domain/stats_range.dart';
import '../ui/common/format.dart';
import '../../theme/tokens.dart' show envelopeColorById;

/// 组件可选的统计区间（周/月/近7日/近30日，默认本月、随时间自动滚动）。
/// 票 16 追加：去掉「今年」，加「近7日」（领域层现成的滚动 7 天）。
enum WidgetStatsRange { week, month, last7, last30 }

extension WidgetStatsRangeX on WidgetStatsRange {
  /// 存储/读取用的字符串（home_widget 数据侧）
  String get id => name;

  /// 区间标签基底（「还剩 N 天」由原生按到期毫秒动态拼，跨天不开 App 也准）
  String get label => switch (this) {
    WidgetStatsRange.week => '本周',
    WidgetStatsRange.month => '本月',
    WidgetStatsRange.last7 => '近7日',
    WidgetStatsRange.last30 => '近30日',
  };

  /// 对应的领域区间（复用 statsBounds/dailyBuckets 等纯函数）
  StatsRange get domain => switch (this) {
    WidgetStatsRange.week => StatsRange.week,
    WidgetStatsRange.month => StatsRange.month,
    WidgetStatsRange.last7 => StatsRange.last7,
    WidgetStatsRange.last30 => StatsRange.last30,
  };

  static WidgetStatsRange parse(String? s) => switch (s) {
    'week' => WidgetStatsRange.week,
    'last7' => WidgetStatsRange.last7,
    'last30' => WidgetStatsRange.last30,
    'year' => WidgetStatsRange.month, // 票 16：今年区间已移除，旧配置回落本月
    _ => WidgetStatsRange.month,
  };
}

/// 可视化类型：支出构成环形图 / 支出趋势柱状图（配置时二选一）
enum WidgetStatsChart { ring, bars }

extension WidgetStatsChartX on WidgetStatsChart {
  String get id => name;

  static WidgetStatsChart parse(String? s) =>
      s == 'bars' ? WidgetStatsChart.bars : WidgetStatsChart.ring;
}

/// 一张统计卡片的全量展示数据（除位图外的字符串与数字全部算好）
class WidgetStatsData {
  const WidgetStatsData({
    required this.labelBase,
    required this.endMillis,
    required this.plannedText,
    required this.usedText,
    required this.leftText,
    required this.progress,
    required this.ringShares,
    required this.barValues,
    required this.barLabels,
    required this.barCurrentIndex,
  });

  final String labelBase;

  /// 区间结束时刻（epoch 毫秒）；滚动区间（近30日）为 null——没有倒计时
  final int? endMillis;

  // 数字摘要（含货币符号，展示就绪）
  final String plannedText;
  final String usedText;
  final String leftText;

  /// 执行进度 0–100（used/planned 截断）
  final int progress;

  /// 环形图占比：(色 hex，金额)，按金额降序
  final List<({String colorHex, double value})> ringShares;

  /// 柱状图：每根柱的金额 + 当前柱下标（今天/本月，渲染时高亮）
  final List<double> barValues;

  /// 柱状图横轴标签（与 barValues 一一对应）：按日「10.5」、按月「1月」；
  /// 渲染时按柱数抽稀绘制（参考图样式）
  final List<String> barLabels;

  final int barCurrentIndex;
}

/// 计算某账本在给定区间的统计卡片数据。
/// [txns]/[envelopes] 传**该账本**的流水与在用信封（口径同统计页）。
WidgetStatsData computeWidgetStats({
  required WidgetStatsRange range,
  required List<Txn> txns,
  required List<Envelope> envelopes,
  required String symbol,
  required DateTime now,
}) {
  final (start, end) = statsBounds(range.domain, now);
  final lastDay = end.subtract(const Duration(days: 1));
  final today = DateTime(now.year, now.month, now.day);

  // ── 区间聚合（与统计页同一套：转移零和、结转退回跳过、收入不进总览）──
  var usedInRange = 0.0;
  var assignedNet = 0.0;
  final byEnv = <String, double>{};
  final byDay = <DateTime, double>{};
  final byMonth = <DateTime, double>{};
  for (final t in txns) {
    if (t.at.isBefore(start) || !t.at.isBefore(end)) continue;
    switch (t.type) {
      case TxType.expense:
        usedInRange = round2(usedInRange + t.amount);
        final id = t.envelopeId;
        if (id != null) byEnv[id] = round2((byEnv[id] ?? 0) + t.amount);
        byDay[DateTime(t.at.year, t.at.month, t.at.day)] = round2(
          (byDay[DateTime(t.at.year, t.at.month, t.at.day)] ?? 0) + t.amount,
        );
        byMonth[DateTime(t.at.year, t.at.month)] = round2(
          (byMonth[DateTime(t.at.year, t.at.month)] ?? 0) + t.amount,
        );
      case TxType.income:
        break;
      case TxType.transfer:
        if (t.fromId == kToBudget) assignedNet += t.amount;
        if (t.toId == kToBudget) assignedNet -= t.amount;
      case TxType.refund:
        break;
    }
  }
  assignedNet = round2(assignedNet);

  // ── 总览三数（组件恒为当前区间：本月用账面值，其余用区间聚合）──
  final isCurrentMonth = range == WidgetStatsRange.month;
  final planned = isCurrentMonth
      ? round2(envelopes.fold(0.0, (s, e) => s + e.planned))
      : assignedNet;
  final used = isCurrentMonth
      ? round2(envelopes.fold(0.0, (s, e) => s + e.used))
      : usedInRange;
  final left = round2(planned - used);
  final pct = planned > 0 ? (used / planned).clamp(0.0, 1.0) : 0.0;

  // ── 环形占比：按金额降序；在用信封取自己的主题色，其余（停用/跨账档案）灰 ──
  final envById = {for (final e in envelopes) e.id: e};
  final entries = byEnv.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final shares = <({String colorHex, double value})>[];
  for (final entry in entries) {
    final env = envById[entry.key];
    final color = env == null
        ? const Color(0xFFB5AB9E)
        : envelopeColorById(env.color).main;
    shares.add((
      colorHex:
          '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      value: entry.value,
    ));
  }

  // ── 柱状桶：周/月/近30日按日、年按月（统计页 dailyBars 同一规则）──
  final useDaily = dailyBars(range.domain, start, lastDay);
  final barValues = <double>[];
  final barLabels = <String>[];
  var currentIndex = -1;
  if (useDaily) {
    for (final d in dailyBuckets(start, lastDay)) {
      barValues.add(byDay[d] ?? 0);
      barLabels.add('${d.month}.${d.day}');
      if (d == today) currentIndex = barValues.length - 1;
    }
  } else {
    final curMonth = DateTime(now.year, now.month);
    for (final m in monthlyBuckets(start, lastDay)) {
      barValues.add(byMonth[m] ?? 0);
      barLabels.add('${m.month}月');
      if (m == curMonth) currentIndex = barValues.length - 1;
    }
  }

  return WidgetStatsData(
    labelBase: range.label,
    // 滚动区间（近7日/近30日）随今天走，没有「还剩 N 天」倒计时
    endMillis: range == WidgetStatsRange.last7 || range == WidgetStatsRange.last30
        ? null
        : end.millisecondsSinceEpoch,
    plannedText: moneySigned(planned, symbol: symbol),
    usedText: moneySigned(used, symbol: symbol),
    leftText: moneySigned(left, symbol: symbol),
    progress: (pct * 100).round().clamp(0, 100),
    ringShares: shares,
    barValues: barValues,
    barLabels: barLabels,
    barCurrentIndex: currentIndex,
  );
}
