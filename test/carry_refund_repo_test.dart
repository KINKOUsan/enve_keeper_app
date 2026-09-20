// 结转退回写入流水 — 仓库层测试（v1.2.0 票 01 / ADR-0016）。
// 三个结转触发路径（打开/切换账本自动结转、修改周期设置立即结转、自由周期手动
// 结束本期）各自断言 refund 流水行（类型、金额、时间、描述、from/to）与余额效果；
// 开关开 / 透支 / 零结余 / 期内不触发 → 不产生流水；历史旧流水不受影响（不补录）。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enve_keeper_app/data/app_repository.dart';
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/domain/period_logic.dart';

void main() {
  // 内存库 harness（同 migration_test 模式）：账本 + AppSetting + 信封组。
  // 默认单个信封 e1「餐饮」（planned 100 / used 40）；carryover 由用例给定。
  Future<(db.EnvelopeDatabase, AppRepository, String)> harness({
    required String periodType,
    String? lastPeriodStart,
    int? periodStartDay,
    bool carryover = false,
    double toBudget = 500,
    List<db.EnvelopesCompanion> extraEnvelopes = const [],
  }) async {
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    final repo = AppRepository(database);
    await database
        .into(database.ledgers)
        .insert(
          db.LedgersCompanion.insert(
            id: 'lg1',
            name: '测试账本',
            createdAt: DateTime(2026, 9, 1),
            lastPeriodStart: Value(lastPeriodStart),
            periodType: Value(periodType),
            periodStartDay: Value(periodStartDay),
          ),
        );
    await database
        .into(database.appSettings)
        .insert(
          db.AppSettingsCompanion.insert(
            ledgerId: 'lg1',
            toBudget: toBudget,
            carryoverDefault: Value(true),
          ),
        );
    await database
        .into(database.envelopes)
        .insert(
          db.EnvelopesCompanion.insert(
            id: 'e1',
            ledgerId: 'lg1',
            name: '餐饮',
            icon: 'food',
            color: 'clay',
            planned: 100,
            used: 40,
            carryover: carryover,
          ),
        );
    for (final extra in extraEnvelopes) {
      await database.into(database.envelopes).insert(extra);
    }
    return (database, repo, 'lg1');
  }

  // 读全部交易行（旧→新）
  Future<List<db.Transaction>> allTxns(db.EnvelopeDatabase database) =>
      (database.select(
        database.transactions,
      )..orderBy([(t) => OrderingTerm.asc(t.at)])).get();

  // 读 settings 行的 toBudget
  Future<double> toBudgetOf(db.EnvelopeDatabase database) async {
    final s = await (database.select(
      database.appSettings,
    )..where((x) => x.ledgerId.equals('lg1'))).getSingle();
    return s.toBudget;
  }

  group('触发路径一：touchLedgerPeriod 打开/切换账本自动结转', () {
    test('越过边界 + 关结转 → 写入 refund 流水（at=旧周期末、描述定型、零和）', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21', // 周一
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));

      final txns = await allTxns(database);
      expect(txns.length, 1);
      final t = txns.single;
      expect(t.type, 'refund');
      expect(t.amount, 60); // 剩余 = 100 − 40
      // 旧周期末 = 被越过的边界（9月28日）前一毫秒；drift 按秒存库截断毫秒
      expect(t.at, DateTime(2026, 9, 27, 23, 59, 59));
      expect(t.description, '结转退回 · 餐饮'); // 不变量⑤：写入时定型
      expect(t.fromId, 'e1');
      expect(t.toId, 'toBudget');
      expect(t.envelopeId, isNull);

      // 余额效果与既有断言一致：信封账面清零、待规划增加（钱守恒）
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 0);
      expect(e.used, 0);
      expect(await toBudgetOf(database), 560);
      await database.close();
    });

    test('开关开 → 正结余带入下期，不产生 refund 流水', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
        carryover: true,
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      expect(await allTxns(database), isEmpty);
      expect(await toBudgetOf(database), 500); // 待规划不动
      await database.close();
    });

    test('期内未越界 → 无结转也无 refund 流水', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 27, 23, 0));
      expect(await allTxns(database), isEmpty);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 100);
      expect(e.used, 40);
      await database.close();
    });
  });

  group('触发路径二：updateBudgetPeriod 修改周期设置立即结转', () {
    test('起点变化 + 关结转 → 写入 refund 流水（at=设置变更时刻）', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: '2026-09-01',
      );
      final rolled = await repo.updateBudgetPeriod(
        ledgerId,
        type: BudgetPeriodType.weekly,
        now: DateTime(2026, 9, 17, 10, 0),
      );
      expect(rolled, isTrue);

      final txns = await allTxns(database);
      expect(txns.length, 1);
      final t = txns.single;
      expect(t.type, 'refund');
      expect(t.amount, 60);
      // 旧周期被设置变更截断：结束时刻 = 变更那一刻
      expect(t.at, DateTime(2026, 9, 17, 10, 0));
      expect(t.description, '结转退回 · 餐饮');
      expect(t.fromId, 'e1');
      expect(t.toId, 'toBudget');
      expect(await toBudgetOf(database), 560);
      await database.close();
    });

    test('重算起点相同 → 不结转，无 refund 流水', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: '2026-09-01',
      );
      final rolled = await repo.updateBudgetPeriod(
        ledgerId,
        type: BudgetPeriodType.customStartDay,
        startDay: 1,
        now: DateTime(2026, 9, 17),
      );
      expect(rolled, isFalse);
      expect(await allTxns(database), isEmpty);
      await database.close();
    });
  });

  group('触发路径三：closeFreePeriod 自由周期手动结束本期', () {
    test('结束本期 + 关结转 → 写入 refund 流水（at=点击时刻）', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'free',
        lastPeriodStart: '2026-09-10',
      );
      final rolled = await repo.closeFreePeriod(
        ledgerId,
        DateTime(2026, 9, 17, 21, 30),
      );
      expect(rolled, isTrue);

      final txns = await allTxns(database);
      expect(txns.length, 1);
      final t = txns.single;
      expect(t.type, 'refund');
      expect(t.amount, 60);
      expect(t.at, DateTime(2026, 9, 17, 21, 30));
      expect(t.description, '结转退回 · 餐饮');
      expect(t.fromId, 'e1');
      expect(t.toId, 'toBudget');
      expect(await toBudgetOf(database), 560);
      await database.close();
    });

    test('重复点击 → 不重复结转，refund 流水不重复', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'free',
        lastPeriodStart: '2026-09-10',
      );
      final now = DateTime(2026, 9, 17, 21, 30);
      await repo.closeFreePeriod(ledgerId, now);
      await repo.closeFreePeriod(ledgerId, now);
      expect((await allTxns(database)).length, 1);
      expect(await toBudgetOf(database), 560); // 只退一次
      await database.close();
    });
  });

  group('多信封与边界情形', () {
    test('多信封关结转 → 每信封一笔 refund 流水，金额守恒', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
        extraEnvelopes: [
          db.EnvelopesCompanion.insert(
            id: 'e2',
            ledgerId: 'lg1',
            name: '交通',
            icon: 'car',
            color: 'sky',
            planned: 30,
            used: 10,
            carryover: false,
          ),
          db.EnvelopesCompanion.insert(
            id: 'e3',
            ledgerId: 'lg1',
            name: '储蓄',
            icon: 'bank',
            color: 'moss',
            planned: 80,
            used: 20,
            carryover: true, // 开关开：不退款、不写流水
          ),
        ],
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));

      final refunds = (await allTxns(database))
          .where((t) => t.type == 'refund');
      expect(refunds.length, 2);
      final byDesc = {for (final t in refunds) t.description: t};
      expect(byDesc['结转退回 · 餐饮']!.amount, 60);
      expect(byDesc['结转退回 · 交通']!.amount, 20);
      // 待规划增加 = 退款合计（钱守恒；e3 的 60 随结转带入 planned）
      expect(await toBudgetOf(database), 580);
      final e3 = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e3'))).getSingle();
      expect(e3.planned, 60);
      await database.close();
    });

    test('透支信封关结转 → 缺口带入下期，不产生 refund 流水', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
        extraEnvelopes: [
          db.EnvelopesCompanion.insert(
            id: 'e2',
            ledgerId: 'lg1',
            name: '医疗',
            icon: 'health',
            color: 'rose',
            planned: 50,
            used: 80, // 透支 30
            carryover: false,
          ),
        ],
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      // 只有 e1 的退款一条；透支的 e2 无流水
      final txns = await allTxns(database);
      expect(txns.length, 1);
      expect(txns.single.description, '结转退回 · 餐饮');
      final e2 = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e2'))).getSingle();
      expect(e2.planned, -30); // 负缺口照带（不变量①）
      expect(e2.used, 0);
      await database.close();
    });

    test('旧流水原样保留：不补录、不重复、金额不动', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
      );
      // 旧周期内的一笔支出（used 40 → 52，结余 48）
      await repo.addTransaction(
        ledgerId: ledgerId,
        fallback: '餐饮',
        txn: TxnFactory.expense('e1', 12, DateTime(2026, 9, 22, 12, 0)),
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));

      final txns = await allTxns(database);
      expect(txns.length, 2); // 旧支出 + 新退款，无补录
      final expense = txns[0];
      expect(expense.type, 'expense');
      expect(expense.amount, 12);
      expect(expense.at, DateTime(2026, 9, 22, 12, 0));
      expect(txns[1].type, 'refund');
      // 退款额按结转那一刻的结余算（100 − 12 − 40 = 48），旧支出的影响未被破坏
      expect(txns[1].amount, 48);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 0);
      expect(e.used, 0);
      expect(await toBudgetOf(database), 548);
      await database.close();
    });
  });

  group('结转退回不可撤销（ADR-0016：系统行为，删掉即破坏钱守恒与账目痕迹）', () {
    test('单笔撤销 refund → ArgumentError，流水与余额原样', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      final txns = await allTxns(database);
      final refundRow = txns.single;
      final refundTxn = Txn(
        id: refundRow.id,
        type: TxType.refund,
        amount: refundRow.amount,
        description: refundRow.description,
        at: refundRow.at,
        fromId: refundRow.fromId,
        toId: refundRow.toId,
      );
      await expectLater(
        repo.revertTransaction(ledgerId: ledgerId, txn: refundTxn),
        throwsArgumentError,
      );
      // 数据未被改动：流水仍在、待规划不回吐
      expect((await allTxns(database)).length, 1);
      expect(await toBudgetOf(database), 560);
      await database.close();
    });

    test('批量撤销含 refund → 整批阻断（返回该笔），其余笔也不动', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
      );
      // 先记一笔可撤销的旧支出，再结转出 refund
      await repo.addTransaction(
        ledgerId: ledgerId,
        fallback: '餐饮',
        txn: TxnFactory.expense('e1', 12, DateTime(2026, 9, 22, 12, 0)),
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      final rows = await allTxns(database);
      final refundRow = rows.firstWhere((t) => t.type == 'refund');
      final expenseRow = rows.firstWhere((t) => t.type == 'expense');
      final refundTxn = Txn(
        id: refundRow.id,
        type: TxType.refund,
        amount: refundRow.amount,
        description: refundRow.description,
        at: refundRow.at,
        fromId: refundRow.fromId,
        toId: refundRow.toId,
      );
      final expenseTxn = Txn(
        id: expenseRow.id,
        type: TxType.expense,
        amount: expenseRow.amount,
        description: expenseRow.description,
        at: expenseRow.at,
        envelopeId: expenseRow.envelopeId,
      );

      // 批量请求里混入 refund：整批不动，返回 refund 作为阻断笔
      final blocked = await repo.revertTransactions(
        ledgerId: ledgerId,
        txns: [expenseTxn, refundTxn],
      );
      expect(blocked, isNotNull);
      expect(blocked!.type, TxType.refund);
      expect((await allTxns(database)).length, 2); // 两笔流水都原样
      expect(await toBudgetOf(database), 548);
      await database.close();
    });
  });
}

/// 测试用交易构造（避免在测试体里重复拼 Txn 字段）
class TxnFactory {
  /// 造一笔支出
  static Txn expense(String envelopeId, double amount, DateTime at) => Txn(
    id: 'tx-expense-$at',
    type: TxType.expense,
    amount: amount,
    description: '测试支出',
    at: at,
    envelopeId: envelopeId,
  );
}
