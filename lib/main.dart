import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/providers.dart';
import 'theme/theme.dart';

/// 应用入口 — 冷启动直接进首页（AGENTS.md：没有启动页）。
/// 开发期全局错误捕获：任何未捕获异常都会显示在屏幕上，避免「黑屏无信息」。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemUi();

  // 框架异常（build/layout/paint 阶段）：既打印控制台，也改写屏幕上的错误页
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // 保留 debug 红屏
    debugPrint('── FlutterError ──────────────────────────');
    debugPrint(details.toString());
    debugPrint('──────────────────────────────────────────');
  };
  // 非 widget 异步异常（async 回调 / isolate 未捕获）
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('── Uncaught async error ──────────────────');
    debugPrint('$error\n$stack');
    debugPrint('──────────────────────────────────────────');
    return true;
  };

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const JinDaXiSuanApp(),
    ),
  );
}
