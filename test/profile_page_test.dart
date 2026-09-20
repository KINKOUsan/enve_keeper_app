// 我的页 + 编辑资料页 widget 测试（profile-polish 票）：
// ① 用户卡默认渲染（默认昵称/签名）与「每月提醒」移除回归；
// ② 编辑资料保存后回退并生效；③ 头像恢复按钮的出现条件与清空动作。
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/state/profile.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';
import 'package:enve_keeper_app/ui/shell/profile/profile_edit_page.dart';
import 'package:enve_keeper_app/ui/shell/profile/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 版本信息替身（业务里来自 package_info_plus 平台通道）
  final fakeInfo = PackageInfo(
    appName: 'enve_keeper_app',
    packageName: 'com.example.enve_keeper_app',
    version: '9.9.9',
    buildNumber: '1',
  );

  // 泵起「我的」页：真实内存数据库 + 真实 provider 树 + 注入版本号
  Future<ProviderContainer> pumpProfile(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);

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

    // 建默认账本并激活（与 app.dart _bootstrap 一致）
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfilePage)),
    );
    final ledger = await container.read(repoProvider).ensureBootstrap();
    await container.read(activeLedgerIdProvider.notifier).set(ledger.id);
    await tester.pumpAndSettle();
    return container;
  }

  // 泵起编辑资料页（挂在有底页的导航栈上，保存后能验证 pop）
  Future<ProviderContainer> pumpEdit(
    WidgetTester tester, {
    Map<String, Object> prefsSeed = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefsSeed);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileEditPage(),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('go')));
  }

  // 测试区收尾：卸载整棵树并排干 drift 流查询的 0ms 计时器
  Future<void> unmountTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('我的页默认渲染：默认昵称/签名，且「每月提醒」已移除', (tester) async {
    await pumpProfile(tester);

    // 用户卡回退默认文案（直接断言 copy.dart 常量，杜绝文案与测试不同步）
    expect(find.text(defaultNickname), findsOneWidget);
    expect(find.text(defaultSignature), findsOneWidget);
    // 「每月提醒」静态占位行不再出现（profile-polish 票回归）
    expect(find.text('每月提醒'), findsNothing);

    await unmountTree(tester);
  });

  testWidgets('编辑资料：填昵称与签名保存后 pop 并生效', (tester) async {
    final container = await pumpEdit(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 两个输入框：第 1 个昵称、第 2 个签名
    await tester.enterText(find.byType(TextField).at(0), '阿金');
    await tester.enterText(find.byType(TextField).at(1), '把每块钱都安排明白');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // pop 回到底页
    expect(find.byType(ProfileEditPage), findsNothing);
    // 控制器状态已更新
    expect(container.read(profileProvider).nickname, '阿金');
    expect(container.read(profileProvider).signature, '把每块钱都安排明白');

    await unmountTree(tester);
  });

  testWidgets('编辑资料：设置过头像才显示「恢复默认头像」，点击后路径清空', (tester) async {
    final container = await pumpEdit(
      tester,
      prefsSeed: {'profile.avatarPath': 'C:/nonexistent/avatar.png'},
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('恢复默认头像'), findsOneWidget);
    await tester.tap(find.text('恢复默认头像'));
    await tester.pumpAndSettle();

    expect(container.read(profileProvider).hasAvatar, isFalse);
    // 默认人像回退：不再渲染任何 Image.file
    expect(find.byType(Image), findsNothing);

    await unmountTree(tester);
  });

  testWidgets('未设置头像时不显示「恢复默认头像」按钮', (tester) async {
    await pumpEdit(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('恢复默认头像'), findsNothing);

    await unmountTree(tester);
  });

  // ── 货币符号（v1.2.0 票 02 / ADR-0017）──

  testWidgets('货币符号：设置行显示当前符号，预置选择后写库生效', (tester) async {
    final container = await pumpProfile(tester);
    final ledger = container.read(activeLedgerProvider)!;

    // 设置行右侧值 = 当前账本符号（默认 ¥）
    final rowLabel = find.text('货币符号');
    expect(rowLabel, findsOneWidget);
    expect(find.text('¥'), findsWidgets);

    // 打开对话框：正文注明作用域，预置 ¥ 已选中
    await tester.tap(rowLabel);
    await tester.pumpAndSettle();
    expect(
      find.text(currencyDialogBody(ledger.name)),
      findsOneWidget,
    );

    // 选 $ 并确定
    await tester.tap(find.text('\$'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 库已写入 + 提示行值跟随
    final setting = await (container.read(dbProvider).select(
      container.read(dbProvider).appSettings,
    )..where((s) => s.ledgerId.equals(ledger.id))).getSingle();
    expect(setting.currency, '\$');
    expect(find.text('\$'), findsWidgets);
    expect(find.text(currencySavedToast), findsOneWidget);

    await unmountTree(tester);
  });

  testWidgets('货币符号：自定义输入 3 字符（HK\$）去空白后可保存', (tester) async {
    final container = await pumpProfile(tester);
    final ledger = container.read(activeLedgerProvider)!;

    await tester.tap(find.text('货币符号'));
    await tester.pumpAndSettle();
    // 首尾空格不占字符预算：去空白后 HK$ 恰好 3 字符
    await tester.enterText(find.byType(TextField).first, ' HK\$ ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final setting = await (container.read(dbProvider).select(
      container.read(dbProvider).appSettings,
    )..where((s) => s.ledgerId.equals(ledger.id))).getSingle();
    expect(setting.currency, 'HK\$');

    await unmountTree(tester);
  });

  testWidgets('货币符号：去空白后超 3 字符 → 提示且确定置灰', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('货币符号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'USDT');
    await tester.pumpAndSettle();

    // 超长提示出现
    expect(find.text(currencyTooLongHint), findsOneWidget);
    // 确定键置灰（onPressed == null），点击后对话框不关闭
    final ok = tester.widget<TextButton>(
      find.ancestor(of: find.text('确定'), matching: find.byType(TextButton)),
    );
    expect(ok.onPressed, isNull);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('货币符号'), findsWidgets); // 对话框仍在

    await unmountTree(tester);
  });
}
