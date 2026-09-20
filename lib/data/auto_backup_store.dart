// 自动备份写入（v1.2.x 票 02 · ADR-0018 · DESIGN.md §19）：
// 数据变动静默 3 秒后把全量 .jx 写到固定文件，单文件覆盖，不产生第二份。
// Android（API 29+）经 MethodChannel 走 MediaStore 写公共
// 下载/金打细算/金打细算-自动备份.jx——卸载重装仍在（属主丢失的读取兜底见票 03）；
// iOS / 桌面 / Android 低版本降级为应用文档目录单文件（文案不承诺卸载可恢复）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// 自动备份固定文件名（公共目录与私有目录同一名，覆盖写）
const kAutoBackupFileName = '金打细算-自动备份.jx';

// 自动备份子目录名（公共目录：下载/金打细算/；私有目录同用）
const kAutoBackupDirName = '金打细算';

/// 自动备份文件的最近写入信息（状态行还原用）
class AutoBackupFileStat {
  const AutoBackupFileStat({required this.modifiedAt, required this.publicTarget});

  // 文件最近一次被写入的时刻
  final DateTime modifiedAt;

  // 文件是否在公共目录（false = 沙盒降级档）
  final bool publicTarget;
}

/// 一次自动备份写入的结果（状态行显示用）
class AutoBackupWriteResult {
  const AutoBackupWriteResult({required this.publicTarget});

  // 是否落在公共目录（false = 应用沙盒，文案不承诺卸载可恢复）
  final bool publicTarget;
}

/// 自动备份写入器：平台分流（MediaStore / 本地文件），失败向上抛、由控制器静默。
class AutoBackupStore {
  // 文档目录解析器（测试注入临时目录用，生产 = path_provider）
  AutoBackupStore({Future<Directory> Function()? docsDirectory})
    : _docsDirectory = docsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _docsDirectory;

  static const _channel = MethodChannel('enve_keeper_app/autobackup');

  /// 写一份自动备份，返回写入位置类别
  Future<AutoBackupWriteResult> write(String json) async {
    if (Platform.isAndroid) {
      // API 29+ 走 MediaStore（Kotlin 侧）；低版本/失败/无引擎返回 null → 降级私有目录
      try {
        final public = await _channel.invokeMethod<bool>('writeAutoBackup', {
          'subdir': kAutoBackupDirName,
          'fileName': kAutoBackupFileName,
          'bytes': utf8.encode(json),
        });
        if (public == true) {
          return const AutoBackupWriteResult(publicTarget: true);
        }
      } on PlatformException {
        // 通道异常（机型差异等）：静默降级私有目录，不丢备份本身
      } on MissingPluginException {
        // 引擎不可用（如测试环境）：同样降级
      }
    }
    final docs = await _docsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}$kAutoBackupDirName',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}$kAutoBackupFileName',
    );
    await file.writeAsString(json, flush: true);
    return const AutoBackupWriteResult(publicTarget: false);
  }

  /// 读自动备份内容（v1.2.x 票 03 重装找回）：公共目录（Android API 29+ 经
  /// MediaStore）或降级档沙盒单文件。找不到、通道异常、属主丢失被系统拒读
  /// 都返回 null——调用方与「无文件」同路径当无事发生，备份页「从文件恢复」
  /// 永远兜底。
  Future<String?> read() async {
    if (Platform.isAndroid) {
      // MediaStore 读不到（未命中属主校验等）返回 null → 继续试私有目录，
      // 与 write 的降级链对称
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('readAutoBackup', {
          'subdir': kAutoBackupDirName,
          'fileName': kAutoBackupFileName,
        });
        if (bytes != null) return utf8.decode(bytes);
      } on Exception {
        // 通道异常 / 引擎不可用（测试环境）：降级读私有目录
      }
    }
    try {
      final docs = await _docsDirectory();
      final file = File(
        '${docs.path}${Platform.pathSeparator}$kAutoBackupDirName'
        '${Platform.pathSeparator}$kAutoBackupFileName',
      );
      if (file.existsSync()) return await file.readAsString();
    } on Exception {
      // 读不了（无文件/无权限）= 无事发生
    }
    return null;
  }

  /// 查自动备份文件的最近写入时刻与位置类别（找不到/读不了返回 null）。
  /// 控制器启动时用它把「上次自动备份」状态行从文件还原——状态只在内存里，
  /// 文件还在却显示「尚未生成」会让用户以为备份丢了（票 02 修复）。
  Future<AutoBackupFileStat?> stat() async {
    if (Platform.isAndroid) {
      // MediaStore 未命中 → 继续试私有目录降级档，与 read 对称
      try {
        final ms = await _channel.invokeMethod<int>('statAutoBackup', {
          'subdir': kAutoBackupDirName,
          'fileName': kAutoBackupFileName,
        });
        if (ms != null) {
          return AutoBackupFileStat(
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(ms),
            publicTarget: true,
          );
        }
      } on Exception {
        // 通道异常 / 引擎不可用（测试环境）：降级读私有目录
      }
    }
    try {
      final docs = await _docsDirectory();
      final file = File(
        '${docs.path}${Platform.pathSeparator}$kAutoBackupDirName'
        '${Platform.pathSeparator}$kAutoBackupFileName',
      );
      if (file.existsSync()) {
        return AutoBackupFileStat(
          modifiedAt: file.lastModifiedSync(),
          publicTarget: false,
        );
      }
    } on Exception {
      // 读不了 = 当没有
    }
    return null;
  }
}
