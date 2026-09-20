// App 根组件 — 主题 + 首页路由。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/app_repository.dart';
import 'data/db/database.dart' as db;
import 'state/auto_backup.dart';
import 'state/providers.dart';
import 'theme/tokens.dart';
import 'theme/theme.dart';
import 'ui/copy.dart';
import 'ui/common/app_route.dart';
import 'ui/onboarding/onboarding_gate.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/profile/backup_restore_page.dart';

class JinDaXiSuanApp extends ConsumerWidget {
  const JinDaXiSuanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '金打细算',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 中文界面：统计自选区间与流水筛选的日历选择器需要中文本地化
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Boot(),
    );
  }
}

/// 启动装配：确保有默认账本 → 触发结转检测 → 引导 / 主壳分流
class _Boot extends ConsumerStatefulWidget {
  const _Boot();

  @override
  ConsumerState<_Boot> createState() => _BootState();
}

class _BootState extends ConsumerState<_Boot> {
  Exception? _error;

  // 启动装配是否完成（含重装找回的检测与恢复）：完成前保持空白，
  // 不让引导首屏在检测期间闪出来
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 关键步骤：建默认账本（首次）→ 对激活账本做结转检测 → 恢复激活 id
  /// → （首次启动 + 空账未引导）重装找回自动备份（票 03）
  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _error = null;
        _ready = false;
      });
    }
    try {
      final repo = ref.read(repoProvider);
      // 是否本安装的首次启动（重装/清数据后偏好为空）——必须在激活写偏好
      // 之前判定；检测只发生在首启，之后不再重复弹（票 03）
      final firstLaunch =
          ref.read(prefsProvider).getString(kActiveLedgerIdKey) == null;
      var target = await _activateLedger();
      if (firstLaunch) {
        final fresh = await repo.getLedger(target);
        if (fresh != null &&
            !fresh.onboarded &&
            await repo.isLedgerEmpty(target)) {
          if (await _maybeRestoreAutoBackup()) {
            // 恢复整体替换了全部账本：重新兜底定位激活账本
            //（正常情况下即恢复出的第一个账本，onboarded 随数据而来）
            target = await _activateLedger();
          }
        }
      }
      // 等账本流追上库内真相再揭幕：恢复把全部账本换掉后立即揭幕，
      // 会闪一帧已被删除的旧引导账本的引导页（票 03）
      await _waitLedgerVisible(target);
      if (mounted) setState(() => _ready = true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// 建默认账本（首次）→ 对激活账本做结转检测 → 激活 id 落偏好，返回最终激活的账本 id
  Future<String> _activateLedger() async {
    final repo = ref.read(repoProvider);
    final ledger = await repo.ensureBootstrap();
    final active = ref.read(activeLedgerIdProvider);
    final target = (active != null && await repo.getLedger(active) != null)
        ? active
        : ledger.id;
    await repo.touchLedgerPeriod(target, DateTime.now());
    if (ref.read(activeLedgerIdProvider) != target) {
      await ref.read(activeLedgerIdProvider.notifier).set(target);
    }
    return target;
  }

  /// 等 [ledgersProvider] 吐出 [ledgerId] 再返回——这是首页/引导读账本的同一
  /// 数据源。等它而不是裸订阅 drift watch 流：后者的首帧在部分环境
  /// （widget 测试的 FakeAsync 区）不送达；5 秒兜底超时防止空白卡死。
  Future<void> _waitLedgerVisible(String ledgerId) async {
    bool has(List<db.Ledger> ls) => ls.any((l) => l.id == ledgerId);
    final current = ref.read(ledgersProvider).value;
    if (current != null && has(current)) return;
    final done = Completer<void>();
    final sub = ref.listenManual<AsyncValue<List<db.Ledger>>>(
      ledgersProvider,
      (_, next) {
        final v = next.value;
        if (v != null && has(v) && !done.isCompleted) done.complete();
      },
    );
    try {
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    } finally {
      sub.close();
    }
  }

  /// 重装找回（票 03 · DESIGN.md §19）：读自动备份文件，找到且能读出摘要时弹
  /// 「发现自动备份」确认框；确认则按既有覆盖恢复语义整体恢复（恢复中不可取消，
  /// 失败保证当前数据未被改动）。找不到 / 拒绝 / 任何失败都返回 false——
  /// 当无事发生，正常走首次引导；备份页「从文件恢复」永远兜底。
  Future<bool> _maybeRestoreAutoBackup() async {
    final repo = ref.read(repoProvider);
    final raw = await ref.read(autoBackupStoreProvider).read();
    if (raw == null || !mounted) return false;
    // 文件在但内容读不出（损坏）：与「找不到」同路径，静默走引导
    final BackupSummary summary;
    try {
      summary = await repo.readBackupSummary(raw);
    } on Exception {
      return false;
    }
    if (!mounted) return false;
    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(autoBackupFoundTitle),
        content: Text(
          autoBackupFoundBody(
            formatBackupTimeLabel(summary.exportedAt),
            summary.ledgerCount,
            summary.envelopeCount,
            summary.txnCount,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: T.primary,
              foregroundColor: T.textPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复备份'),
          ),
        ],
      ),
    );
    if (restore != true || !mounted) return false;
    // 恢复：沿用既有覆盖恢复语义（恢复中不可取消；失败保护当前数据）
    final failure = await runCoverRestore(context, repo, raw);
    if (!mounted) return false;
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
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 自动备份常驻：从启动即 watch，让控制器与生命周期监听全应用存活
    // （v1.2.x 票 02 · ADR-0018）
    ref.watch(autoBackupProvider);
    final ledger = ref.watch(activeLedgerProvider);
    if (_error != null) {
      // 数据异常全屏错误（DESIGN.md §18）
      return _BootError(onRetry: _bootstrap);
    }
    if (!_ready || ledger == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    // 每账本独立判断是否走引导（ADR-0011：新账本从零开始）
    return ledger.onboarded
        ? const AppShell()
        : OnboardingGate(ledgerId: ledger.id);
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: T.overspend, size: 48),
            const SizedBox(height: 16),
            const Text(
              '数据没能读出来',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '记账数据都存在本机，这次没能打开。可以先重试；'
                '如果还是不行，用最近一次备份恢复。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: T.textSecondary,
                  height: 1.7,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: T.primary,
                foregroundColor: T.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 14,
                ),
              ),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
            const SizedBox(height: 12),
            // 白底描边「从备份恢复」（§18：错误页两个按钮）——恢复成功后自动重试引导
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: T.textPrimary,
                side: const BorderSide(color: T.border),
                backgroundColor: T.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(T.radiusKey),
                ),
              ),
              onPressed: () async {
                final restored = await Navigator.of(context).push<bool>(
                  AppPageRoute<bool>(
                    builder: (_) => const BackupRestorePage(),
                  ),
                );
                if (restored == true) onRetry();
              },
              child: const Text('从备份恢复'),
            ),
          ],
        ),
      ),
    );
  }
}
