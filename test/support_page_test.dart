// 支持页 widget 测试（v1.2.x 票 05）：
// 关于页「支持」行位置（意见反馈与开源许可之间）与跳转、
// 支持页开篇文案 + 微信赞赏码/支付宝收款码两张原样大图。
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';
import 'package:enve_keeper_app/ui/shell/profile/about_page.dart';
import 'package:enve_keeper_app/ui/shell/profile/support_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 版本信息替身（关于页读它）
  final fakeInfo = PackageInfo(
    appName: 'enve_keeper_app',
    packageName: 'com.example.enve_keeper_app',
    version: '9.9.9',
    buildNumber: '1',
  );

  Finder qr(String asset) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == asset,
  );

  testWidgets('关于页「支持」行在意见反馈与开源许可之间，点击进入支持页', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWith((_) => Future.value(fakeInfo)),
        ],
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pump();

    expect(find.text('支持'), findsOneWidget);
    final feedbackY = tester.getTopLeft(find.text('意见反馈')).dy;
    final supportY = tester.getTopLeft(find.text('支持')).dy;
    final licenseY = tester.getTopLeft(find.text('开源许可')).dy;
    expect(feedbackY < supportY && supportY < licenseY, isTrue);

    await tester.tap(find.text('支持'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(supportIntroBody), findsOneWidget);
    expect(qr('assets/wechat_pay.png'), findsOneWidget);
    expect(qr('assets/alipay.png'), findsOneWidget);
  });

  testWidgets('支持页：两码上下排列、均可见且不互相遮挡', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('支持'), findsOneWidget);
    expect(find.text('微信赞赏码'), findsOneWidget);

    // 码图很高：滚动到支付宝卡再断言（懒构建 + 视口外）
    final list = find.byType(ListView).first;
    for (var i = 0; i < 10 && qr('assets/alipay.png').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('支付宝收款码'), findsOneWidget);
    final wechatY = tester.getTopLeft(qr('assets/wechat_pay.png')).dy;
    final alipayY = tester.getTopLeft(qr('assets/alipay.png')).dy;
    expect(wechatY < alipayY, isTrue);
  });
}
