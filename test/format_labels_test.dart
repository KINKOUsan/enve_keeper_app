// 日期标签纯函数单测（txn-time-edit 票 01 / ADR-0019）：
// 时间可补记到过去任意时刻后，跨年日期必须带年份显示才不歧义。
import 'package:enve_keeper_app/ui/common/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 23, 10, 0);

  group('dayLabel（流水组头）', () {
    test('当年日期不带年份', () {
      expect(dayLabel(DateTime(2026, 9, 15), now), '9月15日 · 周二');
    });

    test('今天 / 昨天不受影响（相对词本身已锚定当前时间）', () {
      expect(dayLabel(now, now), '今天 · 9月23日');
      expect(
        dayLabel(now.subtract(const Duration(days: 1)), now),
        '昨天 · 9月22日',
      );
    });

    test('跨年的昨天：相对词不变（12月31日 只可能指去年）', () {
      final newYear = DateTime(2027, 1, 1, 8, 0);
      expect(
        dayLabel(newYear.subtract(const Duration(days: 1)), newYear),
        '昨天 · 12月31日',
      );
    });

    test('非当年日期带年份', () {
      expect(dayLabel(DateTime(2025, 12, 31), now), '2025年12月31日 · 周三');
    });
  });

  group('atLabel（详情页时间行）', () {
    test('当年：月日 + 时分', () {
      expect(atLabel(DateTime(2026, 9, 15, 8, 30), now), '9月15日 08:30');
    });

    test('非当年：年份前缀 + 月日 + 时分', () {
      expect(atLabel(DateTime(2025, 12, 31, 20, 5), now), '2025年12月31日 20:05');
    });
  });
}
