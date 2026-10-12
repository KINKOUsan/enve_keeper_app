// 桌面小组件的外观选项（v1.3.0 票 07）：字体颜色预设色板 + 按背景明暗的
// 默认建议。存 home_widget 数据侧的键值是 hex 字符串（原生 Color.parseColor）。
import 'package:flutter/material.dart';

/// 一个可选字体颜色：[id] 即存储与原生共用的 hex（#RRGGBB）
class WidgetFontColorOption {
  const WidgetFontColorOption(this.id, this.label);

  final String id;
  final String label;

  Color get color => _colorOf(id);

  static Color _colorOf(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xFFFFFFFF;
    return Color(0xFF000000 | v);
  }
}

/// 预设色板（票 07）：白 / 暖黑 / 明黄（主色）/ 暖白，四个够用且都压得住
/// 信封色的底；背景图（票 08）接入后同样适用。
const List<WidgetFontColorOption> kWidgetFontColors = [
  WidgetFontColorOption('#FFFFFF', '白色'),
  WidgetFontColorOption('#1F1C17', '暖黑'),
  WidgetFontColorOption('#FFC72B', '明黄'),
  WidgetFontColorOption('#FFF2D1', '暖白'),
];

/// 按背景明暗给默认建议：背景偏深 → 白字；偏浅 → 暖黑。
/// 亮度阈值 0.55：8 个信封主色都属中低亮度（白字），背景图/浅色时给暖黑。
String suggestWidgetFontColor(Color background) =>
    background.computeLuminance() < 0.55 ? kWidgetFontColors[0].id
        : kWidgetFontColors[1].id;
