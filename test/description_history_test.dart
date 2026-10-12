// 描述历史 — 仓库层测试（v1.3.0 票 02 / ADR-0020）。
// 覆盖：手输入史/兜底不入、归属映射（支出信封 / 待规划 / 转移双侧）、
// 重复上浮、超限淘汰（LRU 8 条）、撤销不抹历史、账本删除清理、
// 备份兼容（v4 旧备份缺键 → 空历史；导出含键、恢复往返）。
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enve_keeper_app/data/app_repository.dart';
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';

void main() {
  // 内存库 harness（同 carry_refund_repo_test 模式）：
  // 账本 lg1 + AppSetting（toBudget 500）+ 信封 e1「餐饮」；可选加 e2「交通」。
  Future<(db.EnvelopeDatabase, AppRepository, String)> harness({
    bool withE2 = false,
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
            lastPeriodStart: const Value('2026-09-01'),
          ),
        );
    await database
        .into(database.appSettings)
        .insert(
          db.AppSettingsCompanion.insert(ledgerId: 'lg1', toBudget: 500),
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
            carryover: false,
          ),
        );
    if (withE2) {
      await database
          .into(database.envelopes)
          .insert(
            db.EnvelopesCompanion.insert(
              id: 'e2',
              ledgerId: 'lg1',
              name: '交通',
              icon: 'car',
              color: 'sky',
              planned: 50,
              used: 10,
              carryover: false,
            ),
          );
    }
    return (database, repo, 'lg1');
  }

  // 读某信封的描述历史（最近优先）——直接查表，不经过被测的 watch 流
  Future<List<String>> historyOf(
    db.EnvelopeDatabase database,
    String envId,
  ) async {
    final rows = await (database.select(database.descriptionHistory)
          ..where((h) => h.envelopeId.equals(envId))
          ..orderBy([(h) => OrderingTerm.desc(h.lastUsedAt)]))
        .get();
    return rows.map((r) => r.description).toList();
  }

  int seq = 0;

  // 造一笔手输描述的支出
  Future<void> spend(
    AppRepository repo,
    String ledgerId, {
    String desc = '',
    DateTime? at,
  }) {
    return repo.addTransaction(
      ledgerId: ledgerId,
      fallback: '餐饮',
      recordHistoryFor: const ['e1'],
      txn: Txn(
        id: 'tx-${seq++}',
        type: TxType.expense,
        amount: 1,
        description: desc,
        at: at ?? DateTime(2026, 9, 28, 10),
        envelopeId: 'e1',
      ),
    );
  }

  group('入史规则（ADR-0020）', () {
    test('手输非空记入所对信封；留空走兜底不入史', () async {
      final (database, repo, ledgerId) = await harness();
      await spend(repo, ledgerId, desc: '午饭');
      expect(await historyOf(database, 'e1'), ['午饭']);

      // 留空 → 描述走兜底「餐饮」，不产生历史
      await spend(repo, ledgerId);
      expect(await historyOf(database, 'e1'), ['午饭']);
      await database.close();
    });

    test('收入记待规划（toBudget 是独立历史域）', () async {
      final (database, repo, ledgerId) = await harness();
      await repo.addTransaction(
        ledgerId: ledgerId,
        fallback: '一笔收入',
        recordHistoryFor: const [kToBudget],
        txn: Txn(
          id: 'tx-in-1',
          type: TxType.income,
          amount: 1000,
          description: '工资',
          at: DateTime(2026, 9, 28, 9),
        ),
      );
      expect(await historyOf(database, kToBudget), ['工资']);
      expect(await historyOf(database, 'e1'), isEmpty); // 不串域
      await database.close();
    });

    test('转移记 from 与 to 两侧各一条', () async {
      final (database, repo, ledgerId) = await harness(withE2: true);
      await repo.addTransaction(
        ledgerId: ledgerId,
        fallback: '餐饮 → 交通',
        recordHistoryFor: const ['e1', 'e2'],
        txn: Txn(
          id: 'tx-tr-1',
          type: TxType.transfer,
          amount: 20,
          description: '腾挪补缺',
          at: DateTime(2026, 9, 28, 11),
          fromId: 'e1',
          toId: 'e2',
        ),
      );
      expect(await historyOf(database, 'e1'), ['腾挪补缺']);
      expect(await historyOf(database, 'e2'), ['腾挪补缺']);
      await database.close();
    });
  });

  group('上浮与淘汰', () {
    test('同信封重复输入 → 只留一条且上浮为最近', () async {
      final (database, repo, ledgerId) = await harness();
      await spend(repo, ledgerId, desc: '早饭', at: DateTime(2026, 9, 28, 8));
      await spend(repo, ledgerId, desc: '午饭', at: DateTime(2026, 9, 28, 9));
      await spend(repo, ledgerId, desc: '早饭', at: DateTime(2026, 9, 28, 10));
      expect(await historyOf(database, 'e1'), ['早饭', '午饭']);
      final count = await database.select(
        database.descriptionHistory,
      ).get();
      expect(count.length, 2); // 没有重复行
      await database.close();
    });

    test('第 9 条进入时淘汰最旧（每信封 8 条）', () async {
      final (database, repo, ledgerId) = await harness();
      for (var i = 0; i < 9; i++) {
        await spend(
          repo,
          ledgerId,
          desc: '描述$i',
          at: DateTime(2026, 9, 28, 8 + i), // 时刻递增，i=0 最旧
        );
      }
      expect(await historyOf(database, 'e1'), [
        for (var i = 8; i >= 1; i--) '描述$i', // 最旧的「描述0」被淘汰
      ]);
      await database.close();
    });
  });

  group('与交易生死解耦（ADR-0020 核心承诺）', () {
    test('撤销交易后历史仍在', () async {
      final (database, repo, ledgerId) = await harness();
      await spend(repo, ledgerId, desc: '午饭');
      final row = await database.select(database.transactions).getSingle();
      await repo.revertTransaction(
        ledgerId: ledgerId,
        txn: Txn(
          id: row.id,
          type: TxType.expense,
          amount: row.amount,
          description: row.description,
          at: row.at,
          envelopeId: row.envelopeId,
        ),
      );
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(await historyOf(database, 'e1'), ['午饭']); // 历史不随交易消失
      await database.close();
    });

    test('删除账本连带清理该账本的历史', () async {
      final (database, repo, ledgerId) = await harness();
      await spend(repo, ledgerId, desc: '午饭');
      await repo.deleteLedger(ledgerId);
      expect(await database.select(database.descriptionHistory).get(), isEmpty);
      await database.close();
    });
  });

  group('.jx 备份兼容（v5 起 descriptionHistory 随备份走）', () {
    // v4 时代（无描述历史表）的最小备份：没有 descriptionHistory 键
    const String v4Backup = '''
{
  "app": "金打细算",
  "schemaVersion": 4,
  "exportedAt": "2026-09-01T10:00:00.000",
  "counts": {"ledgers": 1, "envelopes": 1, "transactions": 0},
  "ledgers": [
    {"id": "lg1", "name": "旧账本", "onboarded": true,
     "lastPeriodStart": "2026-08-01", "periodType": "naturalMonth",
     "periodStartDay": null, "sortOrder": 0,
     "createdAt": "2026-08-01T08:00:00.000Z"}
  ],
  "envelopes": [
    {"id": "e1", "ledgerId": "lg1", "name": "餐饮", "icon": "food",
     "color": "clay", "planned": 100.0, "used": 30.0, "carryover": true,
     "sortOrder": 0}
  ],
  "transactions": [],
  "appSettings": [
    {"ledgerId": "lg1", "toBudget": 500.0, "carryoverDefault": true,
     "currency": "¥"}
  ]
}''';

    test('恢复 v4 旧备份：缺键 → 空历史，账本数据完好', () async {
      final (database, repo, _) = await harness();
      await repo.restoreFromJson(v4Backup);
      expect(
        await database.select(database.descriptionHistory).get(),
        isEmpty,
      );
      final ledger = await (database.select(
        database.ledgers,
      )..where((l) => l.id.equals('lg1'))).getSingle();
      expect(ledger.name, '旧账本');
      await database.close();
    });

    test('导出含 descriptionHistory；恢复到新库后历史完整往返', () async {
      final (database, repo, ledgerId) = await harness();
      await spend(repo, ledgerId, desc: '午饭', at: DateTime(2026, 9, 28, 8));
      await spend(repo, ledgerId, desc: '晚饭', at: DateTime(2026, 9, 28, 9));
      final raw = await repo.exportBackupJson();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      expect(map['schemaVersion'], database.schemaVersion);
      final historyJson = map['descriptionHistory'] as List;
      expect(historyJson.length, 2);

      // 恢复到全新库：整体覆盖后历史与账本都在
      final fresh = db.EnvelopeDatabase(NativeDatabase.memory());
      final freshRepo = AppRepository(fresh);
      await freshRepo.restoreFromJson(raw);
      final rows = await (fresh.select(fresh.descriptionHistory)
            ..orderBy([(h) => OrderingTerm.desc(h.lastUsedAt)]))
          .get();
      expect(rows.map((r) => r.description).toList(), ['晚饭', '午饭']);
      await fresh.close();
      await database.close();
    });
  });
}
