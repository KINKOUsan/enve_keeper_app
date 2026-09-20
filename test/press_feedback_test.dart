// 按压反馈视觉单测（v1.2.x 票 01 · DESIGN.md §4 2026-09-20 增补）：
// 信封卡与待规划头部 pressed 真假切换 0.97 ⇄ 1.0。回弹靠常驻 AnimatedScale
// 的参数变化播放——条件性包裹会在松开瞬间跳变，这里顺带回归该实现约束。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/ui/shell/home/budget_arc_header.dart';
import 'package:enve_keeper_app/ui/shell/home/envelope_card.dart';

// 造一个信封的快捷方法（同 envelope_card_progress_test）
Envelope _env() {
  return Envelope(
    id: 'e1',
    name: '餐饮',
    icon: 'food',
    color: 'clay',
    planned: 100,
    used: 30,
    carryover: true,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('信封卡 pressed 真假切换 0.97 ⇄ 1.0', (tester) async {
    Widget card(bool pressed) => SizedBox(
      width: 158,
      height: 93,
      child: EnvelopeCard(envelope: _env(), symbol: '¥', pressed: pressed),
    );

    await _pump(tester, card(true));
    AnimatedScale scale() => tester.widget<AnimatedScale>(
      find
          .descendant(
            of: find.byType(EnvelopeCard),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );
    expect(scale().scale, 0.97);

    await _pump(tester, card(false));
    expect(scale().scale, 1.0);
  });

  testWidgets('待规划头部 pressed 真假切换 0.97 ⇄ 1.0（弧形背景不动）', (tester) async {
    Widget header(bool pressed) =>
        BudgetArcHeader(toBudget: 100, symbol: '¥', pressed: pressed);

    await _pump(tester, header(true));
    AnimatedScale scale() => tester.widget<AnimatedScale>(
      find
          .descendant(
            of: find.byType(BudgetArcHeader),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );
    expect(scale().scale, 0.97);

    await _pump(tester, header(false));
    expect(scale().scale, 1.0);
  });
}
