// 结转退回 UI widget 测试（v1.2.0 票 01 / ADR-0016）：真实内存数据库 + 真实 provider 树。
// 覆盖：① 流水页 refund 行默认隐藏、勾选「显示转移项」后可见；
//      ② 详情页 refund 只读（无撤销入口、系统行为提示、从/到字段）；
//      ③ 统计页 refund 不计入支出构成（零和排除）。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';
import 'package:enve_keeper_app/ui/shell/records/records_page.dart';
import 'package:enve_keeper_app/ui/shell/stats/stats_page.dart';
import 'package:enve_keeper_app/ui/txn/txn_detail_page.dart';

// 泵起测试环境的依赖：内存库 + mock prefs（widget 树由各用例自行 pump）
class _Env {
  _Env(this.database, this.prefs);
  final db.EnvelopeDatabase database;
  final SharedPreferences prefs;
}

Future<_Env> _makeEnv(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final database = db.EnvelopeDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return _Env(database, prefs);
}

Future<void> _pump(WidgetTester tester, _Env env, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(env.database),
        prefsProvider.overrideWithValue(env.prefs),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

// 建默认账本 + 信封「餐饮」+ 收入 100 + 分配 60 + 结转退回 60。
// 退回后账面：信封 planned 0、待规划 100——与真实结转退回后一致。
Future<ProviderContainer> _seedLedgerWithRefund(
  WidgetTester tester,
  _Env env,
) async {
  await _pump(tester, env, const SizedBox.shrink());
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  final repo = container.read(repoProvider);
  final ledger = await repo.ensureBootstrap();
  final envRow = await repo.createOrRestoreEnvelope(
    ledgerId: ledger.id,
    name: '餐饮',
    icon: 'food',
    color: 'clay',
  );
  await container.read(activeLedgerIdProvider.notifier).set(ledger.id);

  final now = DateTime.now();
  await repo.addTransaction(
    ledgerId: ledger.id,
    fallback: '一笔收入',
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
    fallback: '待规划 → 餐饮',
    txn: Txn(
      id: 't-assign',
      type: TxType.transfer,
      amount: 60,
      description: '测试分配',
      at: now,
      fromId: kToBudget,
      toId: envRow.envelope.id,
    ),
  );
  // 结转退回（系统写入形态）：from=信封、to=待规划、描述写入时定型
  await repo.addTransaction(
    ledgerId: ledger.id,
    fallback: '结转退回 · 餐饮',
    txn: Txn(
      id: 't-refund',
      type: TxType.refund,
      amount: 60,
      description: '',
      at: now,
      fromId: envRow.envelope.id,
      toId: kToBudget,
    ),
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('流水页：结转退回默认隐藏，勾选「显示转移项」后可见', (tester) async {
    final env = await _makeEnv(tester);
    await _seedLedgerWithRefund(tester, env);
    await _pump(tester, env, const RecordsPage());

    // 默认聚焦收支：refund 行（描述「结转退回 · 餐饮」）不可见
    expect(find.text('结转退回 · 餐饮'), findsNothing);
    expect(find.text('测试收入'), findsOneWidget);

    // 勾选后 refund 行出现（归入转移显隐组）
    await tester.tap(find.text('显示转移项'));
    await tester.pumpAndSettle();
    expect(find.text('结转退回 · 餐饮'), findsOneWidget);

    // 长按普通行进入多选；refund 行不可选中（ADR-0016：系统行为不可撤销）
    await tester.longPress(find.text('测试收入'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    // 多选模式下点 refund 行：选中数不变（不进撤销池）
    await tester.tap(find.text('结转退回 · 餐饮'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    // 全选只计入可撤销行（收入 + 分配），refund 不被算进
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);

    await unmountTree(tester);
  });

  testWidgets('详情页：结转退回只读——无撤销入口、系统行为提示、从/到字段', (tester) async {
    final env = await _makeEnv(tester);
    await _seedLedgerWithRefund(tester, env);

    // 一次性查询 refund 行（watch 流在 testWidgets 的假时钟里要靠 pump 推进，
    // 直接 await .first 会死等——一次性 Future 无此问题）
    final row = await (env.database.select(
      env.database.transactions,
    )..where((t) => t.id.equals('t-refund'))).getSingle();
    final refund = Txn(
      id: row.id,
      type: txTypeFromDb(row.type),
      amount: row.amount,
      description: row.description,
      at: row.at,
      fromId: row.fromId,
      toId: row.toId,
    );
    expect(refund.description, '结转退回 · 餐饮'); // 描述已按兜底定型

    // 泵宿主页（provider 流先热身），再把详情页推入导航栈——
    // 详情页的「交易消失自动 pop」守卫假定栈下还有页面，直接当 home 会弹空栈
    await _pump(tester, env, _TxnHostPage(txn: refund));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    // 类型胶囊与金额（灰色无符号）
    expect(find.text('结转退回'), findsOneWidget);
    expect(find.text('¥60'), findsOneWidget);
    // 不提供撤销入口（顶栏「撤销」与底部「撤销这笔记录」都不出现）
    expect(find.text('撤销'), findsNothing);
    expect(find.text('撤销这笔记录'), findsNothing);
    // 系统行为提示替代编辑规则提示
    expect(find.text(refundDetailHint), findsOneWidget);
    // 从/到字段：信封 → 待规划
    expect(find.text('从'), findsOneWidget);
    expect(find.text('待规划'), findsOneWidget);

    await unmountTree(tester);
  });

  testWidgets('统计页：结转退回不计入支出构成与已使用', (tester) async {
    final env = await _makeEnv(tester);
    await _seedLedgerWithRefund(tester, env);
    await _pump(tester, env, const StatsPage());

    // 支出构成为空（若 refund 被误计支出，这里会出现「餐饮 ¥60」段）
    expect(find.text('这个范围里还没有支出'), findsOneWidget);
    // 本月总览：三数全 0（refund 不进 used，也不进任何聚合）
    expect(find.text('¥0'), findsWidgets);

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

// 详情页宿主：Consumer 主动 watch 交易流（热身），模拟真实入口页（流水页）；
// 「打开详情」按钮把详情页推入导航栈——详情页的「交易消失自动 pop」守卫
// 假定进入前交易流已就绪，宿主不 watch 的话首帧即触发自动 pop 弹回。
class _TxnHostPage extends ConsumerWidget {
  const _TxnHostPage({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 热身交易流（与真实入口页一致）；这里不渲染列表
    ref.watch(txnsProvider);
    return Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TxnDetailPage(txn: txn)),
        ),
        child: const Text('打开详情'),
      ),
    );
  }
}
