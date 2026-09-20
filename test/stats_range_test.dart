// stats_range 纯函数单测 — 区间边界 / 日桶 / 月桶（票 04）+
// 周期分页锚点/平移/可达判定与近30日/全部区间（v1.2.0 票 07）
import 'package:enve_keeper_app/domain/stats_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mondayOf', () {
    test('返回所在自然周的周一 0 点', () {
      for (var i = 0; i < 7; i++) {
        final d = DateTime(2026, 9, 14 + i); // 9月14日起连续 7 天
        final mon = mondayOf(d);
        expect(mon.weekday, 1);
        expect(mon, DateTime(2026, 9, 14)); // 这 7 天同属周一 9/14 所在周
      }
    });

    test('跨月归一化正确', () {
      final mon = mondayOf(DateTime(2026, 9, 1)); // 9月1日若在周内前几天会落 8 月
      expect(mon.weekday, 1);
      expect(mon.isBefore(DateTime(2026, 9, 1)), isTrue);
    });
  });

  group('近30日与全部时间（票 07）', () {
    test('近30日 = 含今天的滚动 30 天', () {
      final (start, end) = statsBounds(
        StatsRange.last30,
        DateTime(2026, 9, 17, 10),
      );
      expect(start, DateTime(2026, 8, 19)); // 今天 − 29 天
      expect(end, DateTime(2026, 9, 18)); // Exclusive：明天 0 点
      expect(
        dailyBuckets(start, end.subtract(const Duration(days: 1))).length,
        30,
      );
    });

    test('全部时间 = 最早流水日 0 点 → 明天 0 点', () {
      final (start, end) = statsBounds(
        StatsRange.all,
        DateTime(2026, 9, 17, 10),
        allStart: DateTime(2025, 3, 8, 14),
      );
      expect(start, DateTime(2025, 3, 8));
      expect(end, DateTime(2026, 9, 18));
    });

    test('全部时间缺 allStart 回落本月（防崩兜底）', () {
      final (start, end) = statsBounds(StatsRange.all, DateTime(2026, 9, 17));
      expect(start, DateTime(2026, 9, 1));
      expect(end, DateTime(2026, 10, 1));
    });
  });

  group('周期锚点与步进（票 07）', () {
    test('periodAnchorOf：周/月/季/年各归周期首日', () {
      expect(
        periodAnchorOf(StatsRange.week, DateTime(2026, 9, 16)),
        DateTime(2026, 9, 14),
      );
      expect(
        periodAnchorOf(StatsRange.month, DateTime(2026, 9, 16)),
        DateTime(2026, 9, 1),
      );
      expect(
        periodAnchorOf(StatsRange.quarter, DateTime(2026, 8, 2)),
        DateTime(2026, 7, 1),
      );
      expect(
        periodAnchorOf(StatsRange.year, DateTime(2026, 8, 2)),
        DateTime(2026, 1, 1),
      );
    });

    test('shiftPeriod：月平移跨年正确，季平移 ±3 月，周平移 ±7 天', () {
      final dec = DateTime(2025, 12, 1);
      expect(shiftPeriod(StatsRange.month, dec, 1), DateTime(2026, 1, 1));
      expect(shiftPeriod(StatsRange.month, dec, -1), DateTime(2025, 11, 1));
      expect(
        shiftPeriod(StatsRange.quarter, DateTime(2026, 7, 1), 1),
        DateTime(2026, 10, 1),
      );
      expect(
        shiftPeriod(StatsRange.quarter, DateTime(2026, 7, 1), -1),
        DateTime(2026, 4, 1),
      );
      expect(
        shiftPeriod(StatsRange.week, DateTime(2026, 9, 14), -1),
        DateTime(2026, 9, 7),
      );
      expect(
        shiftPeriod(StatsRange.week, DateTime(2026, 9, 14), 2),
        DateTime(2026, 9, 28),
      );
    });

    test('periodAnchorsWithTxns：流水时刻归并到所在周期', () {
      final anchors = periodAnchorsWithTxns(StatsRange.month, [
        DateTime(2026, 7, 3, 9),
        DateTime(2026, 7, 28, 21),
        DateTime(2026, 9, 1),
      ]);
      expect(anchors, {DateTime(2026, 7, 1), DateTime(2026, 9, 1)});
    });

    test('periodStepAllowed：目标有流水可达；当前周期特例可停留', () {
      final now = DateTime(2026, 9, 17);
      final anchor = DateTime(2026, 9, 1);
      // 当前月无流水、上一月有流水
      final withTxns = {DateTime(2026, 8, 1)};

      // 步回上一月：有流水 → 可达
      expect(
        periodStepAllowed(StatsRange.month, anchor, -1, withTxns, now),
        isTrue,
      );
      // 从上一月步进到当前月：无流水但属当前周期 → 可停留
      expect(
        periodStepAllowed(
          StatsRange.month,
          DateTime(2026, 8, 1),
          1,
          withTxns,
          now,
        ),
        isTrue,
      );
      // 再往右（跨过当前周期）：既无流水也非当前周期 → 不可达
      expect(
        periodStepAllowed(
          StatsRange.month,
          DateTime(2026, 8, 1),
          2,
          withTxns,
          now,
        ),
        isFalse,
      );
      // 往左越过最早流水月（2026-07 无流水）→ 不可达
      expect(
        periodStepAllowed(
          StatsRange.month,
          DateTime(2026, 8, 1),
          -1,
          withTxns,
          now,
        ),
        isFalse,
      );
    });

    test('periodStepAllowed：最晚流水在当前周期之后（未来流水）也可达', () {
      final now = DateTime(2026, 9, 17);
      final withTxns = {DateTime(2026, 10, 1)}; // 预记了 10 月的流水
      expect(
        periodStepAllowed(
          StatsRange.month,
          DateTime(2026, 9, 1),
          1,
          withTxns,
          now,
        ),
        isTrue,
      );
    });

    test('dailyBars 粒度：周/近7日/近30日/历史月按日，季/年/全部按月', () {
      bool d(StatsRange r) =>
          dailyBars(r, DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expect(d(StatsRange.week), isTrue);
      expect(d(StatsRange.last7), isTrue);
      expect(d(StatsRange.last30), isTrue);
      expect(d(StatsRange.month), isTrue); // 历史月（当前月走进度榜）
      expect(d(StatsRange.quarter), isFalse);
      expect(d(StatsRange.year), isFalse);
      expect(d(StatsRange.all), isFalse);
      // 自选维持现状：≤31 天按日，>31 按月
      expect(
        dailyBars(
          StatsRange.custom,
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30),
        ),
        isTrue,
      );
      expect(
        dailyBars(
          StatsRange.custom,
          DateTime(2026, 1, 1),
          DateTime(2026, 9, 30),
        ),
        isFalse,
      );
    });
  });

  group('kStatsSegmentOrder 固定顺序（票 07）', () {
    test('段顺序恒为 周/月/季/年/近7日/近30日/全部', () {
      expect(kStatsSegmentOrder, [
        StatsRange.week,
        StatsRange.month,
        StatsRange.quarter,
        StatsRange.year,
        StatsRange.last7,
        StatsRange.last30,
        StatsRange.all,
      ]);
      // 可勾选段是全集去掉周/月
      expect(kStatsOptionalSegments, [
        StatsRange.quarter,
        StatsRange.year,
        StatsRange.last7,
        StatsRange.last30,
        StatsRange.all,
      ]);
      expect(isPeriodRange(StatsRange.week), isTrue);
      expect(isPeriodRange(StatsRange.month), isTrue);
      expect(isPeriodRange(StatsRange.quarter), isTrue);
      expect(isPeriodRange(StatsRange.year), isTrue);
      expect(isPeriodRange(StatsRange.last7), isFalse);
      expect(isPeriodRange(StatsRange.last30), isFalse);
      expect(isPeriodRange(StatsRange.all), isFalse);
      expect(isPeriodRange(StatsRange.custom), isFalse);
    });
  });

  group('statsBounds', () {
    test('周 = 周一起的自然周，区间长 7 天', () {
      final now = DateTime(2026, 9, 16, 15, 30);
      final (start, end) = statsBounds(StatsRange.week, now);
      expect(start, mondayOf(now));
      expect(end.difference(start).inDays, 7);
      expect(start.hour, 0);
    });

    test('近7日 = 含今天的滚动 7 天', () {
      final now = DateTime(2026, 9, 17, 10);
      final (start, end) = statsBounds(StatsRange.last7, now);
      expect(start, DateTime(2026, 9, 11));
      expect(end, DateTime(2026, 9, 18)); // Exclusive：明天 0 点
      // 桶函数含尾，传入「最后一天」（排他终点 − 1 天）
      expect(
        dailyBuckets(start, end.subtract(const Duration(days: 1))).length,
        7,
      );
    });

    test('月 = 自然月', () {
      final (start, end) = statsBounds(StatsRange.month, DateTime(2026, 2, 10));
      expect(start, DateTime(2026, 2, 1));
      expect(end, DateTime(2026, 3, 1)); // 平月 28 天由下月 1 号表达
    });

    test('季 = 自然季（Q3 = 7–9 月）', () {
      final (start, end) = statsBounds(
        StatsRange.quarter,
        DateTime(2026, 8, 2),
      );
      expect(start, DateTime(2026, 7, 1));
      expect(end, DateTime(2026, 10, 1));
    });

    test('年 = 自然年', () {
      final (start, end) = statsBounds(StatsRange.year, DateTime(2026, 9, 17));
      expect(start, DateTime(2026, 1, 1));
      expect(end, DateTime(2027, 1, 1));
    });

    test('自选区间含首尾；起止颠倒时交换', () {
      final (s1, e1) = statsBounds(
        StatsRange.custom,
        DateTime(2026, 9, 17),
        customStart: DateTime(2026, 9, 1, 8),
        customEnd: DateTime(2026, 9, 7, 23),
      );
      expect(s1, DateTime(2026, 9, 1));
      expect(e1, DateTime(2026, 9, 8)); // Exclusive
      // spanDays 面向自选起止日（含首尾）
      expect(spanDays(DateTime(2026, 9, 1), DateTime(2026, 9, 7)), 7);

      final (s2, e2) = statsBounds(
        StatsRange.custom,
        DateTime(2026, 9, 17),
        customStart: DateTime(2026, 9, 7),
        customEnd: DateTime(2026, 9, 1),
      );
      expect(s2, DateTime(2026, 9, 1));
      expect(e2, DateTime(2026, 9, 8));
    });

    test('自选区间跨年正确', () {
      final (start, end) = statsBounds(
        StatsRange.custom,
        DateTime(2026, 9, 17),
        customStart: DateTime(2025, 11, 20),
        customEnd: DateTime(2026, 2, 3),
      );
      expect(start, DateTime(2025, 11, 20));
      expect(end, DateTime(2026, 2, 4));
    });
  });

  group('聚合桶', () {
    test('spanDays 含首尾（≤31 按日 / >31 按月的分界）', () {
      expect(spanDays(DateTime(2026, 9, 1), DateTime(2026, 10, 1)), 31);
      expect(spanDays(DateTime(2026, 9, 1), DateTime(2026, 10, 2)), 32);
    });

    test('dailyBuckets 逐日升序、含首尾', () {
      final days = dailyBuckets(DateTime(2026, 8, 30), DateTime(2026, 9, 2));
      expect(days, [
        DateTime(2026, 8, 30),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
      ]);
    });

    test('monthlyBuckets 跨年升序', () {
      final months = monthlyBuckets(
        DateTime(2025, 11, 15),
        DateTime(2026, 2, 3),
      );
      expect(months, [
        DateTime(2025, 11, 1),
        DateTime(2025, 12, 1),
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 1),
      ]);
    });
  });
}
