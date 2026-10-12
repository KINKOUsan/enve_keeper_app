// 桌面小组件点击路由与外观选项 — 单测（v1.3.0 票 06/07）。
// 覆盖：URI 解析（快速记账 / 编辑组件 / 非本 App 路由的拒绝）、
// 字色建议按背景明暗分流、色板 hex 可还原为 Color。
import 'package:enve_keeper_app/home_widget/widget_routes.dart';
import 'package:enve_keeper_app/home_widget/widget_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('组件点击路由解析', () {
    test('快速记账：envekeeper://quick-record?env=<id>', () {
      final route = parseWidgetUri(
        Uri.parse('envekeeper://quick-record?env=env-123'),
      );
      expect(route, isA<WidgetQuickRecord>());
      expect((route as WidgetQuickRecord).envelopeId, 'env-123');
    });

    test('编辑组件：envekeeper://widget-edit?id=<appWidgetId>', () {
      final route = parseWidgetUri(
        Uri.parse('envekeeper://widget-edit?id=42'),
      );
      expect(route, isA<WidgetEditRoute>());
      expect((route as WidgetEditRoute).widgetId, 42);
    });

    test('看统计：envekeeper://open-stats（票 15）', () {
      final route = parseWidgetUri(Uri.parse('envekeeper://open-stats'));
      expect(route, isA<WidgetStatsRoute>());
    });

    test('非本 App 的路由一律拒绝（null  scheme 不对 / 缺参 / 非数字 id）', () {
      expect(parseWidgetUri(null), isNull);
      expect(parseWidgetUri(Uri.parse('https://example.com')), isNull);
      expect(parseWidgetUri(Uri.parse('other://quick-record?env=1')), isNull);
      expect(parseWidgetUri(Uri.parse('envekeeper://unknown?x=1')), isNull);
      expect(parseWidgetUri(Uri.parse('envekeeper://quick-record')), isNull);
      expect(
        parseWidgetUri(Uri.parse('envekeeper://widget-edit?id=abc')),
        isNull,
      );
    });
  });

  group('字色建议（按背景明暗）', () {
    test('偏深背景 → 白字；偏浅背景 → 暖黑', () {
      // 信封主色都偏中低亮度（8 色）→ 白
      expect(suggestWidgetFontColor(const Color(0xFFC77D70)), '#FFFFFF');
      // 浅背景（暖白底）→ 暖黑
      expect(suggestWidgetFontColor(const Color(0xFFFFF2D1)), '#1F1C17');
    });

    test('色板 hex 都能还原为对应颜色', () {
      for (final option in kWidgetFontColors) {
        final v = int.parse(
          option.id.replaceFirst('#', ''),
          radix: 16,
        );
        expect(option.color, Color(0xFF000000 | v), reason: option.id);
      }
    });
  });
}
