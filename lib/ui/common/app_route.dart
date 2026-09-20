// 全 App 统一的推入页路由（DESIGN.md §4 2026-09-20 增补 · v1.2.x 票 01）：
// 转场时长由 Material 默认 300ms 缩短到 180ms，动画形态沿用平台默认——
// 压缩「返回首页后立刻点信封、点击被转场吸收」的窗口。
import 'package:flutter/material.dart';

/// 所有推入页（信封详情 / 流水详情 / 周期设置 / 账本 / 备份 / 关于 / 资料编辑）
/// 统一用 [AppPageRoute] 替代 MaterialPageRoute，其余行为完全一致。
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required super.builder, super.settings});

  // push 与 pop 同为 180ms，进出方向对称、无跳变
  static const Duration _fast = Duration(milliseconds: 180);

  @override
  Duration get transitionDuration => _fast;

  @override
  Duration get reverseTransitionDuration => _fast;
}
