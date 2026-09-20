// 首页 widget 测试：真实内存数据库 + 真实 provider 树。
// 覆盖：① 信封卡渲染；② 待规划区拖拽出硬币；
// ③ 大字体缩放（模拟器/系统字体设置≠1 的场景）下无溢出异常。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/shell/home/budget_arc_header.dart';
import 'package:enve_keeper_app/ui/shell/home/envelope_card.dart';
import 'package:enve_keeper_app/ui/shell/home/home_controller.dart';
import 'package:enve_keeper_app/ui/shell/home/home_page.dart';
import 'package:drift/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 泵起一个带真实数据（默认账本 + 两个信封）的首页，返回 Provider 容器
  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    HomeController controller, {
    TextScaler? textScaler,
  }) async {
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
        child: MaterialApp(
          // textScaler 非空时模拟「系统字体放大」的设备（模拟器常见差异来源）
          builder: (context, child) => textScaler == null
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
          home: Scaffold(body: HomePage(gesture: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 首次启动：建默认账本（与 app.dart _bootstrap 一致）→ 建两个信封
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    final repo = container.read(repoProvider);
    final ledger = await repo.ensureBootstrap();
    for (final name in const ['餐饮', '交通']) {
      await repo.createOrRestoreEnvelope(
        ledgerId: ledger.id,
        name: name,
        icon: 'food',
        color: 'clay',
      );
    }
    await container.read(activeLedgerIdProvider.notifier).set(ledger.id);
    await tester.pumpAndSettle();
    return container;
  }

  // 测试区内卸载整棵树：drift 流查询关闭会排一个 0ms 计时器，若留到框架
  // 收尾（finalizeTree）会触发 !timersPending 断言（测试基建噪音）。
  // pump 显式推进 1ms 让 0ms 计时器触发（pump() 默认推进 0ms 不触发）。
  Future<void> unmountTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('首页渲染信封卡，待规划区拖拽出硬币', (tester) async {
    final controller = HomeController();
    await pumpHome(tester, controller);

    // 断言一：信封卡渲染出来了（真机反馈「我信封呢」的回归）
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('交通'), findsOneWidget);

    // 断言二：按下不动 → 无拖拽会话（v1.2.0 票 05：真正拖动才显示硬币）
    final budgetCenter = tester.getCenter(find.byKey(controller.budgetKey));
    final gesture = await tester.startGesture(budgetCenter);
    await tester.pump();
    expect(controller.drag, isNull); // 按下未动：无拖拽会话（硬币等视觉由会话单点驱动，均不出现）

    // 断言三：拖动越过阈值 → 硬币会话开始（真机反馈「拖不出硬币」的回归）
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(controller.drag, isNotNull); // 拖拽会话存在
    expect(controller.drag!.kind, DragKind.budget);

    // 断言四：松手 → 会话结束，覆盖层消失
    await gesture.up();
    await tester.pump();
    expect(controller.drag, isNull);

    await unmountTree(tester);
  });

  testWidgets('大字体缩放（1.4）下首页无布局溢出', (tester) async {
    final controller = HomeController();
    await pumpHome(
      tester,
      controller,
      textScaler: const TextScaler.linear(1.4),
    );

    // 信封卡仍正常渲染
    expect(find.text('餐饮'), findsOneWidget);
    // 渲染过程中不允许任何异常（RenderFlex overflow 会以异常形式出现）
    expect(tester.takeException(), isNull);

    await unmountTree(tester);
  });

  // v1.2.x 票 01：按压反馈接线——裸 Listener 按下瞬间点亮 0.97 缩放，
  // 手势取消即恢复（取消而非抬起，避免触发双击判定的 300ms 等待计时器）
  testWidgets('按压信封卡：按下即缩放 0.97，手势取消回 1.0', (tester) async {
    final controller = HomeController();
    await pumpHome(tester, controller);

    AnimatedScale cardScale() => tester.widget<AnimatedScale>(
      find
          .descendant(
            of: find.byType(EnvelopeCard),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(EnvelopeCard).first),
    );
    // 越过 100ms 缩放动画时长，落定在目标值
    await tester.pump(const Duration(milliseconds: 150));
    expect(cardScale().scale, 0.97);

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 150));
    expect(cardScale().scale, 1.0);

    await unmountTree(tester);
  });

  // v1.2.x 票 01：待规划区按压反馈 + 拖拽会话开始时按压态让位拖拽视觉
  testWidgets('按压待规划区：按下即缩放，拖出分配时收掉', (tester) async {
    final controller = HomeController();
    await pumpHome(tester, controller);

    AnimatedScale budgetScale() => tester.widget<AnimatedScale>(
      find
          .descendant(
            of: find.byType(BudgetArcHeader),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );

    final budgetCenter = tester.getCenter(find.byKey(controller.budgetKey));
    final gesture = await tester.startGesture(budgetCenter);
    await tester.pump(const Duration(milliseconds: 150));
    expect(budgetScale().scale, 0.97);

    // 拖动越过阈值 → 拖拽会话开始，按压缩放收掉（源卡视觉交给拖拽层）
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.drag, isNotNull);
    expect(budgetScale().scale, 1.0);

    await gesture.up();
    await tester.pump();
    expect(controller.drag, isNull);

    await unmountTree(tester);
  });
}
