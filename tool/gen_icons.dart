// 启动图标资产生成脚本（票 06；v1.2.0 票 09 起源为根 logo.svg 的栅格化单张方格）
// 源图 logo.png（440×440，由根 logo.svg 经 headless Chrome 栅格化，圆角外透明），
// 产出：
//   1. Android 旧式 mipmap ic_launcher.png（5 档密度，合成不透明米白底——
//      透明角落会被部分 ROM 启动器垫黑底）
//   2. Android 自适应图标（5 档）：
//      背景层 ic_launcher_background.png = 满幅米白（部分启动器对 @color 背景渲染成黑色），
//      前景 ic_launcher_foreground.png = 信封+¥徽章居中安全区
//      分层见 mipmap-anydpi-v26/ic_launcher.xml
//   3. iOS AppIcon 全尺寸（不透明米白底，圆角交由系统遮罩）
// 用法：先由 logo.svg 重出 logo.png（见 .scratch/v1.2.0/issues/09），再 dart run tool/gen_icons.dart
// 资产已入库，日常开发无需重跑；改 logo 后重跑一次即可。
import 'dart:io';

import 'package:image/image.dart' as img;

// 图标底色（与 logo 方格底一致，暖米白；v1.2.0 票 09 起 #FFFDF7 以 logo.svg 为准）
final _bg = img.ColorRgba8(0xFF, 0xFD, 0xF7, 0xFF);

// 源图路径与方格尺寸（440 = 旧 220 源的 2 倍：自适应前景 285px 不再上采样）
const _sourcePath = 'logo.png';
const _tileSize = 440;

// Android 旧式图标密度 → 边长（48dp 基准）
const _legacySizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

// 自适应图标画布（108dp 基准）；前景内容缩放比例——
// 源方格含底色与安全区同色，铺 66% 时信封主体落在 66/108 安全区内
const _adaptive = {
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};
const _fgScale = 0.66;

// iOS 图标文件名 → 像素边长（与 AppIcon.appiconset/Contents.json 一一对应）
const _ios = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

/// 入口：读源方格 → 产出 Android/iOS 全套资产 → 复制 logo 入 assets
void main() {
  final bytes = File(_sourcePath).readAsBytesSync();
  final source = img.decodePng(bytes);
  if (source == null) {
    stderr.writeln('无法解码 $_sourcePath');
    exitCode = 1;
    return;
  }

  // 源方格 = 图标源图（裁切对 440 全幅是恒等操作，保留以兼容未来更大源图）
  final tile = img.copyCrop(
    source,
    x: 0,
    y: 0,
    width: _tileSize,
    height: _tileSize,
  );

  // 1. Android 旧式 mipmap：源方格合成不透明米白底再缩放（无透明角落，防启动器垫黑底）
  final opaque = img.Image(width: _tileSize, height: _tileSize);
  img.fill(opaque, color: _bg);
  img.compositeImage(opaque, tile);
  for (final entry in _legacySizes.entries) {
    _write(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      img.copyResize(opaque, width: entry.value, height: entry.value),
    );
  }

  // 2. 自适应图标：背景层=满幅纯米白（不用 @color，部分启动器会渲染成黑色）；
  //    前景=透明画布 + 源方格 66% 居中（内容落 66/108 安全区）
  for (final entry in _adaptive.entries) {
    final bgCanvas = img.Image(width: entry.value, height: entry.value);
    img.fill(bgCanvas, color: _bg);
    _write(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_background.png',
      bgCanvas,
    );

    // 显式 4 通道 RGBA：Image() 默认 3 通道无 alpha，新建出来是黑图而非透明图
    final canvas = img.Image(
      width: entry.value,
      height: entry.value,
      numChannels: 4,
    );
    final side = (entry.value * _fgScale).round();
    final content = img.copyResize(tile, width: side, height: side);
    final offset = (entry.value - side) ~/ 2;
    img.compositeImage(canvas, content, dstX: offset, dstY: offset);
    _write(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png',
      canvas,
    );
  }

  // 3. iOS：复用 opaque（源方格圆角与底同色，合成后不可见，系统遮罩自行裁形；
  //    App Store 1024 图禁透明）
  for (final entry in _ios.entries) {
    _write(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
      img.copyResize(opaque, width: entry.value, height: entry.value),
    );
  }

  // 4. logo 方格图入 assets（关于页复用）；另产出不透明方格作 App 图标（票 07 关于页）
  Directory('assets').createSync(recursive: true);
  File(_sourcePath).copySync('assets/logo.png');
  _write('assets/logo_icon.png', opaque);

  stdout.writeln(
    '图标资产生成完毕：'
    '${_legacySizes.length} 档 mipmap + ${_adaptive.length} 档前景 + ${_ios.length} 个 iOS 图标 + assets/logo.png',
  );
}

// 写出 PNG 文件
void _write(String path, img.Image image) {
  final file = File(path);
  file.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
}
