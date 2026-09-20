// TxnFilter / TxnSort 纯逻辑单测（票 05）
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/domain/txn_filter.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _txn(String id, TxType type, double amount, DateTime at) => Txn(
  id: id,
  type: type,
  amount: amount,
  description: id,
  at: at,
  envelopeId: type == TxType.expense ? 'e1' : null,
);

void main() {
  final e = DateTime(2026, 9, 10, 12, 30); // 支出
  final i = DateTime(2026, 9, 15, 9, 0); // 收入
  final t = DateTime(2026, 9, 15, 18, 0); // 转移
  final txns = [
    _txn('a', TxType.expense, 10, e),
    _txn('b', TxType.income, 100, i),
    _txn('c', TxType.transfer, 20, t),
    _txn('d', TxType.expense, 5, DateTime(2026, 8, 1, 8)),
    // 结转退回（v1.2.0 票 01）：时间在旧周期末，与转移同类管理显隐
    Txn(
      id: 'r',
      type: TxType.refund,
      amount: 15,
      description: 'r',
      at: DateTime(2026, 9, 30, 12, 0),
      fromId: 'e1',
      toId: kToBudget,
    ),
  ];

  group('类型筛选', () {
    test('null = 全部', () {
      const f = TxnFilter();
      expect(f.isActive, isFalse);
      expect(txns.where(f.match).length, 5);
    });

    test('只留指定类型', () {
      final f = const TxnFilter().withType(TxType.expense);
      expect(f.isActive, isTrue);
      expect(txns.where(f.match).map((t) => t.id), ['a', 'd']);
      // refund 与 transfer 类型互不混选（面板也不提供 refund 筛选，票 01）
      expect(
        txns.where(const TxnFilter().withType(TxType.transfer).match).map(
          (t) => t.id,
        ),
        ['c'],
      );
    });
  });

  group('日期筛选', () {
    test('单日：同日不同时刻都命中（日历口径）', () {
      final f = const TxnFilter().withDay(DateTime(2026, 9, 15));
      expect(txns.where(f.match).map((t) => t.id), ['b', 'c']);
    });

    test('区间：首尾两端都含', () {
      final f = const TxnFilter().withRange(
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 15),
      );
      expect(txns.where(f.match).map((t) => t.id), ['a', 'b', 'c']);
    });

    test('单日与区间互斥：设单日清区间，设区间清单日', () {
      final f1 = const TxnFilter()
          .withRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30))
          .withDay(DateTime(2026, 9, 15));
      expect(f1.day, isNotNull);
      expect(f1.rangeStart, isNull);
      expect(f1.rangeEnd, isNull);

      final f2 = const TxnFilter()
          .withDay(DateTime(2026, 9, 15))
          .withRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expect(f2.rangeStart, isNotNull);
      expect(f2.day, isNull);
    });

    test('逐项移除：withoutDay / withoutRange 保留其余条件', () {
      final f = const TxnFilter()
          .withType(TxType.expense)
          .withRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      final f3 = f.withoutRange();
      expect(f3.type, TxType.expense);
      expect(f3.isActive, isTrue);
      expect(f3.noDate, isTrue);

      final f4 = f3.withType(null);
      expect(f4.isActive, isFalse);
    });
  });

  group('组合筛选', () {
    test('类型 + 日期同时生效', () {
      final f = const TxnFilter()
          .withType(TxType.expense)
          .withRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expect(txns.where(f.match).map((t) => t.id), ['a']);
    });
  });

  group('转移显隐（v1.2.0 票 04 + 票 01）', () {
    test('默认显示转移（向后兼容：信封详情页等既有用法不受影响）', () {
      const f = TxnFilter();
      expect(f.showTransfers, isTrue);
      expect(txns.where(f.match).length, 5);
    });

    test('隐藏转移：只剩收入与支出', () {
      final f = const TxnFilter().withShowTransfers(false);
      expect(txns.where(f.match).map((t) => t.id), ['a', 'b', 'd']);
    });

    test('结转退回归入转移显隐组：默认隐藏、勾选后可见（票 01）', () {
      final hidden = const TxnFilter().withShowTransfers(false);
      expect(txns.where(hidden.match).map((t) => t.id), isNot(contains('r')));
      final shown = const TxnFilter().withShowTransfers(true);
      expect(txns.where(shown.match).map((t) => t.id), contains('r'));
    });

    test('隐藏转移不算激活筛选：isActive 不变、条件条不受影响', () {
      final f = const TxnFilter().withShowTransfers(false);
      expect(f.isActive, isFalse);
      expect(f.withShowTransfers(true).isActive, isFalse);
    });

    test('隐藏转移 + 类型 chips 组合：支出/收入各自独立过滤', () {
      final hidden = const TxnFilter().withShowTransfers(false);
      expect(
        txns.where(hidden.withType(TxType.expense).match).map((t) => t.id),
        ['a', 'd'],
      );
      expect(
        txns.where(hidden.withType(TxType.income).match).map((t) => t.id),
        ['b'],
      );
    });

    test('withXxx 复制时保留显隐设置', () {
      final f = const TxnFilter()
          .withShowTransfers(false)
          .withDay(DateTime(2026, 9, 15));
      expect(f.showTransfers, isFalse);
      expect(txns.where(f.match).map((t) => t.id), ['b']);
    });
  });

  group('排序', () {
    test('新→旧：默认方向，同日按时刻排', () {
      final sorted = sortTxns(txns, TxnSort.newest);
      expect(sorted.map((t) => t.id), ['r', 'c', 'b', 'a', 'd']);
    });

    test('旧→新', () {
      final sorted = sortTxns(txns, TxnSort.oldest);
      expect(sorted.map((t) => t.id), ['d', 'a', 'b', 'c', 'r']);
    });

    test('不改入参顺序', () {
      sortTxns(txns, TxnSort.oldest);
      expect(txns.first.id, 'a');
    });
  });
}
