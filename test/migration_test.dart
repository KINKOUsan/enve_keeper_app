// schema 迁移与版本兼容验证（票 01 · ADR-0013；v3→v4 货币符号 · 票 02 · ADR-0017）。
// 四块：
// 1) 真实走 v2 → v3 升级路径（NativeDatabase.memory 的 setup 钩子搭 v2 旧库）；
// 2) .jx 备份兼容：恢复 v1.0（schema v2）旧备份归一化、导出含新字段、拒收更新版本；
// 3) touchLedgerPeriod 仓库级行为：自动类型越界静默结转、自由类型永不自动；
// 4) 真实走 v3 → v4 升级路径：设置表加 currency 列，存量行回填默认 ¥。
// 说明：setup 回调的 raw 参数类型来自 sqlite3 包，测试不直接依赖该包，故以
// dynamic 传递（行为已由本文件测试覆盖）。
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enve_keeper_app/data/app_repository.dart';
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/period_logic.dart';

// v2 的 ledgers 表结构（ADR-0011/0012 时代：月 key，无周期字段）
const String _v2LedgersDdl = '''
CREATE TABLE ledgers (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  onboarded INTEGER NOT NULL DEFAULT 0,
  last_active_month TEXT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''';

// v2 的其余三表结构（真实 v2 库全表齐备，v2→v4 迁移会触碰 app_settings）
const String _v2OtherTablesDdl = '''
CREATE TABLE envelopes (
  id TEXT NOT NULL PRIMARY KEY,
  ledger_id TEXT NOT NULL,
  name TEXT NOT NULL,
  icon TEXT NOT NULL,
  color TEXT NOT NULL,
  planned REAL NOT NULL,
  used REAL NOT NULL,
  target REAL NULL,
  carryover INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE transactions (
  id TEXT NOT NULL PRIMARY KEY,
  ledger_id TEXT NOT NULL,
  type TEXT NOT NULL,
  amount REAL NOT NULL,
  description TEXT NOT NULL,
  at INTEGER NOT NULL,
  envelope_id TEXT NULL,
  from_id TEXT NULL,
  to_id TEXT NULL
);
CREATE TABLE app_settings (
  ledger_id TEXT NOT NULL PRIMARY KEY,
  to_budget REAL NOT NULL,
  carryover_default INTEGER NOT NULL DEFAULT 1
);
''';

// 造一个 v2 库：旧表 + 给定旧数据 + user_version = 2
void _setupV2Db(dynamic raw, List<Map<String, Object?>> rows) {
  raw.execute(_v2LedgersDdl);
  raw.execute(_v2OtherTablesDdl);
  for (final r in rows) {
    raw.execute(
      'INSERT INTO ledgers (id, name, onboarded, last_active_month, sort_order, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      r.values.toList(),
    );
  }
  raw.execute('PRAGMA user_version = 2');
}

// 造一个 v3 库：ledgers 已有周期字段、app_settings 无 currency 列，user_version = 3
void _setupV3Db(dynamic raw, {required List<Map<String, Object?>> settings}) {
  raw.execute('''
CREATE TABLE ledgers (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  onboarded INTEGER NOT NULL DEFAULT 0,
  last_active_month TEXT NULL,
  last_period_start TEXT NULL,
  period_type TEXT NOT NULL DEFAULT 'naturalMonth',
  period_start_day INTEGER NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''');
  raw.execute(_v2OtherTablesDdl);
  raw.execute(
    'INSERT INTO ledgers (id, name, onboarded, sort_order, created_at) '
    "VALUES ('lg1', 'v3账本', 1, 0, 0)",
  );
  for (final r in settings) {
    raw.execute(
      'INSERT INTO app_settings (ledger_id, to_budget, carryover_default) '
      'VALUES (?, ?, ?)',
      r.values.toList(),
    );
  }
  raw.execute('PRAGMA user_version = 3');
}

void main() {
  // ── 1. 迁移 v2 → v3 ──────────────────────────
  group('迁移 v2→v3（真实升级路径）', () {
    test('月 key → 周期起点（当月 1 号），默认自然月，字段不丢', () async {
      final database = db.EnvelopeDatabase(
        NativeDatabase.memory(
          setup: (raw) => _setupV2Db(raw, [
            {
              'id': 'lg1',
              'name': '旧账本',
              'onboarded': 1,
              'last_active_month': '2026-08',
              'sort_order': 0,
              'created_at': DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
            },
          ]),
        ),
      );
      final ledger = await (database.select(
        database.ledgers,
      )..where((l) => l.id.equals('lg1'))).getSingle();
      // 关键断言：'2026-08' → '2026-08-01'（自然月起点），类型默认自然月
      expect(ledger.lastPeriodStart, '2026-08-01');
      expect(ledger.periodType, 'naturalMonth');
      expect(ledger.periodStartDay, isNull);
      // 其余字段原样保留（不丢数据）
      expect(ledger.name, '旧账本');
      expect(ledger.onboarded, isTrue);
      await database.close();
    });

    test('lastActiveMonth 为 NULL 保持 NULL（首次打开时再初始化）', () async {
      final database = db.EnvelopeDatabase(
        NativeDatabase.memory(
          setup: (raw) => _setupV2Db(raw, [
            {
              'id': 'lg2',
              'name': '空月key',
              'onboarded': 0,
              'last_active_month': null,
              'sort_order': 0,
              'created_at': DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
            },
          ]),
        ),
      );
      final ledger = await (database.select(
        database.ledgers,
      )..where((l) => l.id.equals('lg2'))).getSingle();
      expect(ledger.lastPeriodStart, isNull);
      expect(ledger.periodType, 'naturalMonth');
      await database.close();
    });

    test('多账本迁移：每行独立回填，顺序与名称保留', () async {
      final database = db.EnvelopeDatabase(
        NativeDatabase.memory(
          setup: (raw) => _setupV2Db(raw, [
            {
              'id': 'lg-a',
              'name': '甲',
              'onboarded': 1,
              'last_active_month': '2025-12',
              'sort_order': 0,
              'created_at':
                  DateTime(2025, 12, 1).millisecondsSinceEpoch ~/ 1000,
            },
            {
              'id': 'lg-b',
              'name': '乙',
              'onboarded': 1,
              'last_active_month': '2026-09',
              'sort_order': 1,
              'created_at': DateTime(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
            },
          ]),
        ),
      );
      final all = await (database.select(
        database.ledgers,
      )..orderBy([(l) => OrderingTerm.asc(l.sortOrder)])).get();
      expect(all.length, 2);
      expect(all[0].id, 'lg-a');
      expect(all[0].lastPeriodStart, '2025-12-01'); // 跨年月 key 也正确回填
      expect(all[1].lastPeriodStart, '2026-09-01');
      await database.close();
    });

    test('全新安装：按 v3 schema 建表，新字段可正常写入读出', () async {
      final database = db.EnvelopeDatabase(NativeDatabase.memory());
      await database
          .into(database.ledgers)
          .insert(
            db.LedgersCompanion.insert(
              id: 'lg-new',
              name: '新账本',
              createdAt: DateTime(2026, 9, 17),
              lastPeriodStart: const Value('2026-09-01'),
              periodStartDay: const Value(15),
            ),
          );
      final ledger = await (database.select(
        database.ledgers,
      )..where((l) => l.id.equals('lg-new'))).getSingle();
      expect(ledger.periodType, 'naturalMonth'); // 默认值生效
      expect(ledger.lastPeriodStart, '2026-09-01');
      expect(ledger.periodStartDay, 15);
      await database.close();
    });
  });

  // ── 1b. 迁移 v3 → v4（货币符号，票 02 / ADR-0017）──
  group('迁移 v3→v4：设置表加 currency 列', () {
    test('存量设置行回填默认 ¥，toBudget 等字段不丢', () async {
      final database = db.EnvelopeDatabase(
        NativeDatabase.memory(
          setup: (raw) => _setupV3Db(
            raw,
            settings: const [
              {'id': 'lg1', 'budget': 500.0, 'def': 1},
            ],
          ),
        ),
      );
      final setting = await (database.select(
        database.appSettings,
      )..where((s) => s.ledgerId.equals('lg1'))).getSingle();
      // 关键断言：旧库无 currency 列，迁移后由列默认值回填 ¥
      expect(setting.currency, '¥');
      expect(setting.toBudget, 500.0);
      expect(setting.carryoverDefault, isTrue);
      final ledger = await (database.select(
        database.ledgers,
      )..where((l) => l.id.equals('lg1'))).getSingle();
      expect(ledger.name, 'v3账本'); // 账本行原样
      await database.close();
    });

    test('升级后可写自定义符号并读回（updateCurrency 往返）', () async {
      final database = db.EnvelopeDatabase(
        NativeDatabase.memory(
          setup: (raw) => _setupV3Db(
            raw,
            settings: const [
              {'id': 'lg1', 'budget': 500.0, 'def': 1},
            ],
          ),
        ),
      );
      final repo = AppRepository(database);
      await repo.updateCurrency('lg1', 'HK\$');
      final setting = await (database.select(
        database.appSettings,
      )..where((s) => s.ledgerId.equals('lg1'))).getSingle();
      expect(setting.currency, 'HK\$');
      expect(setting.toBudget, 500.0); // 只动符号，不动金额
      await database.close();
    });

    test('全新安装：按 v4 schema 建表，currency 默认 ¥ 可直接读出', () async {
      final database = db.EnvelopeDatabase(NativeDatabase.memory());
      final repo = AppRepository(database);
      final ledger = await repo.ensureBootstrap();
      final setting = await (database.select(
        database.appSettings,
      )..where((s) => s.ledgerId.equals(ledger.id))).getSingle();
      expect(setting.currency, '¥');
      await database.close();
    });
  });

  // ── 2. .jx 备份版本兼容 ──────────────────────
  group('.jx 备份兼容（票 01：导出含新字段、恢复 v1.0 旧备份）', () {
    // v1.0（schema v2）格式的最小备份：ledgers 用 lastActiveMonth 月 key，
    // 无 periodType/periodStartDay；信封无 archivedAt（更旧备份兜底）
    const String v2Backup = '''
{
  "app": "金打细算",
  "schemaVersion": 2,
  "exportedAt": "2026-09-01T10:00:00.000",
  "counts": {"ledgers": 1, "envelopes": 1, "transactions": 0},
  "ledgers": [
    {"id": "lg1", "name": "旧账本", "onboarded": true,
     "lastActiveMonth": "2026-08", "sortOrder": 0,
     "createdAt": "2026-08-01T08:00:00.000Z"}
  ],
  "envelopes": [
    {"id": "e1", "ledgerId": "lg1", "name": "餐饮", "icon": "food",
     "color": "clay", "planned": 100.0, "used": 30.0, "carryover": true,
     "sortOrder": 0}
  ],
  "transactions": [],
  "appSettings": [
    {"ledgerId": "lg1", "toBudget": 500.0, "carryoverDefault": true}
  ]
}''';

    test('恢复 v2 旧备份：月 key → 周期起点、默认自然月，信封与待规划不丢', () async {
      final database = db.EnvelopeDatabase(NativeDatabase.memory());
      final repo = AppRepository(database);
      await repo.restoreFromJson(v2Backup);

      final ledger = await (database.select(
        database.ledgers,
      )..where((l) => l.id.equals('lg1'))).getSingle();
      expect(ledger.lastPeriodStart, '2026-08-01'); // 归一化：月 key 拼 '-01'
      expect(ledger.periodType, 'naturalMonth'); // 缺省 → 自然月
      expect(ledger.periodStartDay, isNull);
      expect(ledger.onboarded, isTrue);

      final envelope = await (database.select(
        database.envelopes,
      )..where((e) => e.id.equals('e1'))).getSingle();
      expect(envelope.planned, 100.0);
      expect(envelope.used, 30.0);
      expect(envelope.archivedAt, isNull); // 旧备份缺 archivedAt → 在用

      final setting = await (database.select(
        database.appSettings,
      )..where((s) => s.ledgerId.equals('lg1'))).getSingle();
      expect(setting.toBudget, 500.0); // 待规划原样
      expect(setting.currency, '¥'); // 缺列 → 默认符号（票 02 / ADR-0017）
      await database.close();
    });

    test(
      '导出含新字段：lastPeriodStart / periodType / periodStartDay / currency 入 JSON',
      () async {
        final database = db.EnvelopeDatabase(NativeDatabase.memory());
        final repo = AppRepository(database);
        await database
            .into(database.ledgers)
            .insert(
              db.LedgersCompanion.insert(
                id: 'lg-x',
                name: '导出账本',
                createdAt: DateTime(2026, 9, 17),
                lastPeriodStart: const Value('2026-09-01'),
                periodType: const Value('customStartDay'),
                periodStartDay: const Value(10),
              ),
            );
        await database
            .into(database.appSettings)
            .insert(
              db.AppSettingsCompanion.insert(
                ledgerId: 'lg-x',
                toBudget: 300,
                currency: const Value('HK\$'), // 自定义复合符号随行导出
              ),
            );
        final raw = await repo.exportBackupJson();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        expect(map['schemaVersion'], database.schemaVersion);
        final ledgerJson =
            (map['ledgers'] as List).first as Map<String, dynamic>;
        expect(ledgerJson['lastPeriodStart'], '2026-09-01');
        expect(ledgerJson['periodType'], 'customStartDay');
        expect(ledgerJson['periodStartDay'], 10);
        final settingJson =
            (map['appSettings'] as List).first as Map<String, dynamic>;
        expect(settingJson['currency'], 'HK\$');
        await database.close();
      },
    );

    test('拒收比当前更新版本的备份，库未被改动', () async {
      final database = db.EnvelopeDatabase(NativeDatabase.memory());
      final repo = AppRepository(database);
      await repo.ensureBootstrap();
      final newer = v2Backup.replaceFirst(
        '"schemaVersion": 2',
        '"schemaVersion": ${database.schemaVersion + 1}',
      );
      expect(
        () => repo.restoreFromJson(newer),
        throwsA(isA<BackupRestoreException>()),
      );
      // 拒收后原数据仍在
      final ledgers = await database.select(database.ledgers).get();
      expect(ledgers, isNotEmpty);
      await database.close();
    });
  });

  // ── 3. touchLedgerPeriod 仓库级行为 ────────────
  group('touchLedgerPeriod：打开/切换账本的结转触发（ADR-0013）', () {
    // 建一个带账本 + AppSetting + 单信封的内存库；periodType/起点由用例给定
    Future<(db.EnvelopeDatabase, AppRepository, String)> harness({
      required String periodType,
      String? lastPeriodStart,
      int? periodStartDay,
      bool carryover = true,
      double toBudget = 500,
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
      return (database, repo, 'lg1');
    }

    // 读 settings 行的 toBudget
    Future<double> toBudgetOf(db.EnvelopeDatabase database) async {
      final s = await (database.select(
        database.appSettings,
      )..where((x) => x.ledgerId.equals('lg1'))).getSingle();
      return s.toBudget;
    }

    Future<db.Envelope> readEnvelope(db.EnvelopeDatabase database) {
      return (database.select(
        database.envelopes,
      )..where((e) => e.id.equals('e1'))).getSingle();
    }

    test('每周类型越过下期边界 → 静默结转，新起点 = 今天所在周一', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21', // 周一
      );
      // 2026-09-28 是下周一：已越过边界
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      final e = await readEnvelope(database);
      expect(e.planned, 60); // 结余带入（结转开关开）
      expect(e.used, 0); // used 归零
      // 开关开：正结余带入下期，待规划不退款
      expect(await toBudgetOf(database), 500);
      final ledger = await repo.getLedger(ledgerId);
      expect(ledger!.lastPeriodStart, '2026-09-28'); // 新周期起点 = 今天所在周一
      await database.close();
    });

    test('每周类型越过下期边界 + 结转关 → 正结余退回待规划（ADR-0015）', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
        carryover: false,
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      final e = await readEnvelope(database);
      expect(e.planned, 0); // 账面清零
      expect(e.used, 0);
      // 剩余 60 退回待规划：500 + 60（自动结转路径同样退款）
      expect(await toBudgetOf(database), 560);
      await database.close();
    });

    test('每周类型未越界 → 什么都不动', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'weekly',
        lastPeriodStart: '2026-09-21',
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 27, 23, 0));
      final e = await readEnvelope(database);
      expect(e.planned, 100);
      expect(e.used, 40);
      final ledger = await repo.getLedger(ledgerId);
      expect(ledger!.lastPeriodStart, '2026-09-21');
      await database.close();
    });

    test('自由类型永不自动结转（哪怕已存起点在一年前）', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'free',
        lastPeriodStart: '2025-01-01',
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 28, 9, 30));
      final e = await readEnvelope(database);
      expect(e.planned, 100); // 账面原样
      expect(e.used, 40);
      final ledger = await repo.getLedger(ledgerId);
      expect(ledger!.lastPeriodStart, '2025-01-01'); // 起点原样
      await database.close();
    });

    test('起点未初始化（NULL）→ 只补写今天所在周期起点，不结转', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: null,
      );
      await repo.touchLedgerPeriod(ledgerId, DateTime(2026, 9, 17, 15, 0));
      final e = await readEnvelope(database);
      expect(e.planned, 100); // 信封不动
      expect(e.used, 40);
      final ledger = await repo.getLedger(ledgerId);
      expect(ledger!.lastPeriodStart, '2026-09-01'); // 补写本自然月 1 号
      await database.close();
    });
  });

  // ── 4. 周期设置与自由周期手动结束 ──────────────
  group('updateBudgetPeriod / closeFreePeriod（ADR-0013 §4/§5）', () {
    // harness 同上：账本 + AppSetting（toBudget 可调）+ 单信封
    // （planned 100 / used 40 / 结转开关默认开）
    Future<(db.EnvelopeDatabase, AppRepository, String)> harness({
      required String periodType,
      String? lastPeriodStart,
      int? periodStartDay,
      bool carryover = true,
      double toBudget = 500,
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
      return (database, repo, 'lg1');
    }

    // 读 settings 行的 toBudget
    Future<double> toBudgetOf(db.EnvelopeDatabase database) async {
      final s = await (database.select(
        database.appSettings,
      )..where((x) => x.ledgerId.equals('lg1'))).getSingle();
      return s.toBudget;
    }

    Future<db.Ledger> ledgerOf(
      db.EnvelopeDatabase database,
      AppRepository repo,
    ) async => (await repo.getLedger('lg1'))!;

    test('切换类型且起点变化 → 立即结转一次并写入新设置', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: '2026-09-01',
      );
      final rolled = await repo.updateBudgetPeriod(
        ledgerId,
        type: BudgetPeriodType.weekly,
        now: DateTime(2026, 9, 17, 10, 0), // 新起点 = 本周一 9月14日 ≠ 9月1日
      );
      expect(rolled, isTrue);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 60); // 结余带入
      expect(e.used, 0); // used 归零
      final ledger = await ledgerOf(database, repo);
      expect(ledger.periodType, 'weekly');
      expect(ledger.periodStartDay, isNull);
      expect(ledger.lastPeriodStart, '2026-09-14');
      await database.close();
    });

    test('重算起点相同（自然月 → 自定义 1 号）→ 不结转静默保存', () async {
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
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 100); // 账面原样
      expect(e.used, 40);
      final ledger = await ledgerOf(database, repo);
      expect(ledger.periodType, 'customStartDay');
      expect(ledger.periodStartDay, 1);
      expect(ledger.lastPeriodStart, '2026-09-01');
      await database.close();
    });

    test('切到自由周期 → 只换标记不结转，起点保持已存值', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: '2026-09-01',
      );
      final rolled = await repo.updateBudgetPeriod(
        ledgerId,
        type: BudgetPeriodType.free,
        now: DateTime(2026, 9, 17),
      );
      expect(rolled, isFalse);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 100);
      expect(e.used, 40);
      final ledger = await ledgerOf(database, repo);
      expect(ledger.periodType, 'free');
      expect(ledger.lastPeriodStart, '2026-09-01'); // 自由 = 已存起点
      await database.close();
    });

    test('自定义起始日非法（0 / 29）→ ArgumentError，不写库', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: '2026-09-01',
      );
      await expectLater(
        repo.updateBudgetPeriod(
          ledgerId,
          type: BudgetPeriodType.customStartDay,
          startDay: 0,
          now: DateTime(2026, 9, 17),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.updateBudgetPeriod(
          ledgerId,
          type: BudgetPeriodType.customStartDay,
          startDay: 29,
          now: DateTime(2026, 9, 17),
        ),
        throwsArgumentError,
      );
      final ledger = await ledgerOf(database, repo);
      expect(ledger.periodType, 'naturalMonth'); // 设置未被改动
      await database.close();
    });

    test('结束本期：结转一次，新起点 = 点击当日', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'free',
        lastPeriodStart: '2026-09-10',
      );
      final rolled = await repo.closeFreePeriod(
        ledgerId,
        DateTime(2026, 9, 17, 21, 30),
      );
      expect(rolled, isTrue);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 60); // 结转带入
      expect(e.used, 0);
      // 开关开：正结余带入下期，待规划不退款
      expect(await toBudgetOf(database), 500);
      final ledger = await ledgerOf(database, repo);
      expect(ledger.lastPeriodStart, '2026-09-17'); // 新期从今天开始
      await database.close();
    });

    test('结束本期：关结转开关的正结余退回待规划（ADR-0015 钱守恒）', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'free',
        lastPeriodStart: '2026-09-10',
        carryover: false,
        toBudget: 500,
      );
      final rolled = await repo.closeFreePeriod(
        ledgerId,
        DateTime(2026, 9, 17, 21, 30),
      );
      expect(rolled, isTrue);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 0); // 账面清零
      expect(e.used, 0);
      // 剩余 60 退回待规划：500 + 60
      expect(await toBudgetOf(database), 560);
      await database.close();
    });

    test('重复点击结束本期 → 不重复结转', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'free',
        lastPeriodStart: '2026-09-10',
      );
      final now = DateTime(2026, 9, 17, 21, 30);
      await repo.closeFreePeriod(ledgerId, now);
      final again = await repo.closeFreePeriod(ledgerId, now);
      expect(again, isFalse); // 已从今天开始：不再结转
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 60); // 保持第一次结转结果，未二次结转
      expect(e.used, 0);
      await database.close();
    });

    test('非自由类型没有手动结束入口 → 拒绝且不动数据', () async {
      final (database, repo, ledgerId) = await harness(
        periodType: 'naturalMonth',
        lastPeriodStart: '2026-09-01',
      );
      final rolled = await repo.closeFreePeriod(
        ledgerId,
        DateTime(2026, 9, 17),
      );
      expect(rolled, isFalse);
      final e = await (database.select(
        database.envelopes,
      )..where((x) => x.id.equals('e1'))).getSingle();
      expect(e.planned, 100);
      expect(e.used, 40);
      await database.close();
    });
  });
}
