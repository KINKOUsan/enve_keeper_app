// 关于页 widget 测试（票 07）：静态结构 + 版本号注入 + 头像本地资产（票 10）
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/shell/profile/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

// 作者头像（本地资产）的 Finder（票 10 起头像不再走网络）
Finder avatarAssetFinder() => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == kAvatarAsset,
);

void main() {
  // 版本信息替身（业务里来自 package_info_plus 平台通道）
  final fakeInfo = PackageInfo(
    appName: 'enve_keeper_app',
    packageName: 'com.example.enve_keeper_app',
    version: '9.9.9',
    buildNumber: '1',
  );

  // 挂载关于页（override 版本 provider）并等数据就绪
  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWith((_) => Future.value(fakeInfo)),
        ],
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('关于页渲染：名称/版本/作者/反馈/许可与 App 图标', (tester) async {
    await pumpAbout(tester);

    // App 卡：名称 + 注入的版本号
    expect(find.text('金打细算'), findsOneWidget);
    expect(find.text('v9.9.9'), findsOneWidget);
    // 作者卡
    expect(find.text('@KINKOUsan'), findsOneWidget);
    expect(find.text('GitHub 主页'), findsOneWidget);
    // 动作行
    expect(find.text('意见反馈'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    // assets 图 2 张：App 方格图标 + 作者头像（票 10 起头像为本地资产）
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is AssetImage),
      findsNWidgets(2),
    );
    // 作者头像明确指向本地资产（回归：曾走 GitHub CDN 在线加载，国内不可达）
    expect(avatarAssetFinder(), findsOneWidget);
  });

  testWidgets('作者头像为本地资产，离线可用（票 10）', (tester) async {
    await pumpAbout(tester);

    // 本地资产同步解码，无需网络；不应再出现首字母占位「K」
    expect(find.text('K'), findsNothing);
    expect(avatarAssetFinder(), findsOneWidget);
  });
}
