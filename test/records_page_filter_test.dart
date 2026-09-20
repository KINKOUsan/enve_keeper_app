// 流水页 widget 测试：真实内存数据库 + 真实 provider 树（票 04）。
// 覆盖：① 默认隐藏转移、勾选「显示转移项」后出现；
//      ② 开关状态持久化（shared_preferences）；
//      ③ 与类型 chips 的组合过滤。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/shell/records/records_page.dart';
import 'package:enve_keeper_app/ui/txn/txn_filter_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 泵起一个带真实数据（默认账本 + 一个信封 + 收入/支出/转移各一笔）的流水页
  Future<ProviderContainer> pumpRecords(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(database),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: Scaffold(body: RecordsPage())),
      ),
    );
    await tester.pumpAndSettle();

    // 首次启动：建默认账本 + 信封，再入三笔流水（收入 / 分配转移 / 支出）
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordsPage)),
    );
    final repo = container.read(repoProvider);
    final ledger = await repo.ensureBootstrap();
    final env = await repo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '餐饮',
      icon: 'food',
      color: 'clay',
    );
    await container.read(activeLedgerIdProvider.notifier).set(ledger.id);

    final now = DateTime.now();
    await repo.addTransaction(
      ledgerId: ledger.id,
      fallback: '收入',
      txn: Txn(
        id: 't-income',
        type: TxType.income,
        amount: 100,
        description: '测试收入',
        at: now,
      ),
    );
    await repo.addTransaction(
      ledgerId: ledger.id,
      fallback: '分配',
      txn: Txn(
        id: 't-alloc',
        type: TxType.transfer,
        amount: 40,
        description: '测试分配',
        at: now,
        fromId: kToBudget,
        toId: env.envelope.id,
      ),
    );
    await repo.addTransaction(
      ledgerId: ledger.id,
      fallback: '餐饮',
      txn: Txn(
        id: 't-expense',
        type: TxType.expense,
        amount: 12,
        description: '测试支出',
        at: now,
        envelopeId: env.envelope.id,
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('流水页默认隐藏转移，勾选显示转移项后出现，状态持久化', (tester) async {
    final container = await pumpRecords(tester);

    // 断言一：默认聚焦收支——收入/支出可见，转移行不可见
    expect(find.text('测试收入'), findsOneWidget);
    expect(find.text('测试支出'), findsOneWidget);
    expect(find.text('测试分配'), findsNothing);
    expect(container.read(showTransfersProvider), isFalse);

    // 断言二：点「显示转移项」→ 转移行出现，provider 状态翻转
    await tester.tap(find.text('显示转移项'));
    await tester.pumpAndSettle();
    expect(find.text('测试分配'), findsOneWidget);
    expect(container.read(showTransfersProvider), isTrue);

    // 断言三：持久化写入 shared_preferences
    final prefs = container.read(prefsProvider);
    expect(prefs.getBool('records.showTransfers'), isTrue);

    // 断言四：再点一次 → 转移行再次隐藏
    await tester.tap(find.text('显示转移项'));
    await tester.pumpAndSettle();
    expect(find.text('测试分配'), findsNothing);
    expect(container.read(showTransfersProvider), isFalse);

    await unmountTree(tester);
  });

  testWidgets('显示转移 + 类型筛选支出：只留支出行', (tester) async {
    await pumpRecords(tester);

    // 先勾选显示转移
    await tester.tap(find.text('显示转移项'));
    await tester.pumpAndSettle();
    expect(find.text('测试分配'), findsOneWidget);

    // 打开筛选面板 → 选「支出」→ 确定
    await tester.tap(find.byType(TxnFilterButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 断言：只留支出行，转移与收入都被过滤
    expect(find.text('测试支出'), findsOneWidget);
    expect(find.text('测试收入'), findsNothing);
    expect(find.text('测试分配'), findsNothing);

    await unmountTree(tester);
  });
}

// 测试区内卸载整棵树：drift 流查询关闭会排一个 0ms 计时器，若留到框架
// 收尾（finalizeTree）会触发 !timersPending 断言（测试基建噪音）。
// pump 显式推进 1ms 让 0ms 计时器触发（pump() 默认推进 0ms 不触发）。
Future<void> unmountTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
