// 首页金额隐私 widget 测试（v1.2.0 票 03）：真实内存数据库 + 真实 provider 树。
// 覆盖：① 首页信封卡 + 待规划头部遮蔽渲染（符号 + ••••）且进度条照常；
//      ② 持久化重启语义（预置 prefs 首帧生效）；③ 透支卡的「缺」行同步遮蔽；
//      ④ 详情页概要区开关就地生效且详情金额不藏；⑤ 「我的 → 预算」组开关同理。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/shell/home/home_controller.dart';
import 'package:enve_keeper_app/ui/shell/home/home_page.dart';
import 'package:enve_keeper_app/ui/shell/profile/profile_page.dart';
import 'package:enve_keeper_app/ui/envelope/envelope_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 泵起测试环境的依赖：内存库 + mock prefs（widget 树由各用例自行 pump）
  Future<(db.EnvelopeDatabase, SharedPreferences)> makeDeps(
    WidgetTester tester, {
    Map<String, Object> prefsSeed = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefsSeed);
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    return (database, prefs);
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    db.EnvelopeDatabase database,
    SharedPreferences prefs,
    Widget child,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(database),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
    // 页面自身也可能带 Scaffold（详情/我的页），取树根这只即可——同一容器
    return ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
  }

  // 建默认账本 + 两个信封 + 收入 100 / 分配 100 / 支出 40。
  // 账面：待规划 0；餐饮 planned 100、剩余 60（进度 0.6）；交通 planned 0。
  // 返回两个信封 id（餐饮在前）。[overspend] 追加支出 80 使餐饮透支（缺 ¥20）。
  Future<(String, String)> seedLedger(
    ProviderContainer container, {
    bool overspend = false,
  }) async {
    final repo = container.read(repoProvider);
    final ledger = await repo.ensureBootstrap();
    final food = await repo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '餐饮',
      icon: 'food',
      color: 'clay',
    );
    final transport = await repo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '交通',
      icon: 'transport',
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
        amount: 100,
        description: '测试分配',
        at: now,
        fromId: kToBudget,
        toId: food.envelope.id,
      ),
    );
    await repo.addTransaction(
      ledgerId: ledger.id,
      fallback: '餐饮',
      txn: Txn(
        id: 't-expense',
        type: TxType.expense,
        amount: 40,
        description: '测试支出',
        at: now,
        envelopeId: food.envelope.id,
      ),
    );
    if (overspend) {
      await repo.addTransaction(
        ledgerId: ledger.id,
        fallback: '餐饮',
        txn: Txn(
          id: 't-over',
          type: TxType.expense,
          amount: 80,
          description: '透支测试',
          at: now,
          envelopeId: food.envelope.id,
        ),
      );
    }
    return (food.envelope.id, transport.envelope.id);
  }

  // 测试区内卸载整棵树：排干 drift 流查询的 0ms 计时器（测试基建噪音）
  Future<void> unmountTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('遮蔽渲染：头部与信封卡显 ¥••••，进度条照常，开关就地生效', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    var container = await pump(
      tester,
      database,
      prefs,
      const SizedBox.shrink(),
    );
    final (foodId, _) = await seedLedger(container);

    // 隐藏待规划 + 餐饮卡，再泵首页
    await container
        .read(hiddenEnvelopeIdsProvider.notifier)
        .setHidden(foodId, true);
    await container.read(hideToBudgetProvider.notifier).set(true);
    container = await pump(
      tester,
      database,
      prefs,
      HomePage(gesture: HomeController()),
    );

    // 断言一：头部（待规划 0）与餐饮卡都显遮蔽形态；餐饮真实金额 60 不可见
    expect(find.text('¥••••'), findsNWidgets(2));
    expect(find.text('¥60'), findsNothing);

    // 断言二：未隐藏的交通卡照常显真实金额
    expect(find.text('¥0'), findsOneWidget);

    // 断言三：遮蔽与进度并存——餐饮卡进度条（剩余比例 0.6）照常渲染
    expect(
      find.byWidgetPredicate(
        (w) => w is FractionallySizedBox && w.widthFactor == 0.6,
      ),
      findsOneWidget,
    );

    // 断言四：开关就地生效——撤销两处隐藏后数字全部回来
    await container.read(hideToBudgetProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(find.text('¥0'), findsNWidgets(2)); // 头部 + 交通
    expect(find.text('¥••••'), findsOneWidget); // 餐饮仍隐藏
    await container
        .read(hiddenEnvelopeIdsProvider.notifier)
        .setHidden(foodId, false);
    await tester.pumpAndSettle();
    expect(find.text('¥60'), findsOneWidget);
    expect(find.text('¥••••'), findsNothing);

    // 断言五：持久化写入 shared_preferences（重启后仍生效的前提）
    final stored = container.read(prefsProvider);
    expect(stored.getBool('home.hideToBudget'), isFalse);
    expect(
      stored.getStringList('home.hiddenEnvelopeIds'),
      isNot(contains(foodId)),
    );

    await unmountTree(tester);
  });

  testWidgets('重启生效：预置 prefs 的隐藏状态首帧即生效', (tester) async {
    final (database, prefs) = await makeDeps(
      tester,
      prefsSeed: {'home.hideToBudget': true},
    );
    var container = await pump(
      tester,
      database,
      prefs,
      const SizedBox.shrink(),
    );
    final (foodId, _) = await seedLedger(container);
    await container
        .read(hiddenEnvelopeIdsProvider.notifier)
        .setHidden(foodId, true);

    // 换全新容器泵首页（模拟重启：provider 从 prefs 重建）
    container = await pump(
      tester,
      database,
      prefs,
      HomePage(gesture: HomeController()),
    );

    expect(container.read(hideToBudgetProvider), isTrue);
    expect(container.read(hiddenEnvelopeIdsProvider), contains(foodId));
    expect(find.text('¥••••'), findsNWidgets(2));

    await unmountTree(tester);
  });

  testWidgets('透支卡遮蔽：「缺」行不带数字，空红条照常渲染', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    var container = await pump(
      tester,
      database,
      prefs,
      const SizedBox.shrink(),
    );
    final (foodId, _) = await seedLedger(container, overspend: true);
    await container
        .read(hiddenEnvelopeIdsProvider.notifier)
        .setHidden(foodId, true);
    container = await pump(
      tester,
      database,
      prefs,
      HomePage(gesture: HomeController()),
    );

    // 主金额遮蔽；透支「缺」行同步遮蔽（不泄露数字）
    expect(find.text('¥••••'), findsOneWidget);
    expect(find.text('缺 ¥••••'), findsOneWidget);
    expect(find.text('缺 ¥20'), findsNothing);
    // 透支后进度条为空（ratio 0），遮蔽前的 0.6 比例条消失
    expect(
      find.byWidgetPredicate(
        (w) => w is FractionallySizedBox && w.widthFactor == 0.6,
      ),
      findsNothing,
    );

    await unmountTree(tester);
  });

  testWidgets('详情页开关：概要区就地切换并持久化，详情金额不藏（仅首页生效）', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    final container = await pump(
      tester,
      database,
      prefs,
      const SizedBox.shrink(),
    );
    final (foodId, _) = await seedLedger(container);
    await pump(tester, database, prefs, EnvelopeDetailPage(envelopeId: foodId));

    // 断言一：概要区默认「金额可见」，点一下就地隐藏并写入 prefs
    expect(find.text('金额可见'), findsOneWidget);
    await tester.tap(find.text('金额可见'));
    await tester.pumpAndSettle();
    expect(find.text('金额已隐藏'), findsOneWidget);
    expect(container.read(hiddenEnvelopeIdsProvider), contains(foodId));
    expect(
      container.read(prefsProvider).getStringList('home.hiddenEnvelopeIds'),
      contains(foodId),
    );

    // 断言二：仅首页生效——详情页剩余金额照常显真实数字
    expect(find.text('¥60'), findsOneWidget);

    // 断言三：再点一下恢复可见
    await tester.tap(find.text('金额已隐藏'));
    await tester.pumpAndSettle();
    expect(find.text('金额可见'), findsOneWidget);
    expect(
      container.read(prefsProvider).getStringList('home.hiddenEnvelopeIds'),
      isNot(contains(foodId)),
    );

    await unmountTree(tester);
  });

  testWidgets('我的页开关：预算组切换待规划隐藏并持久化，我的页金额不藏', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    final container = await pump(
      tester,
      database,
      prefs,
      const SizedBox.shrink(),
    );
    await seedLedger(container);
    await pump(tester, database, prefs, const ProfilePage());

    // 断言一：默认不隐藏，点开关就地生效并写入 prefs
    expect(find.text('隐藏待规划金额'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(hideToBudgetProvider), isTrue);
    expect(container.read(prefsProvider).getBool('home.hideToBudget'), isTrue);

    // 断言二：仅首页生效——我的页月度概览条的待规划金额照常显真实数字
    expect(find.textContaining('未分配的预算 ¥0'), findsOneWidget);

    // 断言三：再点一次恢复
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(hideToBudgetProvider), isFalse);

    await unmountTree(tester);
  });
}
