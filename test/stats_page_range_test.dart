// 统计页区间系统 widget 测试（v1.2.0 票 07）：真实内存数据库 + 真实 provider 树。
// 覆盖：① 默认两段胶囊（周/月）+ 月分页条渲染与置灰；
//      ② 「编辑」弹层勾选持久化、胶囊出段、切换生效；
//      ③ 左箭头步进到上月：标签与卡片数据正确，回到当前月右箭头可步进；
//      ④ 重启语义（预置 prefs 出段）+ 滚动区间（近7日）无分页器。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/domain/stats_range.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';
import 'package:enve_keeper_app/ui/shell/stats/stats_page.dart';

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
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(database),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: Scaffold(body: StatsPage())),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
  }

  // 建默认账本 + 信封「餐饮」并激活；返回容器与账本 id
  Future<(ProviderContainer, String)> seedLedger(
    WidgetTester tester,
    db.EnvelopeDatabase database,
    SharedPreferences prefs,
  ) async {
    final container = await pump(tester, database, prefs);
    final repo = container.read(repoProvider);
    final ledger = await repo.ensureBootstrap();
    await repo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '餐饮',
      icon: 'food',
      color: 'clay',
    );
    await container.read(activeLedgerIdProvider.notifier).set(ledger.id);
    await tester.pumpAndSettle();
    return (container, ledger.id);
  }

  // 记一笔支出（任意记账时间，引擎不校验日期）；泵一帧让分页条可达性刷新
  Future<void> addExpense(
    WidgetTester tester,
    ProviderContainer container,
    String ledgerId,
    String envelopeId,
    double amount,
    DateTime at,
  ) async {
    await container
        .read(repoProvider)
        .addTransaction(
          ledgerId: ledgerId,
          fallback: '餐饮',
          txn: Txn(
            id: 't-${at.millisecondsSinceEpoch}-$amount',
            type: TxType.expense,
            amount: amount,
            description: '测试支出',
            at: at,
            envelopeId: envelopeId,
          ),
        );
    await tester.pumpAndSettle();
  }

  // 当前月与上月的参照时刻（测试跑在真实时钟上，断言全部动态推导）
  final now = DateTime.now();
  final thisMonthLabel = '${now.year}年${now.month}月';
  final prevMonth = DateTime(now.year, now.month - 1, 15);
  final prevMonthLabel = '${prevMonth.year}年${prevMonth.month}月';

  testWidgets('默认胶囊只有 周/月 两段，月分页条渲染且右箭头置灰', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    final (container, ledgerId) = await seedLedger(tester, database, prefs);
    // 记一笔支出：当前月有流水 → 分页条只右边界（当前周期）可停留
    final envelopes = await container.read(envelopesProvider.future);
    await addExpense(tester, container, ledgerId, envelopes.first.id, 12, now);

    // 断言一：默认两段胶囊，未勾选段不出现
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('季'), findsNothing);
    expect(find.text('近30日'), findsNothing);
    expect(find.text('编辑'), findsOneWidget);

    // 断言二：月区间分页条渲染，标签 = 当前月
    expect(find.text(thisMonthLabel), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    // 断言三：右箭头置灰（当前周期是右边界），点击标签无动作也不报错
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text(thisMonthLabel), findsOneWidget); // 停在当前月

    await unmountTree(tester);
  });

  testWidgets('编辑弹层勾选季：持久化 + 胶囊出段 + 切换生效', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    final (container, ledgerId) = await seedLedger(tester, database, prefs);
    final envelopes = await container.read(envelopesProvider.future);
    await addExpense(tester, container, ledgerId, envelopes.first.id, 12, now);

    // 打开编辑弹层
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text(statsSegmentEditHint), findsOneWidget);

    // 勾选「季 · 自然季度」→ 就地持久化
    await tester.tap(find.text('季 · 自然季度'));
    await tester.pumpAndSettle();
    expect(
      container.read(prefsProvider).getStringList('stats.segments'),
      contains(StatsRange.quarter.name),
    );

    // 完成 → 胶囊出现「季」段
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('季'), findsOneWidget);

    // 切到季：总览卡标题换成本季度预算，分页条标签 = 当前季度
    await tester.tap(find.text('季'));
    await tester.pumpAndSettle();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    expect(find.text('本季度预算'), findsOneWidget);
    expect(find.text('${now.year}年第$quarter季度'), findsOneWidget);

    // 再进弹层勾掉季 → 当前段被勾掉自动回落到月
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('季 · 自然季度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('本季度预算'), findsNothing); // 已回落
    expect(find.text('本月预算'), findsOneWidget);

    await unmountTree(tester);
  });

  testWidgets('分页条步进：上月标签与数据正确，回到当前月后右箭头可步进', (tester) async {
    final (database, prefs) = await makeDeps(tester);
    final (container, ledgerId) = await seedLedger(tester, database, prefs);
    final envelopes = await container.read(envelopesProvider.future);
    final envId = envelopes.first.id;
    // 上月一笔支出 50（无分配）+ 本月一笔支出 12
    await addExpense(tester, container, ledgerId, envId, 50, prevMonth);
    await addExpense(tester, container, ledgerId, envId, 12, now);

    // 断言一：上月有流水 → 左箭头可步进
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    // 标签出现在分页条与柱状卡标题两处（历史月的柱状卡标题即区间标签）
    expect(find.text(prevMonthLabel), findsNWidgets(2));

    // 断言二：区间切换后卡片数据正确——历史月走区间聚合：
    // 已使用 = 50（总览卡 + 支出构成图例各一处）；信封进度榜换成柱状卡
    expect(find.text('¥50'), findsNWidgets(2));
    expect(find.text('信封进度'), findsNothing);

    // 断言三：历史月右箭头可步进（目标 = 当前周期特例），落回当前月（规范形：
    // 分页条标签回到当前月，第三卡恢复信封进度榜）
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text(thisMonthLabel), findsOneWidget);
    expect(find.text('信封进度'), findsOneWidget);
    // 当前月总览走账面值：已使用 = 12 + 50（信封累计；总览卡 + 进度行各一处）
    expect(find.text('¥62'), findsNWidgets(2));

    await unmountTree(tester);
  });

  testWidgets('重启语义：预置勾选出段；滚动区间近7日无分页器', (tester) async {
    final (database, prefs) = await makeDeps(
      tester,
      prefsSeed: {
        'stats.segments': [StatsRange.last7.name, StatsRange.quarter.name],
      },
    );
    final (container, ledgerId) = await seedLedger(tester, database, prefs);
    final envelopes = await container.read(envelopesProvider.future);
    await addExpense(tester, container, ledgerId, envelopes.first.id, 12, now);

    // 断言一：预置勾选在首帧生效（模拟重启），段顺序固定 周/月/季/近7日
    expect(find.text('季'), findsOneWidget);
    expect(find.text('近7日'), findsOneWidget);
    expect(find.text('近30日'), findsNothing);
    expect(
      find.text('周'),
      findsOneWidget, // 顺序在前的周仍在
    );

    // 断言二：切到近7日（滚动区间）→ 分页器消失
    await tester.tap(find.text('近7日'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.text('近7日预算'), findsOneWidget);

    // 断言三：日历自选区间按钮保留（页头圆形按钮）
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);

    await unmountTree(tester);
  });
}

// 测试区内卸载整棵树：排干 drift 流查询的 0ms 计时器（测试基建噪音）
Future<void> unmountTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
