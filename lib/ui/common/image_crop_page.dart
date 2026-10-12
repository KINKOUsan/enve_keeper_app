// 图片裁剪页（v1.3.0 票 04）——头像与桌面小组件背景共用的裁剪基建。
// 纯 Flutter 实现（crop_your_image，无原生依赖）：拖动平移 + 双指缩放，
// 裁剪框按传入比例锁定；结果统一经 dart:ui 重编码为 PNG 并限制最大边长
// （控制私有目录文件体积）。取消 / 返回 → null，调用方不改动原图。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'app_route.dart';

/// 打开裁剪页。[image] 原图字节；[aspectRatio] 裁剪框宽高比（头像 1:1、
/// 小组件背景按组件比例）；[maxSide] 结果最大边长（等比缩放）。
/// 返回裁剪结果（PNG 字节）；取消返回 null。
Future<Uint8List?> showImageCropPage(
  BuildContext context, {
  required Uint8List image,
  required double aspectRatio,
  String title = '裁剪图片',
  int maxSide = 1024,
}) {
  return Navigator.of(
    context,
  ).push<Uint8List>(AppPageRoute(builder: (_) => _ImageCropPage(
        image: image,
        aspectRatio: aspectRatio,
        title: title,
        maxSide: maxSide,
      )));
}

class _ImageCropPage extends StatefulWidget {
  const _ImageCropPage({
    required this.image,
    required this.aspectRatio,
    required this.title,
    required this.maxSide,
  });

  final Uint8List image;
  final double aspectRatio;
  final String title;
  final int maxSide;

  @override
  State<_ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<_ImageCropPage> {
  final _controller = CropController();

  // 解析中禁用「使用」（crop_your_image 先解码原图，ready 后才可裁）
  CropStatus _status = CropStatus.nothing;

  @override
  Widget build(BuildContext context) {
    final ready = _status == CropStatus.ready;
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: Text(widget.title)),
      body: Crop(
        image: widget.image,
        controller: _controller,
        onCropped: (result) {
          switch (result) {
            case CropSuccess():
              _finish(result.croppedImage);
            case CropFailure():
              // 解码 / 裁剪失败（文件损坏等）：回退原 图，让上层照旧展示
              Navigator.of(context).pop(widget.image);
          }
        },
        onStatusChanged: (s) => setState(() => _status = s),
        aspectRatio: widget.aspectRatio,
        interactive: true,
        fixCropRect: true,
        maskColor: const Color(0x96000000),
        baseColor: T.bg,
        radius: 12,
      ),
      // 底部操作：取消 + 使用（与时间滚轮弹层底部同款按钮语言）
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: T.surfaceSubtle,
                    foregroundColor: T.textSecondary,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(T.radiusKey),
                    ),
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: ready
                      ? () {
                          setState(() => _status = CropStatus.cropping);
                          _controller.crop();
                        }
                      : null,
                  style: TextButton.styleFrom(
                    backgroundColor: T.primary,
                    foregroundColor: T.textPrimary,
                    disabledBackgroundColor: const Color(0xFFF3EFE7),
                    disabledForegroundColor: const Color(0xFFCCC4B8),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(T.radiusKey),
                    ),
                  ),
                  child: const Text(
                    '使用',
                    style: TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 裁剪完成：重编码为 PNG（并等比缩到最大边长）后交回
  Future<void> _finish(Uint8List bytes) async {
    final png = await _encodePng(bytes, widget.maxSide);
    if (!mounted) return;
    Navigator.of(context).pop(png ?? bytes);
  }

  // 解码 → 等比缩放 → PNG 字节；失败返回 null（调用方回退原图字节）
  Future<Uint8List?> _encodePng(Uint8List bytes, int maxSide) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      final scale = maxSide / (w > h ? w : h);
      final codec = scale < 1
          ? await descriptor.instantiateCodec(
              targetWidth: (w * scale).round(),
              targetHeight: (h * scale).round(),
            )
          : await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } on Exception {
      return null;
    }
  }
}
