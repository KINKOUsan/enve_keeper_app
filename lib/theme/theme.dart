import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// 由 design tokens 组装出的全 App 唯一 ThemeData。
/// 组件沿用 Material 3，视觉全部通过主题层覆盖。
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: T.primary,
      onPrimary: T.textPrimary,
      secondary: T.primaryMid,
      surface: T.surface,
      onSurface: T.textPrimary,
      error: T.overspend,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: T.bg,
  );

  return base.copyWith(
    // 中文观感由安卓系统字体（Noto Sans CJK）兜底，不额外指定字体族
    textTheme: base.textTheme.apply(
      bodyColor: T.textPrimary,
      displayColor: T.textPrimary,
    ),
    // 全局触摸反馈
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: T.border,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: T.surface,
      modalBackgroundColor: T.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(T.radiusSheet),
        ),
      ),
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: T.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(T.radiusCardLg),
      ),
      barrierColor: const Color(0x57000000), // 34% 黑
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: T.textPrimary,
      contentTextStyle: TextStyle(color: T.surface, fontSize: T.typeBase),
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: T.bg,
      indicatorColor: Colors.transparent,
      height: 80,
      elevation: 0,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: T.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? T.textPrimary : T.textSecondary,
        );
      }),
    ),
  );
}

/// 亮色 launch window 背景（AGENTS.md：冷启动直接进首页，原生背景用页面底色）
void configureSystemUi() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: T.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
}
