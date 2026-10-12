// 统计卡片数据计算 — 单测（v1.3.0 票 09 / ADR-0021 · ADR-0013）。
// 口径必须与 App 统计页一致：本月用账面值、其余区间用净分配/区间支出、
// 转移零和、结转退回跳过；环形占比按金额降序、停用信封走灰色；
// 柱状桶周/月/近30日按日、年按月；近30日无倒计时。
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/home_widget/stats_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 造一笔交易的简写
  Txn txn(
    String id,
    TxType type,
    double amount,
    DateTime at, {
    String? envelopeId,
    String? fromId,
    String? toId,
  }) => Txn(
    id: id,
    type: type,
    amount: amount,
    description: '测试',
    at: at,
    envelopeId: envelopeId,
    fromId: fromId,
    toId: toId,
  );

  Envelope env(String id, String color, {double planned = 0, double used = 0}) =>
      Envelope(
        id: id,
        name: '信封$id',
        icon: 'food',
        color: color,
        planned: planned,
        used: used,
        carryover: true,
      );

  // 2026-09-28（周二）中午
  final now = DateTime(2026, 9, 28, 12);

  group('总览三数口径（与统计页一致）', () {
    test('本月：用账面值（结转后的 planned/used 合计），不看区间聚合', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.month,
        txns: [
          // 上月的分配与支出不该进本月账面口径
          txn('t1', TxType.transfer, 100, DateTime(2026, 8, 10),
              fromId: kToBudget, toId: 'e1'),
          txn('t2', TxType.expense, 30, DateTime(2026, 8, 11), envelopeId: 'e1'),
        ],
        envelopes: [env('e1', 'clay', planned: 100, used: 40)],
        symbol: '¥',
        now: now,
      );
      expect(data.plannedText, '¥100');
      expect(data.usedText, '¥40');
      expect(data.leftText, '¥60');
      expect(data.progress, 40);
    });

    test('本周：用区间聚合（净分配 / 区间支出），转移零和、结转退回跳过', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.week,
        txns: [
          // 本周（9-28 周一起）：分配 200、撤销 50 → 净分配 150
          txn('a', TxType.transfer, 200, DateTime(2026, 9, 28, 9),
              fromId: kToBudget, toId: 'e1'),
          txn('b', TxType.transfer, 50, DateTime(2026, 9, 28, 10),
              fromId: 'e1', toId: kToBudget),
          // 支出 75（e1=45 + e2=30）
          txn('c', TxType.expense, 45, DateTime(2026, 9, 28, 11),
              envelopeId: 'e1'),
          txn('d', TxType.expense, 30, DateTime(2026, 9, 29, 8),
              envelopeId: 'e2'),
          // 信封间转移：零和，不计收支
          txn('e', TxType.transfer, 20, DateTime(2026, 9, 28, 12),
              fromId: 'e1', toId: 'e2'),
          // 结转退回：系统行为，跳过
          txn('f', TxType.refund, 10, DateTime(2026, 9, 28, 13),
              fromId: 'e1', toId: kToBudget),
          // 上周与下周的都不算
          txn('g', TxType.expense, 99, DateTime(2026, 9, 26), envelopeId: 'e1'),
          txn('h', TxType.expense, 99, DateTime(2026, 10, 6), envelopeId: 'e1'),
        ],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(data.plannedText, '¥150'); // 净分配
      expect(data.usedText, '¥75'); // 区间支出
      expect(data.leftText, '¥75');
      expect(data.progress, 50);
    });

    test('透支：剩余为负、进度截断到 100（不变量①照实显示）', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.week,
        txns: [
          txn('a', TxType.transfer, 100, DateTime(2026, 9, 28),
              fromId: kToBudget, toId: 'e1'),
          txn('b', TxType.expense, 150, DateTime(2026, 9, 28), envelopeId: 'e1'),
        ],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(data.leftText, '−¥50');
      expect(data.progress, 100);
    });
  });

  group('倒计时与区间', () {
    test('本周：end = 下周一 0 点（毫秒），标签「本周」', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.week,
        txns: const [],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(data.labelBase, '本周');
      expect(data.endMillis, DateTime(2026, 10, 5).millisecondsSinceEpoch);
    });

    test('近30日：滚动区间没有倒计时（endMillis = null）', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.last30,
        txns: const [],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(data.labelBase, '近30日');
      expect(data.endMillis, isNull);
    });
  });

  group('可视化数据', () {
    test('环形占比：按金额降序、在用信封用主题色 hex、停用信封灰色', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.month,
        txns: [
          txn('a', TxType.expense, 30, DateTime(2026, 9, 10), envelopeId: 'e1'),
          txn('b', TxType.expense, 70, DateTime(2026, 9, 11), envelopeId: 'gone'),
          txn('c', TxType.expense, 10, DateTime(2026, 9, 12), envelopeId: 'e2'),
        ],
        // gone 已停用（不在在用列表）
        envelopes: [env('e1', 'clay'), env('e2', 'teal')],
        symbol: '¥',
        now: now,
      );
      expect(
        data.ringShares.map((s) => s.colorHex).toList(),
        ['#b5ab9e', '#c77d70', '#80a69c'], // gone(灰) 70 > e1 30 > e2 10
      );
      expect(data.ringShares.first.value, 70);
    });

    test('柱状桶：本周 7 根、近7日 7 根、近30日 30 根（票 16：今年已移除）', () {
      WidgetStatsData of(WidgetStatsRange r) => computeWidgetStats(
        range: r,
        txns: const [],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(of(WidgetStatsRange.week).barValues.length, 7);
      expect(of(WidgetStatsRange.last7).barValues.length, 7);
      expect(of(WidgetStatsRange.last30).barValues.length, 30);
    });

    test('区间解析：旧配置 year 回落本月；近7日有标签、无倒计时（endMillis 为空）', () {
      expect(WidgetStatsRangeX.parse('year'), WidgetStatsRange.month);
      final last7 = computeWidgetStats(
        range: WidgetStatsRange.last7,
        txns: const [],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(last7.labelBase, '近7日');
      expect(last7.endMillis, isNull);
    });

    test('柱状当前下标：本周 = 今天（周一 → 第 0 根）', () {
      final data = computeWidgetStats(
        range: WidgetStatsRange.week,
        txns: const [],
        envelopes: const [],
        symbol: '¥',
        now: now,
      );
      expect(data.barCurrentIndex, 0);
    });
  });

  group('区间/可视化配置解析', () {
    test('往返：id 存储 → parse 还原（未知值回落本月/环形）', () {
      for (final r in WidgetStatsRange.values) {
        expect(WidgetStatsRangeX.parse(r.id), r);
      }
      expect(WidgetStatsRangeX.parse(null), WidgetStatsRange.month);
      expect(WidgetStatsRangeX.parse('junk'), WidgetStatsRange.month);
      expect(WidgetStatsChartX.parse('bars'), WidgetStatsChart.bars);
      expect(WidgetStatsChartX.parse(null), WidgetStatsChart.ring);
    });
  });
}
