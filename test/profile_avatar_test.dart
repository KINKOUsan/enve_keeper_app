// 头像替换回归（260922 修复）：setAvatarFrom 每次生成新文件名——
// 旧实现固定拷到 avatar.png 同名覆盖，路径不变导致 Image.file 按路径
// 命中旧缓存，表现为「选了图却不替换」「恢复默认后再选还是旧图」；
// 顺带验证旧头像文件清理与恢复默认删文件。
import 'dart:io';

import 'package:enve_keeper_app/state/profile.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avatar_test');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        // 注入临时支持目录（测试宿主上 path_provider 走平台 FFI，不可 mock）
        profileProvider.overrideWith(
          () => ProfileController(supportDirectory: () async => tempDir),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tempDir.delete(recursive: true));
  });

  // 在临时目录造一张假图源文件，返回其路径
  Future<String> makeSource(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  test('连续换两次头像：目标路径每次都不同，旧头像文件被清理', () async {
    final notifier = container.read(profileProvider.notifier);

    await notifier.setAvatarFrom(await makeSource('a.png', [1, 2, 3]));
    final first = container.read(profileProvider).avatarPath;
    expect(first, isNotEmpty);
    expect(File(first).readAsBytesSync(), [1, 2, 3]);

    await notifier.setAvatarFrom(await makeSource('b.png', [9, 9, 9]));
    final second = container.read(profileProvider).avatarPath;
    // 回归断言：路径必须变——同名覆盖会让图片缓存按路径命中旧图
    expect(second, isNot(first));
    expect(File(second).readAsBytesSync(), [9, 9, 9]);
    expect(File(first).existsSync(), isFalse);
    // 持久化同步到新路径
    expect(prefs.getString('profile.avatarPath'), second);
  });

  test('恢复默认头像：路径清空且私有目录文件被删', () async {
    final notifier = container.read(profileProvider.notifier);

    await notifier.setAvatarFrom(await makeSource('a.png', [1]));
    final path = container.read(profileProvider).avatarPath;
    expect(File(path).existsSync(), isTrue);

    await notifier.clearAvatar();
    expect(container.read(profileProvider).hasAvatar, isFalse);
    expect(File(path).existsSync(), isFalse);
    expect(prefs.getString('profile.avatarPath'), '');
  });
}
