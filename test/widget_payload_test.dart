// 桌面小组件·信封卡片数据负载 — 单测（v1.3.0 票 05 / ADR-0021）。
// 覆盖：金额展示形态（正 / 透支负号 / 隐藏遮蔽）、颜色 #RRGGBB、
// 默认绑定 = 第一个信封、计数键；图标位图的缓存命中路径（已存在文件直接复用）。
import 'dart:io';

import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/home_widget/icon_raster.dart';
import 'package:enve_keeper_app/home_widget/widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Envelope env(
    String id, {
    required String color,
    double planned = 100,
    double used = 40,
  }) => Envelope(
    id: id,
    name: '信封$id',
    icon: 'food',
    color: color,
    planned: planned,
    used: used,
    carryover: true,
  );

  group('信封卡片负载（ADR-0021：原生只显示，字符串全部算好再推）', () {
    test('基础负载：名字 / 金额 / 颜色 / 计数 / 默认绑定', () {
      final out = buildEnvelopeCardPayloads(
        envelopes: [env('e1', color: 'clay'), env('e2', color: 'teal', used: 130)],
        symbol: '¥',
        hiddenIds: const {},
        defaultId: 'e1',
      );
      expect(out[EnvelopeCardKeys.name('e1')], '信封e1');
      // 剩余 = 100 − 40
      expect(out[EnvelopeCardKeys.amount('e1')], '¥60');
      // 透支照记（不变量①）：负号 U+2212 前置
      expect(out[EnvelopeCardKeys.amount('e2')], '−¥30');
      expect(out[EnvelopeCardKeys.masked('e2')], '0');
      // 主色 #RRGGBB（clay = #C77D70，与 App 内信封主题色一致）
      expect(out[EnvelopeCardKeys.color('e1')], '#c77d70');
      expect(out[EnvelopeCardKeys.count], '2');
      // 默认绑定 = 第一个信封（票 05 临时绑定）
      expect(out[EnvelopeCardKeys.defaultBinding], 'e1');
    });

    test('隐藏开关命中的信封：金额走遮蔽形态（与 App 内同一开关）', () {
      final out = buildEnvelopeCardPayloads(
        envelopes: [env('e1', color: 'amber')],
        symbol: '¥',
        hiddenIds: const {'e1'},
      );
      expect(out[EnvelopeCardKeys.amount('e1')], '¥••••');
      expect(out[EnvelopeCardKeys.masked('e1')], '1');
      // 名字与颜色不藏（只藏数字）
      expect(out[EnvelopeCardKeys.name('e1')], '信封e1');
      expect(out[EnvelopeCardKeys.color('e1')], '#d6a354');
    });

    test('货币符号按账本跟随（ADR-0017）', () {
      final out = buildEnvelopeCardPayloads(
        envelopes: [env('e1', color: 'moss')],
        symbol: r'$',
        hiddenIds: const {},
      );
      expect(out[EnvelopeCardKeys.amount('e1')], r'$60');
    });

    test('空信封列表：无默认绑定键，计数为 0', () {
      final out = buildEnvelopeCardPayloads(
        envelopes: const [],
        symbol: '¥',
        hiddenIds: const {},
        defaultId: 'e1',
      );
      expect(out[EnvelopeCardKeys.count], '0');
      expect(out.containsKey(EnvelopeCardKeys.defaultBinding), isFalse);
    });
  });

  group('图标位图缓存', () {
    test('缓存命中：目标文件已存在时直接返回路径、不重渲染', () async {
      final dir = await Directory.systemTemp.createTemp('icon_raster_test');
      addTearDown(() => dir.delete(recursive: true));
      final cached = File(
        '${dir.path}/widget_icons/env-icon-food-s-96.png',
      )..createSync(recursive: true)
      ..writeAsBytesSync([1, 2]);

      final path = await rasterizeEnvelopeIcon(
        iconId: 'food',
        baseDir: dir,
      );
      expect(path, cached.path);
      // 内容未被重写（命中缓存不触发渲染管线）
      expect(cached.readAsBytesSync(), [1, 2]);
    });
  });
}
