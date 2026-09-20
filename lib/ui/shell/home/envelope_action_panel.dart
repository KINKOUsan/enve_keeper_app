// 信封操作面板（票 03 · ADR-0014 §4 · DESIGN.md §4 v1.1.0）。
// 长按信封弹出：主动作 = 从待规划快捷分配（信封名 + 待规划余额 + 金额输入，
// 待规划不足时确定键置灰——不变量②唯一执行点之一）；保留记支出 / 转移入口，
// 转移目标选择器可跨页选全部在用信封。视觉复用数字键盘（把手/圆角/键帽）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../domain/tx_engine.dart';
import '../../../state/providers.dart';
import '../../../theme/envelope_icons.dart';
import '../../../theme/tokens.dart';
import '../../common/format.dart';
import '../../copy.dart';
import '../../keypad/keypad_flow.dart';
import '../../keypad/keypad_models.dart';

/// 打开信封操作面板。[envelopeId] 为长按的信封。
/// 快捷分配在面板内完成提交；记支出 / 转移关闭面板后转交数字键盘。
Future<void> showEnvelopeActionPanel(
  BuildContext context,
  WidgetRef ref,
  String envelopeId,
) async {
  final act = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57000000), // 34% 黑遮罩，与键盘一致
    builder: (_) => _ActionPanel(envelopeId: envelopeId),
  );
  if (act == null || !context.mounted) return;
  switch (act) {
    case 'expense':
      // 记支出：转交标准键盘（透支合法照记，键盘里有软警告）
      await runKeypadFlow(
        context,
        ref,
        KeypadRequest(action: KeypadAction.expense, envelopeId: envelopeId),
      );
    case 'transfer':
      // 转移：先选目标（跨页选全部在用信封），再进键盘
      final target = await _pickTransferTarget(
        context,
        ref,
        excludeId: envelopeId,
      );
      if (target == null || !context.mounted) return;
      await runKeypadFlow(
        context,
        ref,
        KeypadRequest(
          action: KeypadAction.transfer,
          fromId: envelopeId,
          envelopeId: target,
        ),
      );
  }
}

/// 转移目标选择器：列出全部**在用**信封（跨页），排除来源自己
Future<String?> _pickTransferTarget(
  BuildContext context,
  WidgetRef ref, {
  required String excludeId,
}) {
  final envelopes = ref.read(envelopesProvider).value ?? const <Envelope>[];
  final targets = envelopes.where((e) => e.id != excludeId).toList();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57000000),
    builder: (_) => _TargetPicker(
      targets: targets,
      // 弹层无法 watch，读取当前符号快照即可（选择期间符号不会变化）
      symbol: ref.read(currencySymbolProvider),
    ),
  );
}

// ── 操作面板本体 ────────────────────────────────

class _ActionPanel extends ConsumerStatefulWidget {
  const _ActionPanel({required this.envelopeId});

  final String envelopeId;

  @override
  ConsumerState<_ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends ConsumerState<_ActionPanel> {
  // 金额输入：纯数字串（快捷分配不需要表达式），'' = 0
  String _amount = '';
  // 光标闪烁（与键盘同节奏）
  bool _cursorOn = true;

  @override
  void initState() {
    super.initState();
    _blink();
  }

  // 光标闪烁循环（mounted 置 false 即退出，无资源需释放）
  void _blink() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _cursorOn = !_cursorOn);
    }
  }

  // 解析当前输入的金额（round2 兜底浮点）
  double get _value => round2(double.tryParse(_amount) ?? 0);

  // ── 按键 ──

  void _onKey(String k) {
    setState(() {
      if (k == 'C') {
        _amount = '';
        return;
      }
      if (k == '⌫') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      // 小数点防重；总长限 9 位（金额上限足够）
      if (k == '.' && _amount.contains('.')) return;
      if (_amount.replaceAll('.', '').length >= 9) return;
      // 式首小数点自动补 0
      if (k == '.' && _amount.isEmpty) _amount = '0';
      _amount += k;
    });
  }

  // 快捷胶囊：当前金额上累加
  void _onQuickAdd(double quick) {
    setState(() => _amount = _fmt(_value + quick));
  }

  // ALL IN 胶囊：金额整体替换为待规划全额（替换而非累加，可重复按）
  void _onAllIn(double full) {
    setState(() => _amount = _fmt(round2(full)));
  }

  // 数值回写成输入串（整数不带小数、非整数保留 2 位）
  String _fmt(double v) {
    final isInt = v == v.roundToDouble();
    return isInt ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    // 每帧读最新账本状态：待规划余额与超额校验实时反映
    final state = ref.watch(ledgerStateProvider);
    // 当前账本货币符号（ADR-0017）：上下文文案、金额行前缀与校验文案共用
    final symbol = ref.watch(currencySymbolProvider);
    final e = state.envelopes[widget.envelopeId];
    final color = e == null ? null : envelopeColorById(e.color);
    // envelopeIconById 直接返回 IconData；未知信封不显示图标
    final icon = e == null ? null : envelopeIconById(e.icon);
    // 不变量②：待规划不足 → 确定键置灰（唯一执行点在入口 UI）
    final assignError = validateAssign(state, _value, symbol: symbol);
    final okEnabled = _value > 0 && assignError == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(T.radiusSheet),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x2E1A140A),
              offset: Offset(0, -8),
              blurRadius: 28,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            // 拖拽把手 36×4
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
            const SizedBox(height: 14),
            // 头行：图标块 + 信封名 + 待规划余额（ADR-0014：信封名 + 待规划余额）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color?.main ?? T.textTertiary,
                      borderRadius: BorderRadius.circular(T.radiusChip),
                    ),
                    child: Icon(icon, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e?.name ?? '未知信封',
                          style: const TextStyle(
                            fontSize: T.typeMd,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          keypadAssignSubtitle(state.toBudget, symbol: symbol),
                          style: const TextStyle(
                            fontSize: T.typeXs,
                            color: T.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 金额行：货币符号 + 数字 + 光标
            SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    symbol,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _amount.isEmpty ? '0' : _amount,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: _amount.isEmpty ? T.textTertiary : T.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: 2,
                    height: 28,
                    color: _cursorOn ? T.primary : Colors.transparent,
                  ),
                ],
              ),
            ),
            // 校验提示行（超额预告）
            SizedBox(
              height: assignError == null ? 0 : 16,
              child: Text(
                assignError ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: T.typeXs, color: T.overspend),
              ),
            ),
            const SizedBox(height: 6),
            // 快捷金额胶囊
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 34,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final quick in const [10.0, 50.0, 100.0])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _QuickChip(
                          label: '+${money(quick)}',
                          onTap: () => _onQuickAdd(quick),
                        ),
                      ),
                    // ALL IN：待规划全额，为 0 时置灰（待规划不允许为负——不变量②）
                    _QuickChip(
                      label: 'ALL IN',
                      onTap: state.toBudget > 0
                          ? () => _onAllIn(state.toBudget)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 紧凑键盘：1-9 / C 0 . + ⌫ / 确定（超额置灰）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Pad(
                onKey: _onKey,
                okEnabled: okEnabled,
                onOk: () => _submit(state),
              ),
            ),
            const SizedBox(height: 12),
            // 次入口行：记支出 / 转移（目标可跨页选）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _EntryButton(
                      icon: Icons.south_rounded,
                      label: '记一笔支出',
                      onTap: () => Navigator.pop(context, 'expense'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _EntryButton(
                      icon: Icons.swap_horiz_rounded,
                      label: '转移给另一个信封',
                      onTap: () => Navigator.pop(context, 'transfer'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 提交快捷分配：关面板 → 落库（messenger 在 await 前取好）
  Future<void> _submit(LedgerState state) async {
    if (!(_value > 0)) return;
    if (validateAssign(
          state,
          _value,
          symbol: ref.read(currencySymbolProvider),
        ) !=
        null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final ledger = ref.read(activeLedgerProvider);
    if (ledger == null) return;
    Navigator.of(context).pop('assigned');
    await submitAssign(
      messenger,
      ref,
      ledgerId: ledger.id,
      envelopeId: widget.envelopeId,
      amount: _value,
    );
  }
}

// 紧凑键盘：左 3 列（1-9 / C 0 .）+ 右列（⌫ / 确定跨 2 行）
class _Pad extends StatelessWidget {
  const _Pad({
    required this.onKey,
    required this.okEnabled,
    required this.onOk,
  });

  final void Function(String key) onKey;
  final bool okEnabled;
  final VoidCallback onOk;

  // 键帽高度与间距（与数字键盘一致的手感）
  static const double _keyH = 52;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4 * _keyH + 3 * _gap,
      child: Row(
        children: [
          // ── 左 3 列 ──
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _row(['1', '2', '3']),
                _vGap,
                _row(['4', '5', '6']),
                _vGap,
                _row(['7', '8', '9']),
                _vGap,
                _row(['C', '0', '.']),
              ],
            ),
          ),
          const SizedBox(width: _gap),
          // ── 右 1 列：⌫ / 确定跨 3 行 ──
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _KeyCap(
                    onTap: () => onKey('⌫'),
                    child: const Icon(
                      Icons.backspace_outlined,
                      size: 20,
                      color: T.textPrimary,
                    ),
                  ),
                ),
                _vGap,
                Expanded(flex: 3, child: _okKey()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 一行 3 键
  Widget _row(List<String> keys) {
    return Expanded(
      child: Row(
        children: [
          for (var c = 0; c < keys.length; c++) ...[
            if (c > 0) const SizedBox(width: _gap),
            Expanded(
              child: _KeyCap(
                onTap: () => onKey(keys[c]),
                child: Text(
                  keys[c],
                  style: TextStyle(
                    fontSize: keys[c] == 'C' ? 18 : 21,
                    fontWeight: keys[c] == 'C' || keys[c] == '.'
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: keys[c] == 'C' ? T.textSecondary : T.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget get _vGap => const SizedBox(height: _gap);

  // 确定键：全面板唯一的黄色实心按钮；超额/空值置灰（不变量②）
  Widget _okKey() {
    return Material(
      color: okEnabled ? T.primary : const Color(0xFFF3EFE7),
      borderRadius: BorderRadius.circular(T.radiusKey),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.radiusKey),
        onTap: okEnabled ? onOk : null,
        child: Center(
          child: Text(
            '确定',
            style: TextStyle(
              fontSize: T.typeMd,
              fontWeight: FontWeight.w700,
              color: okEnabled ? T.textPrimary : const Color(0xFFCCC4B8),
            ),
          ),
        ),
      ),
    );
  }
}

// 键帽：#F7F2E8 底、圆角 12
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: T.surfaceSubtle,
      borderRadius: BorderRadius.circular(T.radiusKey),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.radiusKey),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Center(child: child),
      ),
    );
  }
}

// 快捷金额胶囊（与键盘同款；onTap 为 null 时置灰禁用——ALL IN 的零额态）
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      // 置灰态：#F3EFE7 底 + #CCC4B8 字（与确定键禁用态一致）
      color: enabled ? T.surfaceSubtle : const Color(0xFFF3EFE7),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: T.typeBase,
              fontWeight: FontWeight.w500,
              color: enabled
                  ? const Color(0xFF6E675C)
                  : const Color(0xFFCCC4B8),
            ),
          ),
        ),
      ),
    );
  }
}

// 次入口按钮：浅底描边、图标 + 文案
class _EntryButton extends StatelessWidget {
  const _EntryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: T.surfaceSubtle,
        borderRadius: BorderRadius.circular(T.radiusKey),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.radiusKey),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF6E675C)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: T.typeSm,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6E675C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 转移目标选择器（跨页）──────────────────────

/// 底部弹出的目标列表：全部在用信封（图标 + 名 + 剩余），点选即返回 id
class _TargetPicker extends StatelessWidget {
  const _TargetPicker({required this.targets, required this.symbol});

  final List<Envelope> targets;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: T.surface,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  '转到哪个信封？',
                  style: TextStyle(
                    fontSize: T.typeMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // 目标列表：跨页全部在用信封
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final e in targets)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(context, e.id),
                        child: SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              const SizedBox(width: 6),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: envelopeColorById(e.color).main,
                                  borderRadius: BorderRadius.circular(
                                    T.radiusChip,
                                  ),
                                ),
                                child: Icon(
                                  envelopeIconById(e.icon),
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.name,
                                  style: const TextStyle(
                                    fontSize: T.typeBase,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '剩余 $symbol${money(e.available)}',
                                style: const TextStyle(
                                  fontSize: T.typeXs,
                                  color: T.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
