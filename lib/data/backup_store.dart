// 备份文件存储 — 应用文档目录下的 backups/ 子目录，文件名自带时间戳。
// 最多保留 5 份（DESIGN.md §19），超出按最旧删除；与数据库无关，
// 数据库损坏时本目录仍可读，因此启动错误页的「从备份恢复」依赖这里。
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 一份本地备份文件的描述（列表行显示用）
class BackupFile {
  const BackupFile({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final DateTime modifiedAt;
  final int sizeBytes;
}

/// 本地备份目录管理：写入 / 列出 / 轮换（最多保留 [kMaxBackups] 份）
class BackupStore {
  BackupStore();

  // 最多保留的份数（§19：最多保留 5 份）
  static const int kMaxBackups = 5;

  // 备份目录：<文档目录>/backups/
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 列出本地备份（新→旧），最多 [kMaxBackups] 份，超出部分删除
  Future<List<BackupFile>> list() async {
    final dir = await _dir();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jx'))
            .toList()
          ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    // 轮换：只保留最近 5 份
    for (final old in files.skip(kMaxBackups)) {
      try {
        old.deleteSync();
      } on FileSystemException {
        // 删不掉（被占用等）就先留着，不影响列表
      }
    }
    return files.take(kMaxBackups).map(_fromFile).toList();
  }

  /// 写入一份备份（时间戳命名），返回文件实体
  Future<File> write(String json, DateTime now) async {
    final dir = await _dir();
    final ts =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final file = File('${dir.path}${Platform.pathSeparator}金打细算-$ts.jx');
    return file.writeAsString(json, flush: true);
  }

  // File → BackupFile 描述
  BackupFile _fromFile(File f) => BackupFile(
    path: f.path,
    name: f.uri.pathSegments.last,
    modifiedAt: f.lastModifiedSync(),
    sizeBytes: f.lengthSync(),
  );
}
