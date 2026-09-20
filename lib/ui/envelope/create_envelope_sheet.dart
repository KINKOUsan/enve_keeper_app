// 新建信封弹层 — 名称 + 图标 + 颜色 + 结转开关的最小表单。
// 设计稿没有独立的表单章节，视觉语言沿用 §13 信封管理行 / §5 键盘弹层（28 圆角、把手、黄主按钮）。
// 步骤 7 的信封管理会复用这里的选择件。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../theme/envelope_icons.dart';
import '../../theme/tokens.dart';
import '../copy.dart';
import '../keypad/keypad_flow.dart';
import 'pickers.dart';

/// 打开「新建信封」弹层。成功创建返回 true。
Future<bool> showCreateEnvelopeSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57000000),
    builder: (_) => const _CreateEnvelopeSheet(),
  );
  return result ?? false;
}

// 新建信封的表单状态：名称 / 图标 / 颜色 / 结转
class _CreateEnvelopeSheet extends ConsumerStatefulWidget {
  const _CreateEnvelopeSheet();

  @override
  ConsumerState<_CreateEnvelopeSheet> createState() =>
      _CreateEnvelopeSheetState();
}

class _CreateEnvelopeSheetState extends ConsumerState<_CreateEnvelopeSheet> {
  final _nameCtrl = TextEditingController();

  // 选择状态：默认第一个图标 / 第一个色（陶土红）；结转默认取账本全局设置
  String _icon = kEnvelopeIcons.first.id;
  String _color = kEnvelopeColors.first.id;
  bool? _carryover;

  // 在用同名冲突（提交时发现）
  bool _conflict = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // 提交：创建 or 恢复同名停用信封（ADR-0012）
  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final ledger = ref.read(activeLedgerProvider);
    if (ledger == null) return;
    final carry =
        _carryover ??
        ref.read(settingsProvider).value?.carryoverDefault ??
        true;
    final result = await ref
        .read(repoProvider)
        .createOrRestoreEnvelope(
          ledgerId: ledger.id,
          name: name,
          icon: _icon,
          color: _color,
          carryover: carry,
        );
    if (!mounted) return;
    if (result.conflict) {
      // 在用同名：阻止并提示
      setState(() => _conflict = true);
      return;
    }
    Navigator.pop(context, true);
    appToast(
      context,
      result.restored ? '已恢复「$name」——新账，旧流水留档' : '已创建信封「$name」',
    );
  }

  @override
  Widget build(BuildContext context) {
    final carryoverDefault =
        ref.watch(settingsProvider).value?.carryoverDefault ?? true;
    final carryover = _carryover ?? carryoverDefault;
    final name = _nameCtrl.text.trim();
    final canSubmit = name.isNotEmpty && !_conflict;

    // 同名检测（ADR-0012）：输入名命中停用信封 → 恢复提示；命中在用 → 冲突提示
    final all = ref.watch(allEnvelopesProvider).value ?? const <Envelope>[];
    final archivedSame =
        all.where((e) => e.isArchived && e.name == name).toList()
          ..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));

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
            // 把手
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: Text(
                '新建信封',
                style: TextStyle(
                  fontSize: T.typeMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 名称输入
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
              child: TextField(
                controller: _nameCtrl,
                autofocus: true,
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
            // ── 同名检测提示（ADR-0012）──
            if (_conflict)
              Padding(
                padding: const EdgeInsets.fromLTRB(T.spaceLg, 10, T.spaceLg, 0),
                child: Text(
                  '已经有在用的「$name」了。信封名字不能重复，换个名字或先停用它。',
                  style: const TextStyle(
                    fontSize: T.typeXs,
                    color: T.overspend,
                  ),
                ),
              )
            else if (archivedSame.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(T.spaceLg, 10, T.spaceLg, 0),
                child: Text(
                  '「$name」曾停用过（共 ${archivedSame.length} 次）。'
                  '创建同名信封将恢复最近停用的那个：这是一本新账，'
                  '它以前的所有流水会作为旧档留在它名下。',
                  style: const TextStyle(
                    fontSize: T.typeXs,
                    height: 1.5,
                    color: Color(0xFFB08A00),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // 图标墙：12 个，6 列
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
            // 色板：8 个圆点
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
            // 结转开关行（DESIGN.md §13 的结转语义）
            SwitchListTile(
              value: carryover,
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
            // 确认：黄色实心（同键盘确定键的置灰规则）
            Padding(
              padding: const EdgeInsets.fromLTRB(T.spaceLg, 0, T.spaceLg, 20),
              child: SizedBox(
                height: 52,
                child: Material(
                  color: canSubmit ? T.primary : const Color(0xFFF3EFE7),
                  borderRadius: BorderRadius.circular(T.radiusKey),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(T.radiusKey),
                    onTap: canSubmit ? _submit : null,
                    child: Center(
                      child: Text(
                        '创建信封',
                        style: TextStyle(
                          fontSize: T.typeMd,
                          fontWeight: FontWeight.w700,
                          color: canSubmit
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
