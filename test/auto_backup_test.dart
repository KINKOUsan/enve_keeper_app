// 自动备份单测（v1.2.x 票 02 · ADR-0018 · DESIGN.md §19）：
// 防抖合并（连续变动只落一次盘）、编辑交易撤旧+记新只算一次变动、
// 退后台强制落盘、开关默认开 / 关闭不写、失败静默只改状态行、
// 开关不进 .jx（导出不含键、恢复不翻转开关）。
import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/auto_backup_store.dart';
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/state/auto_backup.dart';
import 'package:enve_keeper_app/state/providers.dart';

// 假写入器：记录写入内容，可注入失败；gate 非空时挂起写入（编排并发用例）
class _FakeStore extends AutoBackupStore {
  final writes = <String>[];
  Exception? failure;
  Completer<void>? gate;

  @override
  Future<AutoBackupWriteResult> write(String json) async {
    final g = gate;
    if (g != null) await g.future;
    final f = failure;
    if (f != null) throw f;
    writes.add(json);
    return const AutoBackupWriteResult(publicTarget: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 泵起容器：内存库 + mock prefs + 假写入器；挂监听保持控制器存活
  //（App 侧由 app.dart 的 _Boot watch）。订阅建立后的变动才计入。
  Future<(ProviderContainer, _FakeStore, db.Ledger)> setup(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = _FakeStore();
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(database),
        prefsProvider.overrideWithValue(prefs),
        autoBackupStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final repo = container.read(repoProvider);
    final ledger = await repo.ensureBootstrap();
    container.listen(autoBackupProvider, (_, _) {});
    return (container, store, ledger);
  }

  testWidgets('变动静默 3 秒后落盘；连续变动合并成一次', (tester) async {
    final (container, store, ledger) = await setup(tester);
    final repo = container.read(repoProvider);

    await repo.updateCurrency(ledger.id, 'US\$');
    await tester.pump(const Duration(seconds: 2)); // 静默期内
    expect(store.writes, isEmpty);

    await repo.renameLedger(ledger.id, '主账本'); // 重置静默窗口
    await tester.pump(const Duration(seconds: 2)); // 距上次变动只有 2 秒
    expect(store.writes, isEmpty);

    await tester.pump(const Duration(seconds: 2)); // 越过 3 秒
    expect(store.writes.length, 1);
  });

  testWidgets('一次编辑交易（撤旧 + 记新）只落一次盘，内容是新金额', (tester) async {
    final (container, store, ledger) = await setup(tester);
    final repo = container.read(repoProvider);
    final created = await repo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '餐饮',
      icon: 'food',
      color: 'clay',
    );
    final env = created.envelope;

    final txn = Txn(
      id: repo.newTxnId(),
      type: TxType.expense,
      amount: 10,
      description: '午餐',
      at: DateTime.now(),
      envelopeId: env.id,
    );
    await repo.addTransaction(ledgerId: ledger.id, txn: txn, fallback: '记一笔支出');
    await repo.editTransactionAmount(
      ledgerId: ledger.id,
      oldTxn: txn,
      newAmount: 20,
    );
    await tester.pump(const Duration(milliseconds: 1)); // 让事务通知送达
    await tester.pump(const Duration(seconds: 4));

    expect(store.writes.length, 1);
    final map = jsonDecode(store.writes.single) as Map<String, dynamic>;
    final txns = map['transactions'] as List;
    expect((txns.single as Map)['amount'], 20.0);
  });

  testWidgets('静默期内退到后台：立即落盘，最后一次变动不丢', (tester) async {
    final (container, store, ledger) = await setup(tester);
    await container.read(repoProvider).updateCurrency(ledger.id, 'US\$');
    await tester.pump(const Duration(seconds: 1)); // 未到 3 秒
    expect(store.writes, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(store.writes.length, 1);

    // 恢复前台状态（状态机要求 hidden → inactive → resumed，直达 resumed 会断言失败）
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('后台写入期间又有变动：立即补写，不等防抖', (tester) async {
    final (container, store, ledger) = await setup(tester);
    final repo = container.read(repoProvider);

    // 变动 A → 退后台立即写；用 gate 把写 #1 挂在半路（还没记录）
    await repo.updateCurrency(ledger.id, 'US\$');
    await tester.pump(); // 先让变动通知送达（记脏），flushNow 才有东西可写
    store.gate = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(store.writes, isEmpty); // 写 #1 被 gate 挂起

    // 写 #1 进行中又有变动 B：只记脏，不触发第二次写
    await repo.renameLedger(ledger.id, '主账本');
    await tester.pump();
    expect(store.writes, isEmpty);

    // 放行写 #1：完成后后台不防抖、立即补写变动 B
    //（补写链含多次 DB 查询，轮询 pump 等两次写入都落定）
    store.gate!.complete();
    for (var i = 0; i < 10 && store.writes.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(store.writes.length, 2);

    // 恢复前台状态
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('开关默认开；关闭后变动不写盘；重开后照常', (tester) async {
    final (container, store, ledger) = await setup(tester);
    final notifier = container.read(autoBackupProvider.notifier);
    expect(container.read(autoBackupProvider).enabled, isTrue);

    await notifier.setEnabled(false);
    await container.read(repoProvider).updateCurrency(ledger.id, 'US\$');
    await tester.pump(const Duration(seconds: 5));
    expect(store.writes, isEmpty);

    await notifier.setEnabled(true);
    await container.read(repoProvider).renameLedger(ledger.id, '主账本');
    await tester.pump(const Duration(seconds: 4));
    expect(store.writes.length, 1);
  });

  testWidgets('写入失败静默：不抛出，状态行反映最近一次失败', (tester) async {
    final (container, store, ledger) = await setup(tester);
    store.failure = Exception('disk full');

    await container.read(repoProvider).updateCurrency(ledger.id, 'US\$');
    await tester.pump(const Duration(seconds: 4));

    expect(store.writes, isEmpty);
    final s = container.read(autoBackupProvider);
    expect(s.lastFailureAt, isNotNull);
    expect(s.lastAttemptFailed, isTrue);
  });

  test('开关状态不进备份内容：导出不含开关键，恢复后开关值不变', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(database),
        prefsProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final repo = container.read(repoProvider);
    await repo.ensureBootstrap();
    await prefs.setBool(kAutoBackupEnabledKey, false);

    final json = await repo.exportBackupJson();
    expect(json.contains(kAutoBackupEnabledKey), isFalse);

    await repo.restoreFromJson(json);
    expect(prefs.getBool(kAutoBackupEnabledKey), isFalse);
  });
}
