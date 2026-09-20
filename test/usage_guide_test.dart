// 使用说明页 widget 测试（v1.2.x 票 04）：
// 「我的」页关于组入口行、说明页内容完整（标题/文案/四张 GIF + 周期图）、
// 进度条公式已人话化、sspai 外链打开与 toast 兜底。
// 注意：GIF 持续动画会让 pumpAndSettle 永不收敛，全程只用固定 pump；
// ListView 懒构建，视口外的节要先滚到才能断言。
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:drift/native.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';
import 'package:enve_keeper_app/ui/shell/profile/profile_page.dart';
import 'package:enve_keeper_app/ui/shell/profile/usage_guide_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 外链通道替身：记录最近一次 launch 的 url，可控返回值
  Object? launchedUrl;
  bool launchOk = true;
  setUp(() {
    launchedUrl = null;
    launchOk = true;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launchedUrl = (call.arguments as Map)['url'];
        return launchOk;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

  // 沿列表把 [finder] 拖进视口（懒构建的节要滚到才存在）
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final list = find.byType(ListView).first;
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
  }

  // 收尾：显式卸载整棵树再泵一拍，让 drift 在卸载时排下的关流计时器
  // 触发掉，避免测试收尾报「Timer is still pending」
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  // 挂载使用说明页（真实 provider 树 + 内存库）
  Future<void> pumpGuide(WidgetTester tester) async {
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
        child: const MaterialApp(home: UsageGuidePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder gif(String asset) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == asset,
  );

  testWidgets('「我的」页关于组首行是「使用说明」，点击进入说明页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final fakeInfo = PackageInfo(
      appName: 'enve_keeper_app',
      packageName: 'com.example.enve_keeper_app',
      version: '9.9.9',
      buildNumber: '1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(database),
          prefsProvider.overrideWithValue(prefs),
          packageInfoProvider.overrideWith((_) => Future.value(fakeInfo)),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    // 滚到关于组：使用说明在关于金打细算上方
    await scrollTo(tester, find.text('使用说明'));
    final guideRow = find.text('使用说明');
    await scrollTo(tester, find.text('关于金打细算'));
    expect(
      tester.getTopLeft(find.text('使用说明')).dy <
          tester.getTopLeft(find.text('关于金打细算')).dy,
      isTrue,
    );

    await tester.tap(guideRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('什么是「信封预算法」'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('说明页内容完整：各节标题、正文、四张 GIF 与周期图都在', (tester) async {
    await pumpGuide(tester);

    // 首屏卡：什么是信封预算法 + 外链
    expect(find.text('什么是「信封预算法」'), findsOneWidget);
    expect(find.text(guideArticleLinkLabel), findsOneWidget);

    // 逐节滚入视口再断言（懒构建）
    await scrollTo(tester, find.text('记收入'));
    expect(find.text('让每一块钱都有「分工」'), findsOneWidget);
    expect(gif('assets/guide/income.gif'), findsOneWidget);

    await scrollTo(tester, find.text('分配金额'));
    expect(gif('assets/guide/allocate.gif'), findsOneWidget);

    await scrollTo(tester, find.text('记消费'));
    expect(gif('assets/guide/spend.gif'), findsOneWidget);

    await scrollTo(tester, find.text('信封的作用'));
    expect(find.textContaining('一并视为可以支配的钱'), findsOneWidget);

    await scrollTo(tester, find.text('灵活调整预算'));
    expect(gif('assets/guide/transfer.gif'), findsOneWidget);
    expect(find.textContaining('金额可以小于 0'), findsOneWidget);

    await scrollTo(tester, find.text('预算周期与结转'));
    expect(find.textContaining('还剩几成预算'), findsOneWidget);
    expect(gif('assets/guide/period.png'), findsOneWidget);

    await scrollTo(tester, find.text('数据安全'));
    expect(find.textContaining('没有任何网络连接'), findsOneWidget);
    await teardownTree(tester);
  });

  test('进度条公式已改写为人话：文案常量里不出现 LaTeX 记号', () {
    expect(guideProgressbarBody.contains(r'\frac'), isFalse);
    expect(guideProgressbarBody.contains(r'$$'), isFalse);
    expect(guideProgressbarBody.contains('已规划'), isTrue);
  });

  testWidgets('sspai 外链：点按经外部浏览器打开文章地址', (tester) async {
    await pumpGuide(tester);

    await tester.tap(find.text(guideArticleLinkLabel));
    await tester.pump();

    expect(launchedUrl, kEnvelopeBudgetArticleUrl);
    // 打开成功：不出现兜底 toast
    expect(
      find.text(linkOpenFailedToast(kEnvelopeBudgetArticleUrl)),
      findsNothing,
    );
    await teardownTree(tester);
  });

  testWidgets('外链打不开：走既有 toast 兜底提示手动访问', (tester) async {
    launchOk = false;
    await pumpGuide(tester);

    await tester.tap(find.text(guideArticleLinkLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(linkOpenFailedToast(kEnvelopeBudgetArticleUrl)),
      findsOneWidget,
    );
    await teardownTree(tester);
  });
}
