// 交易时间编辑 widget 测试（txn-time-edit 票 01 / ADR-0019）：真实内存数据库 + 真实 provider 树。
// 覆盖：① 详情页时间行可点（有箭头）、结转退回纯只读（无箭头）；
//      ② 点时间行弹滚轮弹层，取消不落库；
//      ③ 滚轮改动后确定 → at 落库，且信封 planned/used 与待规划分毫不动（时间是档案标签）。
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';
import 'package:enve_keeper_app/ui/txn/time_edit_sheet.dart';
import 'package:enve_keeper_app/ui/txn/txn_detail_page.dart';

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

// 建默认账本 + 信封「餐饮」+ 收入 100 + 分配 60 + 支出 25 + 结转退回 20。
// 账面：餐饮 planned 40（分配 60 − 造数退回 20；真实结转退回发生在 planned 清零后，
// 这里只为造一笔 refund 行）、used 25，待规划 60。
Future<void> _seed(WidgetTester tester, _Env env) async {
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
  Future<void> add(String id, Txn txn) =>
      repo.addTransaction(ledgerId: ledger.id, fallback: id, txn: txn);
  await add('t-income', Txn(id: 't-income', type: TxType.income, amount: 100, description: '测试收入', at: now));
  await add('t-assign', Txn(id: 't-assign', type: TxType.transfer, amount: 60, description: '测试分配', at: now, fromId: kToBudget, toId: envRow.envelope.id));
  await add('t-expense', Txn(id: 't-expense', type: TxType.expense, amount: 25, description: '午餐', at: now, envelopeId: envRow.envelope.id));
  await add('t-refund', Txn(id: 't-refund', type: TxType.refund, amount: 20, description: '', at: now, fromId: envRow.envelope.id, toId: kToBudget));
}

// 查一行交易并转领域对象
Future<Txn> _getTxn(_Env env, String id) async {
  final row = await (env.database.select(
    env.database.transactions,
  )..where((t) => t.id.equals(id))).getSingle();
  return Txn(
    id: row.id,
    type: txTypeFromDb(row.type),
    amount: row.amount,
    description: row.description,
    at: row.at,
    envelopeId: row.envelopeId,
    fromId: row.fromId,
    toId: row.toId,
  );
}

// 查账面三数：信封 planned/used + 待规划
Future<(double, double, double)> _balances(_Env env, String envelopeId) async {
  final envRow = await (env.database.select(
    env.database.envelopes,
  )..where((e) => e.id.equals(envelopeId))).getSingle();
  final settings = await (env.database.select(
    env.database.appSettings,
  )..where((s) => s.ledgerId.equals(envRow.ledgerId))).getSingle();
  return (envRow.planned, envRow.used, settings.toBudget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('详情页：支出笔时间行有箭头可点、新提示文案；结转退回时间行无箭头', (tester) async {
    final env = await _makeEnv(tester);
    await _seed(tester, env);
    final expense = await _getTxn(env, 't-expense');

    await _pump(tester, env, _TxnHostPage(txn: expense));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    // 可编辑行（描述 + 时间）各带一个右箭头
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    // 新提示文案（260922 定稿逐字）
    expect(find.text(txnEditRulesHint), findsOneWidget);
    expect(find.text('可修改金额、描述与时间'), findsOneWidget);

    await unmountTree(tester);

    // 结转退回：详情页纯只读，时间行不给箭头
    final refund = await _getTxn(env, 't-refund');
    await _pump(tester, env, _TxnHostPage(txn: refund));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await unmountTree(tester);
  });

  testWidgets('改时间：点时间行弹滚轮弹层；取消不落库', (tester) async {
    final env = await _makeEnv(tester);
    await _seed(tester, env);
    final expense = await _getTxn(env, 't-expense');

    await _pump(tester, env, _TxnHostPage(txn: expense));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    // 点「时间」行 → 弹层出现。弹层入场要两段 pump：第一段挂载路由，
    // 第二段推进动画；滚轮动画未定时 pumpAndSettle 会死等，全程用定长 pump。
    await tester.tap(find.text('时间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('改时间'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);

    // 取消：弹层关闭、at 不变
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('改时间'), findsNothing);
    final afterCancel = await _getTxn(env, 't-expense');
    expect(afterCancel.at, expense.at);

    await unmountTree(tester);
  });

  testWidgets('改时间：滚轮改过去 → 确定落库，余额分毫不动（at 是档案标签）', (tester) async {
    final env = await _makeEnv(tester);
    await _seed(tester, env);
    final expense = await _getTxn(env, 't-expense');
    final envelopeId = expense.envelopeId!;
    final before = await _balances(env, envelopeId);
    expect(before, (40.0, 25.0, 60.0)); // 种子账面自检

    await _pump(tester, env, _TxnHostPage(txn: expense));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('时间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 往下拨滚轮 = 拨向更早时刻（对上限无碰撞，任意时刻跑都成立）
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, 32));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // at 已变（具体值随滚轮落点，不硬编码），且只早不晚
    final after = await _getTxn(env, 't-expense');
    expect(after.at.isBefore(expense.at), isTrue);

    // 时间变了，钱一分没动（ADR-0019：at 是档案标签，不是账务归属）
    final balances = await _balances(env, envelopeId);
    expect(balances, before);

    await unmountTree(tester);
  });

  testWidgets('弹层：任意过去时刻可作初始值（无下限钳制），确定原样交回', (tester) async {
    DateTime? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Builder 提供 onPressed 闭包能拿到的 BuildContext
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  returned = await showTimeEditSheet(
                    context,
                    initial: DateTime(2020, 5, 1, 8, 30),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('改时间'), findsOneWidget);

    // 滚轮未被拨动 → 确定交回的就是传入的过去时刻（ADR-0019：任意过去可补记）
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(returned, DateTime(2020, 5, 1, 8, 30));

    await unmountTree(tester);
  });
}

// 详情页宿主：与 refund_ui_test 同一套路——宿主先 watch 交易流热身，
// 详情页的「交易消失自动 pop」守卫假定栈下还有页面，直接当 home 会弹空栈。
class _TxnHostPage extends StatelessWidget {
  const _TxnHostPage({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        ref.watch(txnsProvider);
        return Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TxnDetailPage(txn: txn)),
            ),
            child: const Text('打开详情'),
          ),
        );
      },
    );
  }
}

// 测试区内卸载整棵树：drift 流关闭排 0ms 计时器，留到 finalizeTree 会触发
// !timersPending 断言——显式推进 1ms 让它触发（同 refund_ui_test）。
Future<void> unmountTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
