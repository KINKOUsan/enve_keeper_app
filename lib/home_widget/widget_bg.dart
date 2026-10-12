// 小组件背景图（v1.3.0 票 08 / ADR-0021）：编辑页选图 → 裁剪（票 04 基建，
// 按组件比例）→ 圆角化 → 存应用私有目录（唯一文件名）→ 路径写进实例配置。
// 属设备本地装饰数据，不进 .jx 备份（.jx 只含 drift 表，天然不含）。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 组件背景的圆角比例（18dp / 110dp ≈ 0.16，与布局 drawable 的 18dp 圆角一致）
const double _kCornerRatio = 0.16;

int _seq = 0;

/// 把裁剪结果（PNG 字节）圆角化并存入私有目录，返回文件绝对路径。
/// [oldPath] 非空时替换成功后清理旧背景（best effort）。
/// 失败返回 null（调用方保持原背景不变）。
Future<String?> saveWidgetBackground({
  required Uint8List bytes,
  required Directory baseDir,
  String? oldPath,
}) async {
  try {
    final rounded = await _roundCorners(bytes);
    if (rounded == null) return null;
    final dir = Directory('${baseDir.path}/widget_bg');
    await dir.create(recursive: true);
    // 唯一文件名：编辑页预览用 Image.file，路径换新才能绕开图片缓存
    final target =
        '${dir.path}/bg-${DateTime.now().millisecondsSinceEpoch}-${_seq++}.png';
    await File(target).writeAsBytes(rounded);
    if (oldPath != null && oldPath.isNotEmpty && oldPath != target) {
      try {
        await File(oldPath).delete();
      } on FileSystemException {
        // 旧文件清理失败不影响新背景生效
      }
    }
    return target;
  } on Exception {
    return null;
  }
}

/// 删除一个背景文件（清除背景时调用；best effort）
Future<void> deleteWidgetBackground(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    await File(path).delete();
  } on FileSystemException {
    // 文件不存在就算了
  }
}

// 圆角化：解码 → clipRRect → 重编码 PNG（保持原尺寸，角落透明）
Future<Uint8List?> _roundCorners(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  final w = img.width;
  final h = img.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final radius = Radius.circular(math.min(w, h) * _kCornerRatio);
  canvas.clipRRect(
    RRect.fromRectAndRadius(
      Offset.zero & Size(w.toDouble(), h.toDouble()),
      radius,
    ),
  );
  canvas.drawImage(img, Offset.zero, Paint()..isAntiAlias = true);
  final out = await recorder.endRecording().toImage(w, h);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
