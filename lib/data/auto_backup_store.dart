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

/// 一次自动备份写入的结果（状态行显示用）
class AutoBackupWriteResult {
  const AutoBackupWriteResult({required this.publicTarget});

  // 是否落在公共目录（false = 应用沙盒，文案不承诺卸载可恢复）
  final bool publicTarget;
}

/// 自动备份写入器：平台分流（MediaStore / 本地文件），失败向上抛、由控制器静默。
class AutoBackupStore {
  AutoBackupStore();

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
    final docs = await getApplicationDocumentsDirectory();
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
}
