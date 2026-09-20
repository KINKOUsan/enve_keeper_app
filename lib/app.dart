// App 根组件 — 主题 + 首页路由。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'state/auto_backup.dart';
import 'theme/tokens.dart';
import 'theme/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 关键步骤：建默认账本（首次）→ 对激活账本做结转检测 → 恢复激活 id
  Future<void> _bootstrap() async {
    if (mounted) setState(() => _error = null);
    try {
      final repo = ref.read(repoProvider);
      final ledger = await repo.ensureBootstrap();
      final active = ref.read(activeLedgerIdProvider);
      final targetId = (active != null && await repo.getLedger(active) != null)
          ? active
          : ledger.id;
      await repo.touchLedgerPeriod(targetId, DateTime.now());
      if (ref.read(activeLedgerIdProvider) != targetId) {
        await ref.read(activeLedgerIdProvider.notifier).set(targetId);
      }
      if (mounted) setState(() {});
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e);
    }
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
    if (ledger == null) {
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
