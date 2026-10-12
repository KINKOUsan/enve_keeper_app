// 统计卡片可视化位图渲染（v1.3.0 票 09 / ADR-0021）：原生组件画不了矢量
// 图形，环形图/柱状图在 Dart 侧用 PictureRecorder 画成透明底 PNG 推送，
// 原生 ImageView 直接显示（叠在组件底色/背景图之上）。
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'stats_payload.dart';

/// 渲染一张统计卡可视化位图并落盘，返回文件绝对路径。
/// 环形图走方形出图（432×432px = 144 逻辑像素 ×3）；
/// 柱状图走**宽幅**出图（票 15：拉长 + 底部日期轴，720×384px = 240×128
/// 逻辑像素 ×3，与 4×2 卡片里图表盒的显示尺寸匹配）。
/// [chart] 决定环形 / 柱状；数据来自 [WidgetStatsData]。
Future<String?> renderStatsChartBitmap({
  required WidgetStatsData data,
  required WidgetStatsChart chart,
  required Directory baseDir,
  required int widgetId,
}) async {
  try {
    final w = chart == WidgetStatsChart.ring ? 432 : 720;
    final h = chart == WidgetStatsChart.ring ? 432 : 384;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (chart == WidgetStatsChart.ring) {
      _paintRing(canvas, w, data);
    } else {
      _paintBars(canvas, w, h, data);
    }
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final dir = Directory('${baseDir.path}/widget_stats');
    await dir.create(recursive: true);
    // 固定文件名原地覆盖：原生每次解码新文件，无图片缓存问题
    final file = File('${dir.path}/stats-$widgetId.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  } on Exception {
    return null;
  }
}

// 环形图：各信封支出占比的甜甜圈（色块用信封主题色），无支出的空轨。
// 半径要给描边留出余量：外缘 = radius + stroke/2 必须落在画布内，
// 否则环顶满位图边缘、显示时贴住标签与进度条（261011 用户反馈「溢出」实因）。
// 票 16：无底衬后由阴影保证可读——彩色弧段先全部画阴影 pass（柔和黑、
// 下移、blur，与原生文字阴影同语言）再画正色，避免相邻弧的影子压住前一段。
void _paintRing(Canvas canvas, int px, WidgetStatsData data) {
  final c = Offset(px / 2, px / 2);
  final stroke = px * 0.16;
  final margin = px * 0.04;
  final radius = px / 2 - stroke / 2 - margin;
  final rect = Rect.fromCircle(center: c, radius: radius);
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..isAntiAlias = true;

  final total = data.ringShares.fold<double>(0, (s, e) => s + e.value);
  if (total <= 0) {
    // 空态：整圈半透明白轨（背景性质的轨道不画影）
    paint.color = const Color(0x59FFFFFF);
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    return;
  }

  // 弧段几何：先算好，影子 pass 与正色 pass 共用
  const gap = 0.03; // 弧段间细缝，避免低分辨率下糊成一体
  final segments = <({double start, double sweep, Color color})>[];
  var start = -math.pi / 2;
  for (final share in data.ringShares) {
    final sweep = (share.value / total) * math.pi * 2;
    segments.add((
      start: start + gap / 2,
      sweep: math.max(sweep - gap, 0.001),
      color: _colorOf(share.colorHex),
    ));
    start += sweep;
  }

  // 底轨（极细一圈，衬托缺口的“未支出”部分；背景性质不画影）
  paint.color = const Color(0x33FFFFFF);
  canvas.drawArc(rect, 0, math.pi * 2, false, paint);

  // 阴影 pass：整圈偏移下移，blur 出柔和黑（对齐布局文字阴影的观感）
  canvas.save();
  canvas.translate(0, px * 0.012);
  paint
    ..color = const Color(0x66000000)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.02);
  for (final seg in segments) {
    canvas.drawArc(rect, seg.start, seg.sweep, false, paint);
  }
  canvas.restore();

  // 正色 pass
  paint.maskFilter = null;
  for (final seg in segments) {
    paint.color = seg.color;
    canvas.drawArc(rect, seg.start, seg.sweep, false, paint);
  }
}

// 柱状图（票 15 参考图样式）：宽幅画布、柱列**按根数均分 X 轴**（票 16 追加：
// 此前柱宽带 5.5% 上限，7 根柱的周/近7日视图挤在左边——上限只服务过 31 根的
// 月视图，改为槽位均分后月视图不变、短区间铺满全轴）、当前日/月琥珀高亮、
// 底部基线 + 日期轴标签（按日「10.5」/按月「1月」，柱多时抽稀、末柱必标）。
void _paintBars(Canvas canvas, int w, int h, WidgetStatsData data) {
  final values = data.barValues;
  if (values.isEmpty) return;
  final labels = data.barLabels;
  final labelH = h * 0.18; // 底部日期轴带高
  final pad = w * 0.02;
  final topPad = h * 0.04;
  final baseline = h - labelH;
  final usableW = w - pad * 2;
  // 每根柱一个等宽槽位，柱子在槽内居中、槽间留缝——根数不同都铺满全轴
  final slot = usableW / values.length;
  final gap = math.min(usableW * 0.012, slot * 0.25);
  final barW = math.max(slot - gap, 1.0);
  double slotCenter(int i) => pad + i * slot + slot / 2;
  final maxV = values.fold<double>(0, math.max);
  final maxH = baseline - topPad;

  // 柱：底部对齐基线，高度按峰值归一；无支出跳过（空区间只剩基线+日期，
  // 与参考图的空态一致）。票 16：先收集矩形，全部影子画完再画正色。
  final rects = <({Rect rect, bool isCurrent})>[];
  for (var i = 0; i < values.length; i++) {
    final x = pad + i * slot + (slot - barW) / 2;
    final bar = maxV <= 0 ? 0.0 : (values[i] / maxV) * maxH;
    if (bar <= 0) continue;
    rects.add((
      rect: Rect.fromLTWH(x, baseline - bar, barW, bar),
      isCurrent: i == data.barCurrentIndex,
    ));
  }

  // 阴影 pass（对齐布局文字阴影的观感）
  final shadowPaint = Paint()
    ..color = const Color(0x66000000)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.008)
    ..isAntiAlias = true;
  // 柱顶圆角：细柱取半圆，宽柱封顶（7 根柱的槽位下全圆穹顶过圆）
  final rad = Radius.circular(math.min(barW / 2, h * 0.03));
  canvas.save();
  canvas.translate(0, h * 0.008);
  for (final r in rects) {
    canvas.drawRRect(
      RRect.fromRectAndCorners(r.rect, topLeft: rad, topRight: rad),
      shadowPaint,
    );
  }
  canvas.restore();

  // 正色 pass
  for (final r in rects) {
    final paint = Paint()
      ..color = r.isCurrent ? const Color(0xFFFFC72B) : const Color(0xCCFFD98A)
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndCorners(r.rect, topLeft: rad, topRight: rad),
      paint,
    );
  }

  // 基线：半透明白，垫住柱底
  final line = Paint()
    ..color = const Color(0x66FFFFFF)
    ..strokeWidth = math.max(w * 0.003, 2.0)
    ..isAntiAlias = true;
  canvas.drawLine(Offset(pad, baseline), Offset(w - pad, baseline), line);

  // 日期轴（票 15 二轮修订）：贪心防重叠布局——按柱序依次尝试绘制，
  // 与前一个已绘标签间距不足就跳过；末柱（今天/本月，参考图最右）优先占位，
  // 其余标签不得侵入它的领地。此前按固定步长抽稀，月视图 31 柱时
  // 「10.2110.25」挤成一团（261011 用户反馈）。
  if (labels.isEmpty || labels.length != values.length) return;
  final fs = labelH * 0.48;

  TextPainter labelPainter(String text, {required bool highlight}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fs,
          color: highlight
              ? const Color(0xFFFFC72B)
              : const Color(0xB3FFFFFF),
          fontWeight: FontWeight.w500,
          // 票 16：日期轴也是前景文本——阴影对齐布局文字（柔和黑、下移、blur）
          shadows: [
            Shadow(
              color: const Color(0xB3000000),
              offset: Offset(0, math.max(1.0, fs * 0.08)),
              blurRadius: fs * 0.25,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  double dxOf(TextPainter tp, int i) {
    final cx = slotCenter(i);
    return (cx - tp.width / 2).clamp(pad, w - pad - tp.width);
  }

  // 末柱优先占位
  final lastTp = labelPainter(
    labels.last,
    highlight: values.length - 1 == data.barCurrentIndex,
  );
  final lastDx = dxOf(lastTp, values.length - 1);
  final lastStart = lastDx - fs * 0.3; // 标签左缘再留小半字间隙
  lastTp.paint(
    canvas,
    Offset(lastDx, h - labelH + (labelH - lastTp.height) / 2),
  );

  var lastEnd = -double.infinity;
  for (var i = 0; i < values.length - 1; i++) {
    final tp = labelPainter(
      labels[i],
      highlight: i == data.barCurrentIndex,
    );
    final dx = dxOf(tp, i);
    if (dx + tp.width > lastStart) continue; // 侵入末柱标签领地
    if (dx < lastEnd + fs * 0.3) continue; // 与前一标签重叠
    tp.paint(canvas, Offset(dx, h - labelH + (labelH - tp.height) / 2));
    lastEnd = dx + tp.width;
  }
}

Color _colorOf(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xB5AB9E;
  return Color(0xFF000000 | v);
}

/// 渲染执行进度条位图并落盘（返回文件绝对路径）。
/// 全宽细条：半透明白轨 + 琥珀填充按 [progress]（0–100）截断。
/// 进度条不用原生 ProgressBar：国产定制桌面（ColorOS/MIUI 等）对它的渲染
/// 不稳定，是「载入窗口小部件时出现问题」的已知触发点——预渲染 PNG 最稳。
Future<String?> renderStatsProgressBar({
  required int progress,
  required Directory baseDir,
  required int widgetId,
  int logicalWidth = 240,
  int logicalHeight = 5,
}) async {
  try {
    final w = logicalWidth * 3;
    final h = logicalHeight * 3;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // 画布留 2px 影子余量：内容整体内缩，避免 blur 出界被裁
    const inset = 2.0;
    canvas.translate(inset, inset);
    final innerW = w - inset * 2;
    final innerH = h - inset * 2;
    final innerRadius = Radius.circular(innerH / 2);
    // 阴影 pass（票 16：进度条也是前景元素）
    final shadowPaint = Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & ui.Size(innerW.toDouble(), innerH.toDouble()),
        innerRadius,
      ),
      shadowPaint,
    );
    // 轨
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & ui.Size(innerW.toDouble(), innerH.toDouble()),
        innerRadius,
      ),
      Paint()..color = const Color(0x33FFFFFF),
    );
    // 填充
    final fill = (innerW * progress.clamp(0, 100) / 100).round();
    if (fill > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & ui.Size(fill.toDouble(), innerH.toDouble()),
          innerRadius,
        ),
        Paint()..color = const Color(0xFFFFC72B),
      );
    }
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final dir = Directory('${baseDir.path}/widget_stats');
    await dir.create(recursive: true);
    final file = File('${dir.path}/stats-$widgetId-bar.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  } on Exception {
    return null;
  }
}
