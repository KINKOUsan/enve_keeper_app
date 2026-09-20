import 'package:flutter/material.dart';

/// 设计变量 — 从 design-tokens.css 逐条搬入，命名与 CSS 变量一一对应。
/// 不要手改颜色；改设计稿后重新导出再同步这里。
class T {
  T._();

  // ── 语义色 ─────────────────────────────────
  /// 页面底：暖白，不要用纯白
  static const Color bg = Color(0xFFFFFCF7);

  /// 卡片、弹层
  static const Color surface = Color(0xFFFFFFFF);

  /// 次级面：键盘键帽、标签底
  static const Color surfaceSubtle = Color(0xFFF7F2E8);

  /// 主色：只做点缀，禁止大面积铺
  static const Color primary = Color(0xFFFFC72B);

  /// 主色的浅底：待规划卡、选中态
  static const Color primarySoft = Color(0xFFFFF2D1);

  /// 主色上的深色文字
  static const Color primaryDeep = Color(0xFF8A6A00);

  /// 主色上的次级文字
  static const Color primaryMid = Color(0xFFBF9A3A);

  /// 暖黑，不要用 #000
  static const Color textPrimary = Color(0xFF1F1C17);
  static const Color textSecondary = Color(0xFF8A8278);
  static const Color textTertiary = Color(0xFFB5AB9E);
  static const Color border = Color(0xFFF0E8DB);

  /// 透支 / 缺口：红
  static const Color overspend = Color(0xFFE5474D);

  /// 收入：绿
  static const Color income = Color(0xFF17A673);

  /// 转移：灰（弱化，不参与收支语义）
  static const Color transfer = Color(0xFF8A8278);

  // ── 信封色（灰度较高的彩色，禁止提高饱和） ──
  static const Color envelopeClay = Color(0xFFC77D70);
  static const Color envelopeClayTint = Color(0xFFF5E8E5);
  static const Color envelopeAmber = Color(0xFFD6A354);
  static const Color envelopeAmberTint = Color(0xFFF7EDE0);
  static const Color envelopeMoss = Color(0xFF8FA87D);
  static const Color envelopeMossTint = Color(0xFFEBF0E8);
  static const Color envelopeTeal = Color(0xFF80A69C);
  static const Color envelopeTealTint = Color(0xFFE8F0ED);
  static const Color envelopeSlate = Color(0xFF7D94A8);
  static const Color envelopeSlateTint = Color(0xFFE8EDF0);
  static const Color envelopeMauve = Color(0xFFA68CA6);
  static const Color envelopeMauveTint = Color(0xFFF0EBF0);
  static const Color envelopeUmber = Color(0xFFA8856B);
  static const Color envelopeUmberTint = Color(0xFFF0E8E5);
  static const Color envelopeRose = Color(0xFFB58C94);
  static const Color envelopeRoseTint = Color(0xFFF2EBED);

  // ── 圆角 ───────────────────────────────────
  /// 信封卡
  static const double radiusCard = 18;

  /// 待规划卡
  static const double radiusCardLg = 20;

  /// 卡内图标块
  static const double radiusChip = 8;

  /// 数字键盘弹层（仅上方两角）
  static const double radiusSheet = 28;

  /// 键帽
  static const double radiusKey = 12;

  /// 进度条
  static const double radiusBar = 3;
  static const double radiusPill = 999;

  // ── 间距 ───────────────────────────────────
  static const double spaceXs = 4;
  static const double spaceSm = 8;

  /// 页面左右边距等常用间距
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;

  // ── 字号 ───────────────────────────────────
  /// 辅助说明、标签
  static const double typeXs = 11;

  /// 信封名
  static const double typeSm = 12;

  /// 正文、键帽辅助
  static const double typeBase = 13;

  /// 弹层标题、确定键
  static const double typeMd = 15;

  /// 卡片金额
  static const double typeLg = 19;

  /// 页面标题
  static const double typeXl = 22;

  /// 待规划金额
  static const double typeXxl = 32;
}

/// 透支提示条专用色（DESIGN.md §10）
class DangerTint {
  DangerTint._();
  static const Color bg = Color(0xFFFDECEC);
  static const Color border = Color(0xFFF6C9CB);
  static const Color text = Color(0xFFB33236);
}

/// 信封的 8 个可选色：主色 + 18% 浅底成对出现。
/// `id` 存库用，信封表里的 `color` 字段就是它。
class EnvelopeColor {
  const EnvelopeColor(this.id, this.main, this.tint);
  final String id;
  final Color main;
  final Color tint;

  /// 主色按给定透明度合成（用于进度槽 18% 等场景）
  Color withAlpha(double opacity) => main.withValues(alpha: opacity);
}

/// 8 个信封色目录，顺序即设计稿顺序
const List<EnvelopeColor> kEnvelopeColors = [
  EnvelopeColor('clay', T.envelopeClay, T.envelopeClayTint),
  EnvelopeColor('amber', T.envelopeAmber, T.envelopeAmberTint),
  EnvelopeColor('moss', T.envelopeMoss, T.envelopeMossTint),
  EnvelopeColor('teal', T.envelopeTeal, T.envelopeTealTint),
  EnvelopeColor('slate', T.envelopeSlate, T.envelopeSlateTint),
  EnvelopeColor('mauve', T.envelopeMauve, T.envelopeMauveTint),
  EnvelopeColor('umber', T.envelopeUmber, T.envelopeUmberTint),
  EnvelopeColor('rose', T.envelopeRose, T.envelopeRoseTint),
];

/// 按 id 查信封色，未知 id 回落到陶土红
EnvelopeColor envelopeColorById(String id) => kEnvelopeColors.firstWhere(
  (c) => c.id == id,
  orElse: () => kEnvelopeColors.first,
);
