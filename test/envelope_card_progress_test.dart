// 信封卡进度状态单测（票 03 · DESIGN.md §3 v1.1.0）：
// 进度条新语义 = 剩余/已规划：未花满条、花完空条、透支空红条、剩余≤20% 转强调、已规划 0 = 空条。
import 'package:flutter_test/flutter_test.dart';
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/ui/shell/home/envelope_card.dart';

// 造一个信封的快捷方法
Envelope _env({double planned = 0, double used = 0}) {
  return Envelope(
    id: 'e1',
    name: '餐饮',
    icon: 'food',
    color: 'clay',
    planned: planned,
    used: used,
    carryover: true,
  );
}

void main() {
  group('cardProgressOf 进度状态（剩余比例语义）', () {
    test('一分未花 → 满条（ratio = 1），不强调', () {
      final p = cardProgressOf(_env(planned: 100, used: 0));
      expect(p.ratio, 1.0);
      expect(p.over, isFalse);
      expect(p.strong, isFalse);
    });

    test('正常消耗（剩余 > 20%）→ 中间比例，不强调', () {
      final p = cardProgressOf(_env(planned: 100, used: 40));
      expect(p.ratio, closeTo(0.6, 1e-9));
      expect(p.over, isFalse);
      expect(p.strong, isFalse);
    });

    test('接近用尽（0 < 剩余 ≤ 20%）→ 转主色强调', () {
      final p = cardProgressOf(_env(planned: 100, used: 85));
      expect(p.ratio, closeTo(0.15, 1e-9));
      expect(p.over, isFalse);
      expect(p.strong, isTrue);
    });

    test('剩余恰好 20% → 仍属接近用尽（边界含）', () {
      final p = cardProgressOf(_env(planned: 100, used: 80));
      expect(p.ratio, closeTo(0.2, 1e-9));
      expect(p.strong, isTrue);
    });

    test('花完（剩余 = 0）→ 空条（0 宽），轨道不转红', () {
      final p = cardProgressOf(_env(planned: 100, used: 100));
      expect(p.ratio, 0);
      expect(p.over, isFalse);
      expect(p.strong, isFalse);
    });

    test('透支（剩余 < 0）→ 空条 + 轨道转红标记', () {
      final p = cardProgressOf(_env(planned: 80, used: 120));
      expect(p.ratio, 0);
      expect(p.over, isTrue);
      expect(p.strong, isFalse);
    });

    test('已规划为 0（一分未分）→ 空条，不算透支', () {
      final p = cardProgressOf(_env(planned: 0, used: 0));
      expect(p.ratio, 0);
      expect(p.over, isFalse);
      expect(p.strong, isFalse);
    });

    test('比例封顶：浮点漂移不会让未花满的条超过 1', () {
      // planned 33.33 / used 0.01 → 剩余 33.32，比例 0.9997 附近而非 >1
      final p = cardProgressOf(_env(planned: 33.33, used: 0.01));
      expect(p.ratio <= 1.0, isTrue);
      expect(p.ratio > 0.99, isTrue);
    });
  });
}
