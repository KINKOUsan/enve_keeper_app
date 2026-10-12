// 信封图标的位图预渲染（v1.3.0 票 05 / ADR-0021）：图标是 Material 字形
// （Flutter 侧字体），原生组件画不了——在 Dart 侧用 TextPainter +
// PictureRecorder 把白色字形画成 PNG，桌面组件以 ImageView 显示。
// 产物按 (图标 id, 边长) 缓存在应用支持目录 widget_icons/ 下，存在即复用。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/envelope_icons.dart';

/// 渲染一枚信封图标位图并返回文件绝对路径。
/// 图标恒为白色（画在信封主色底上）；票 16 起带柔和阴影（底衬移除后图标
/// 也是前景元素）。失败返回 null，组件降级为不显示图标。
/// 缓存文件名带 `-s` 代号：阴影参数变化时换代，防旧版无影缓存被复用。
Future<String?> rasterizeEnvelopeIcon({
  required String iconId,
  required Directory baseDir,
  int pixelSize = 96,
}) async {
  final dir = Directory('${baseDir.path}/widget_icons');
  await dir.create(recursive: true);
  final file = File('${dir.path}/env-icon-$iconId-s-$pixelSize.png');
  if (await file.exists()) return file.path;

  try {
    final icon = envelopeIconById(iconId);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          // 字形占画布约七成，四周留白避免贴边裁切
          fontSize: pixelSize * 0.7,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
          // 阴影对齐布局文字（柔和黑、下移、blur）
          shadows: [
            Shadow(
              color: const Color(0xB3000000),
              offset: Offset(0, pixelSize * 0.012),
              blurRadius: pixelSize * 0.04,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (pixelSize - painter.width) / 2,
        (pixelSize - painter.height) / 2,
      ),
    );
    final image = await recorder.endRecording().toImage(
      pixelSize,
      pixelSize,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  } on Exception {
    // 渲染失败（极端：字体不可用）：返回 null，不写半截文件
    return null;
  }
}
