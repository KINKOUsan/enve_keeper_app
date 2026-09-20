// 账本管理页 — 列出全部账本：点击切换使用、重命名、删除（保护：至少一本）。
// ADR-0011：账本是数据空间——新账本一切为 0，账本之间互不影响。
// 创建后立即切换使用；新账本未完成引导，返回首页时会进入引导门。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart' as db;
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../keypad/keypad_flow.dart';

class LedgerManagePage extends ConsumerWidget {
  const LedgerManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgers = ref.watch(ledgersProvider).value ?? const <db.Ledger>[];
    final active = ref.watch(activeLedgerProvider);

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 页头：返回 + 标题 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _CircleButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '账本管理',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 提示行
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '点任意一本切换使用；每本账本的信封和流水互相独立。',
                style: TextStyle(fontSize: T.typeXs, color: Color(0xFFB4AC9F)),
              ),
            ),
            const SizedBox(height: 12),
            // ── 账本行组 ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: T.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F6B5738),
                          offset: Offset(0, 3),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < ledgers.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: T.border),
                          _LedgerRow(
                            ledger: ledgers[i],
                            isActive: ledgers[i].id == active?.id,
                            canDelete: ledgers.length > 1,
                            onTap: () => _switch(context, ref, ledgers[i]),
                            onRename: () => _rename(context, ref, ledgers[i]),
                            onDelete: () => _delete(context, ref, ledgers[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── 新建账本：暖黄描边按钮（DESIGN.md §13 的追加动作样式）──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 52,
                child: Material(
                  color: const Color(0xFFFFF3D1),
                  // StadiumBorder 自带全圆角，不能再同时给 borderRadius（Material 断言冲突）
                  shape: StadiumBorder(
                    side: BorderSide(color: const Color(0xFFFFE49B), width: 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(T.radiusKey),
                    onTap: () => _create(context, ref),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 18, color: T.primaryDeep),
                        SizedBox(width: 6),
                        Text(
                          '新建账本',
                          style: TextStyle(
                            fontSize: T.typeBase,
                            fontWeight: FontWeight.w600,
                            color: T.primaryDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 动作 ────────────────────────────────────

  /// 切换激活账本：先做结转检测再切换（ADR-0011：结转只对激活账本触发）
  Future<void> _switch(
    BuildContext context,
    WidgetRef ref,
    db.Ledger ledger,
  ) async {
    final active = ref.read(activeLedgerProvider);
    if (ledger.id == active?.id) return;
    final repo = ref.read(repoProvider);
    await repo.touchLedgerPeriod(ledger.id, DateTime.now());
    await ref.read(activeLedgerIdProvider.notifier).set(ledger.id);
    if (context.mounted) {
      appToast(context, '已切换到「${ledger.name}」');
    }
  }

  /// 新建账本：默认名「账本 N」，创建即切换使用（一切为 0）
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repoProvider);
    final ledger = await repo.createLedger();
    await repo.touchLedgerPeriod(ledger.id, DateTime.now());
    await ref.read(activeLedgerIdProvider.notifier).set(ledger.id);
    // 新账本会进引导门，退出本页避免盖住
    if (context.mounted) Navigator.of(context).pop();
  }

  /// 重命名对话框
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    db.Ledger ledger,
  ) async {
    final ctrl = TextEditingController(text: ledger.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名账本'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '账本名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == ledger.name) return;
    await ref.read(repoProvider).renameLedger(ledger.id, name);
  }

  /// 删除账本：至少保留一本；删激活账本后自动切到剩余第一本
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    db.Ledger ledger,
  ) async {
    final ledgers = ref.read(ledgersProvider).value ?? const <db.Ledger>[];
    final active = ref.read(activeLedgerProvider);
    final isActive = ledger.id == active?.id;

    // 删除保护（ADR-0011 规则 4）
    if (ledgers.length <= 1) {
      if (context.mounted) appToast(context, '至少要保留一本账本');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${ledger.name}」？'),
        content: Text(
          isActive
              ? '这是当前使用的账本。它里面的信封和流水会一起删掉，且不可恢复。'
              : '它里面的信封和流水会一起删掉，且不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: T.overspend),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(repoProvider);
    await repo.deleteLedger(ledger.id);
    // 删的是激活账本 → 切到剩余第一本（createLedger 的命名也依赖剩余数量）
    if (isActive) {
      final remaining = ref.read(ledgersProvider).value ?? const <db.Ledger>[];
      if (remaining.isNotEmpty) {
        await repo.touchLedgerPeriod(remaining.first.id, DateTime.now());
        await ref.read(activeLedgerIdProvider.notifier).set(remaining.first.id);
      }
    }
    if (context.mounted) appToast(context, '已删除「${ledger.name}」');
  }
}

// ── 小组件 ─────────────────────────────────────

// 36dp 圆形按钮（页头返回）
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}

// 一行账本：图标块 + 名 + 当前标记 + 菜单
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.ledger,
    required this.isActive,
    required this.canDelete,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final db.Ledger ledger;
  final bool isActive;

  // 是否允许删除（至少保留一本）
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            // 32dp 图标块：激活用暖黄底，非激活浅底
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive ? T.primary : T.surfaceSubtle,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.auto_awesome_motion_outlined,
                size: 16,
                color: isActive ? T.textPrimary : const Color(0xFF6E675C),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ledger.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w500,
                      color: T.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '创建于 ${ledger.createdAt.month}月${ledger.createdAt.day}日',
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: Color(0xFFB4AC9F),
                    ),
                  ),
                ],
              ),
            ),
            // 当前使用标记：黄胶囊
            if (isActive)
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Text(
                  '使用中',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: T.primaryDeep,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            // 菜单按钮
            SizedBox(
              width: 32,
              height: 32,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showMenu(context),
                child: const Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: T.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 行尾菜单：重命名 / 删除
  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x57000000),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: T.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _menuItem(
                  ctx,
                  Icons.drive_file_rename_outline,
                  '重命名',
                  onRename,
                ),
                _menuItem(
                  ctx,
                  Icons.delete_outline,
                  canDelete ? '删除' : '删除（至少保留一本）',
                  canDelete ? onDelete : () {},
                  danger: !canDelete,
                ),
                _menuItem(
                  ctx,
                  Icons.close_rounded,
                  '取消',
                  () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 菜单项行
  Widget _menuItem(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF6E675C)),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: T.typeBase,
                fontWeight: FontWeight.w500,
                color: danger ? T.textTertiary : T.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
