import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/providers.dart';
import 'theme/theme.dart';
import 'ui/shell/widgets/quick_record_overlay.dart';

/// 应用入口 — 冷启动直接进首页（AGENTS.md：没有启动页）。
/// 开发期全局错误捕获：任何未捕获异常都会显示在屏幕上，避免「黑屏无信息」。
///
/// 悬浮快速记账（v1.3.0 票 14）：QuickRecordActivity 以初始路由透传
/// `envekeeper://quick-record?env=<id>&w=<appWidgetId>`——按它分流进
/// 悬浮模式（透明浮层里记账，记完回桌面），不装配主 App 外壳。
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
  final initialRoute = PlatformDispatcher.instance.defaultRouteName;
  // 路由不靠引擎初始路由兜底（QuickRecordActivity.getInitialRoute 透传在部分
  // 链路上未按预期到达 defaultRouteName，261011 真机点击落在主装配）——
  // 直接问原生要启动 intent 的 data（仅浮层 Activity 注册该处理器）
  String? overlayUri = initialRoute.startsWith('envekeeper://quick-record')
      ? initialRoute
      : null;
  if (overlayUri == null) {
    try {
      overlayUri = await const MethodChannel('enve_keeper_app/quick_record')
          .invokeMethod<String>('initialIntentData');
    } on Exception {
      overlayUri = null; // 主引擎没注册：走正常装配
    }
  }
  debugPrint('── main 分支：overlayUri=$overlayUri defaultRoute=$initialRoute');
  if (overlayUri != null && overlayUri.startsWith('envekeeper://quick-record')) {
    final uri = Uri.parse(overlayUri);
    runApp(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: QuickRecordOverlayApp(
          envelopeId: uri.queryParameters['env'],
          widgetId: int.tryParse(uri.queryParameters['w'] ?? ''),
        ),
      ),
    );
    return;
  }
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const JinDaXiSuanApp(),
    ),
  );
}
