// 备份与恢复页 — 推入页，无底导航（DESIGN.md §19）。
// .jx = JSON 全量导出（含全部账本，ADR-0011）；本地保留最近 5 份，
// 另可导出到用户自选位置（换机）与从外部文件恢复（清数据/换机回导）。
// 恢复确认必须把「会丢什么」算出来；恢复中不可取消；失败时保证当前数据未被改动。
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/app_repository.dart';
import '../../../data/backup_store.dart';
import '../../../state/auto_backup.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../copy.dart';

/// 备份与恢复页 — 完成恢复时 pop(true)，调用方据此刷新/重试。
class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  final _store = BackupStore();

  // 列表加载中
  bool _loading = true;

  // 本地备份列表（新→旧，最多 5 份）
  List<BackupFile> _files = const [];

  // 每份备份的摘要（路径 → 摘要；解析失败为 null）
  Map<String, BackupSummary?> _summaries = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // 重新列出本地备份并解析每份的摘要
  Future<void> _refresh() async {
    final files = await _store.list();
    final repo = ref.read(repoProvider);
    final summaries = <String, BackupSummary?>{};
    for (final f in files) {
      try {
        summaries[f.path] = await repo.readBackupSummary(
          await File(f.path).readAsString(),
        );
      } on Exception {
        summaries[f.path] = null; // 损坏/无法解析
      }
    }
    if (!mounted) return;
    setState(() {
      _files = files;
      _summaries = summaries;
      _loading = false;
    });
  }

  // ── 动作 ──

  // 统一提示入口（跨 async 前取好 messenger）
  void _toast(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(milliseconds: 2200),
        ),
      );
  }

  /// 立即备份：生成 .jx → 写本地（保留 5 份）→ 可选导出到用户选的位置（§19 步骤 1）。
  /// 本地写入成功即算备份完成；导出环节失败只提示导出部分，不误报「备份失败」。
  Future<void> _backupNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(repoProvider);
    _toast(messenger, toastExporting);

    // 第 1 步：本地备份（先落一份数据库之外的安全副本）
    final String json;
    try {
      json = await repo.exportBackupJson();
      await _store.write(json, DateTime.now());
      await _refresh();
      if (!mounted) return;
    } on Exception catch (e) {
      _toast(messenger, toastBackupFailed(e));
      return;
    }

    // 第 2 步：导出到用户选的位置（SAF / 桌面保存框）；取消 = 仅本地备份，也算完成
    final bytes = utf8.encode(json);
    final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    String? savedPath;
    try {
      savedPath = await FilePicker.platform.saveFile(
        fileName: '金打细算-$stamp.jx',
        bytes: bytes,
      );
    } on Exception {
      savedPath = null; // 部分机型保存框异常 → 降级为仅本地备份
    }
    if (!mounted) return;
    if (savedPath == null) {
      _toast(messenger, toastBackupLocalOnly);
      return;
    }
    // 关键步骤：移动端 saveFile(bytes:) 已由插件经 SAF 写完文件，返回的是文档
    // URI（content:// 或 /document/raw:… 形式），不能再用 dart:io 打开写——
    // 会抛 PathNotFoundException（曾因此误报「备份失败」但文件其实已写成功）。
    // 桌面端只返回目标路径，需要我们自己写文件。
    if (Platform.isAndroid || Platform.isIOS) {
      _toast(messenger, toastExportedToPicker);
    } else {
      try {
        await File(savedPath).writeAsBytes(bytes, flush: true);
        _toast(messenger, toastExportedToPath(savedPath));
      } on Exception catch (e) {
        _toast(messenger, toastBackupLocalExportFailed(e));
      }
    }
  }

  /// 从本地列表行恢复（§19 步骤 2-5）
  Future<void> _restoreFromFile(String path, String timeLabel) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(repoProvider);
    final navigator = Navigator.of(context);

    // 第 3 步：二次确认，必须说清会丢什么（库损坏时算不出今日笔数，按 0 处理不阻断恢复）
    var todayCount = 0;
    try {
      todayCount = await repo.countTxnsOnDay(DateTime.now());
    } on Exception {
      todayCount = 0;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('覆盖恢复'),
        content: Text(restoreCoverConfirmBody(timeLabel, todayCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: T.overspend),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 第 4 步：恢复中，不可取消（写一半的库没法回滚）
    _showRestoringDialog();
    String? failure;
    try {
      final raw = await File(path).readAsString();
      await repo.restoreFromJson(raw);
    } on BackupRestoreException catch (e) {
      failure = e.message;
    } on Exception {
      failure = restoreCorruptBody;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 关掉「恢复中」

    // 第 5/6 步：完成或失败（failure 局部提升为非空 String）
    final String? failureMsg = failure;
    if (failureMsg != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复失败'),
          content: Text(failureMsg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    _toast(messenger, toastRestored(timeLabel));
    navigator.pop(true); // 带结果回上一页（启动错误页据此重试）
  }

  /// 从外部文件挑一份 .jx 恢复（换机/清数据回导）
  Future<void> _pickAndRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jx'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _restoreFromFile(path, _timeLabel(File(path).lastModifiedSync()));
  }

  // 「恢复中」对话框——不可取消（§19：给取消等于给一个会毁数据的开关）
  void _showRestoringDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在恢复…'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 行首时间标签：今天 18:40 / 9月14日 09:30（顶层函数，自动备份卡共用）
  String _timeLabel(DateTime t) => formatBackupTimeLabel(t);

  // 大小文案：<1MB 显示 KB，否则 MB
  String _sizeLabel(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页头：返回 + 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(T.spaceLg, 8, T.spaceLg, 0),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _roundIconBtn(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '备份与恢复',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 说明行
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: Text(
                backupIntroBody,
                style: TextStyle(
                  fontSize: T.typeXs,
                  height: 1.7,
                  color: T.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 主行动：黄色实心「立即备份」（§19：整宽黄色实心）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: SizedBox(
                height: 52,
                child: Material(
                  color: T.primary,
                  borderRadius: BorderRadius.circular(T.radiusKey),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(T.radiusKey),
                    onTap: _loading ? null : _backupNow,
                    child: const Center(
                      child: Text(
                        '立即备份',
                        style: TextStyle(
                          fontSize: T.typeMd,
                          fontWeight: FontWeight.w700,
                          color: T.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 自动备份卡（v1.2.x 票 02 · §19）：开关 + 状态行
            const _AutoBackupCard(),
            const SizedBox(height: 20),
            // 分区标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: Row(
                children: [
                  const Text(
                    '最近的备份',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Text(
                    '最多保留 5 份',
                    style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 备份行列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: T.spaceLg,
                      ),
                      children: [
                        if (_files.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              backupEmptyBody,
                              style: TextStyle(
                                fontSize: T.typeBase,
                                color: T.textTertiary,
                              ),
                            ),
                          ),
                        for (final f in _files)
                          _BackupRow(
                            timeLabel: _timeLabel(f.modifiedAt),
                            subLabel: _subLabel(f),
                            onTap: () => _onRowTap(f),
                          ),
                        const SizedBox(height: 8),
                        // 从外部文件恢复（换机/清数据回导）
                        _BackupRow(
                          timeLabel: '从文件恢复',
                          subLabel: restoreFromFileSubLabel,
                          icon: Icons.file_open_outlined,
                          onTap: _pickAndRestore,
                        ),
                      ],
                    ),
            ),
            // 底部提示
            const Padding(
              padding: EdgeInsets.fromLTRB(T.spaceLg, 0, T.spaceLg, 16),
              child: Text(
                restoreCoverHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 行副文案：大小 · 账本数 · 信封数 · 流水数（解析失败的行给出说明）
  String _subLabel(BackupFile f) {
    final s = _summaries[f.path];
    if (s == null) return '${_sizeLabel(f.sizeBytes)} · 未能读取';
    return '${_sizeLabel(f.sizeBytes)} · ${s.ledgerCount} 个账本 · ${s.envelopeCount} 个信封 · ${s.txnCount} 笔流水';
  }

  // 行点击：正常备份走恢复；损坏的备份提示后不作操作
  Future<void> _onRowTap(BackupFile f) async {
    if (_summaries[f.path] == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('这份备份没能读出来'),
          content: const Text(restoreFileCorruptBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    await _restoreFromFile(f.path, _timeLabel(f.modifiedAt));
  }
}

// ── 小组件 ──────────────────────────────────

/// 行首/状态行时间标签：今天 18:40 / 9月14日 09:30（备份行与自动备份卡共用）
String formatBackupTimeLabel(DateTime t) {
  final now = DateTime.now();
  final hhmm = DateFormat('HH:mm').format(t);
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? '今天 $hhmm' : '${t.month}月${t.day}日 $hhmm';
}

/// 自动备份卡（v1.2.x 票 02 · ADR-0018 · §19）：开关行 + 两行状态小字。
/// 开关默认开、不进 .jx（恢复旧备份不翻转）；失败静默，状态行反映最近一次结果；
/// 位置固定、单文件覆盖——公共目录（下载/金打细算/）或沙盒降级两档文案。
class _AutoBackupCard extends ConsumerWidget {
  const _AutoBackupCard();

  // 状态行小字样式（11 Regular 暖灰）
  static const _statusStyle = TextStyle(
    fontSize: T.typeXs,
    color: T.textTertiary,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(autoBackupProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: T.spaceLg),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radiusCard),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 开关行：图标块 + 标题/副行 + Switch（整行可点）
          InkWell(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(T.radiusCard),
            ),
            onTap: () => ref
                .read(autoBackupProvider.notifier)
                .setEnabled(!status.enabled),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: T.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.autorenew_rounded,
                      size: 18,
                      color: Color(0xFF6E675C),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自动备份',
                          style: TextStyle(
                            fontSize: T.typeBase,
                            fontWeight: FontWeight.w500,
                            color: T.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          autoBackupSwitchSubtitle,
                          style: TextStyle(
                            fontSize: T.typeXs,
                            color: T.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: status.enabled,
                    onChanged: (v) =>
                        ref.read(autoBackupProvider.notifier).setEnabled(v),
                  ),
                ],
              ),
            ),
          ),
          // 状态行：最近一次结果 + 固定位置（单文件覆盖）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusLabel(status), style: _statusStyle),
                const SizedBox(height: 2),
                Text(
                  status.publicTarget
                      ? autoBackupLocationPublic
                      : autoBackupLocationSandbox,
                  style: _statusStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 最近一次结果：失败晚于成功显示失败，否则显示上次成功，从未写过显示引导
  String _statusLabel(AutoBackupState s) {
    if (s.lastAttemptFailed) {
      return autoBackupStatusFailure(formatBackupTimeLabel(s.lastFailureAt!));
    }
    final ok = s.lastSuccessAt;
    if (ok != null) return autoBackupStatusSuccess(formatBackupTimeLabel(ok));
    return autoBackupStatusNever;
  }
}

/// 备份行（高 56）：36dp 圆角图标块 + 两行文字 + 右箭头（§19）
class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.timeLabel,
    required this.subLabel,
    required this.onTap,
    this.icon = Icons.schedule_rounded,
  });

  final String timeLabel;
  final String subLabel;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            // 36dp 圆角图标块（#F7F2E8 底）
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: T.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF6E675C)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w500,
                      color: T.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: T.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16, color: T.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 36dp 圆形返回按钮（与其他推入页同款）
Widget _roundIconBtn({required IconData icon, required VoidCallback onTap}) {
  return SizedBox(
    width: 36,
    height: 36,
    child: Material(
      color: T.surfaceSubtle,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Icon(icon, size: 16, color: T.textPrimary),
      ),
    ),
  );
}
