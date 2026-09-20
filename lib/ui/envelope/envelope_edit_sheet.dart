// 信封编辑弹层 — 改名 / 图标 / 颜色 / 结转开关 / 停用（DESIGN.md §13 + ADR-0012）。
// 停用前在确认框里说清三件事：钱回待规划、流水保留不撤销、恢复走新建同名。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../theme/envelope_icons.dart';
import '../../theme/tokens.dart';
import '../common/format.dart';
import '../copy.dart';
import 'pickers.dart';

/// 打开「编辑信封」弹层。返回 true 表示信封被停用（调用方负责提示与导航）。
Future<bool> showEditEnvelopeSheet(
  BuildContext context,
  WidgetRef ref,
  Envelope envelope,
) async {
  final deleted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57000000),
    builder: (_) => _EditEnvelopeSheet(envelope: envelope),
  );
  return deleted ?? false;
}

class _EditEnvelopeSheet extends ConsumerStatefulWidget {
  const _EditEnvelopeSheet({required this.envelope});

  final Envelope envelope;

  @override
  ConsumerState<_EditEnvelopeSheet> createState() => _EditEnvelopeSheetState();
}

class _EditEnvelopeSheetState extends ConsumerState<_EditEnvelopeSheet> {
  late final TextEditingController _nameCtrl;

  // 选择状态（从当前信封初始化）
  late String _icon = widget.envelope.icon;
  late String _color = widget.envelope.color;
  late bool _carryover = widget.envelope.carryover;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.envelope.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // 保存：名字非空才可保存
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref
        .read(repoProvider)
        .updateEnvelope(
          widget.envelope.id,
          name: name,
          icon: _icon,
          color: _color,
          carryover: _carryover,
        );
    if (!mounted) return;
    // 提示要在 pop 前拿好 messenger（pop 后 context 失效）
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已保存「$name」')));
  }

  // 停用（ADR-0012：信封没有删除）：确认框说明三件事——钱回待规划、流水保留不撤销、
  // 恢复走新建同名。透支信封不允许停用（必须先补缺口，避免核销导致账面虚增）。
  Future<void> _archive() async {
    final e = widget.envelope;
    // 当前账本货币符号（ADR-0017）：确认框文案用
    final symbol = ref.read(currencySymbolProvider);

    // 透支拦截：缺口必须先腾挪补上，停用才不改变账本总额
    if (e.available < 0) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('「${e.name}」还透支着'),
          content: Text(
            '它还缺 $symbol${money(-e.available)}。停用前需要先把缺口补上：'
            '到流水页顶部的提示条点「去补上」，从其他信封腾挪过来。',
          ),
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

    final refund = e.available > 0 ? e.available : 0.0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('停用「${e.name}」？'),
        content: Text(
          '${refund > 0 ? '未花完的 $symbol${money(refund)} 会回到待规划；' : ''}'
          '它的流水会全部保留，停用不会撤销任何一笔。'
          '以后新建同名信封即可恢复它（新账，旧流水留档）。'
          '如果目的是撤销它的流水，请到信封详情页里多选撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: T.overspend),
            child: const Text('停用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ledger = ref.read(activeLedgerProvider);
    if (ledger == null) return;
    try {
      await ref.read(repoProvider).archiveEnvelope(e.id, ledgerId: ledger.id);
    } catch (err) {
      // 防御：任何落库异常都直接可见，不静默吞掉
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('停用失败'),
          content: Text('$err'),
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
    if (!mounted) return;
    // 只负责返回结果；成功提示与返回首页由调用方（信封详情页）处理
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameCtrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(T.radiusSheet),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3DCD0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: Row(
                children: [
                  const Text(
                    '编辑信封',
                    style: TextStyle(
                      fontSize: T.typeMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // 停用入口（红字，无底色；信封没有删除，ADR-0012）
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _archive,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        '停用',
                        style: TextStyle(
                          fontSize: T.typeBase,
                          fontWeight: FontWeight.w500,
                          color: T.overspend,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 名称输入
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: TextField(
                controller: _nameCtrl,
                maxLength: 8,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: T.typeMd,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '信封叫什么（最多 8 个字）',
                  hintStyle: const TextStyle(
                    fontSize: T.typeBase,
                    color: T.textTertiary,
                  ),
                  filled: true,
                  fillColor: T.surfaceSubtle,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(T.radiusKey),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 图标墙
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final def in kEnvelopeIcons)
                    IconCell(
                      def: def,
                      colorId: _color,
                      selected: _icon == def.id,
                      onTap: () => setState(() => _icon = def.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 色板
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: Row(
                children: [
                  for (final c in kEnvelopeColors)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ColorDot(
                        color: c,
                        selected: _color == c.id,
                        onTap: () => setState(() => _color = c.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _carryover,
              onChanged: (v) => setState(() => _carryover = v),
              title: const Text(
                '结余带入下个月',
                style: TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                carryoverSwitchSubtitle,
                style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
              ),
              activeThumbColor: Colors.white,
              activeTrackColor: T.primary,
            ),
            const SizedBox(height: 14),
            // 保存按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(T.spaceLg, 0, T.spaceLg, 20),
              child: SizedBox(
                height: 52,
                child: Material(
                  color: canSave ? T.primary : const Color(0xFFF3EFE7),
                  borderRadius: BorderRadius.circular(T.radiusKey),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(T.radiusKey),
                    onTap: canSave ? _save : null,
                    child: Center(
                      child: Text(
                        '保存',
                        style: TextStyle(
                          fontSize: T.typeMd,
                          fontWeight: FontWeight.w700,
                          color: canSave
                              ? T.textPrimary
                              : const Color(0xFFCCC4B8),
                        ),
                      ),
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
}
