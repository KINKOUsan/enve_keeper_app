// 数字键盘弹层 — 上两角圆角 28、高度由内容自适应、支持 +−×÷ 与括号、
// 「=/确定」两态（含运算符先按 = 求值，求出结果回到确定态再落账）。四则运算见 DESIGN.md §5。
// 这是全 App 的地基：分配 / 撤销 / 转移 / 支出 / 收入 / 改金额共用，只换上下文文案（IMPLEMENTATION §4）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/tx_engine.dart';
import '../../domain/tx_math.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../common/format.dart';
import '../copy.dart';
import '../txn/time_edit_sheet.dart';
import 'keypad_models.dart';

/// 打开数字键盘。提交时回调 [onConfirm]（金额已通过校验，[at] 为时间行草稿）。
/// 返回是否成功提交。
Future<bool> showKeypadSheet(
  BuildContext context,
  KeypadRequest request, {
  required Future<void> Function(double amount, String note, DateTime at)
  onConfirm,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57000000), // 34% 黑遮罩
    builder: (_) => _KeypadSheet(request: request, onConfirm: onConfirm),
  );
  return result ?? false;
}

class _KeypadSheet extends ConsumerStatefulWidget {
  const _KeypadSheet({required this.request, required this.onConfirm});

  final KeypadRequest request;
  final Future<void> Function(double amount, String note, DateTime at)
  onConfirm;

  @override
  ConsumerState<_KeypadSheet> createState() => _KeypadSheetState();
}

class _KeypadSheetState extends ConsumerState<_KeypadSheet> {
  String _expr = '';
  bool _cursorOn = true;
  Timer? _blink;
  final _noteCtrl = TextEditingController();

  // 描述栏焦点：聚焦（输入法弹起）时在描述栏上方浮出历史候选胶囊（票 03）
  final _noteFocus = FocusNode();

  // 本次键盘会话的时间草稿（票 01 / ADR-0019）：默认当前时间，滚轮可改到
  // 任意过去时刻（上限今天）；确认才随交易落库，关键盘即丢弃重置。
  DateTime _at = DateTime.now();

  // 是否刚按过「=」（此刻 _expr 是求值结果；此时按数字应重新开始）
  bool _evaluated = false;

  // 手动提示（如「=」求值失败），优先于校验警告显示；任意按键清除
  String? _hint;

  @override
  void initState() {
    super.initState();
    _expr = widget.request.initialExpr ?? '';
    // 焦点变化驱动候选胶囊显隐
    _noteFocus.addListener(() {
      if (mounted) setState(() {});
    });
    // 光标闪烁（与原型同节奏）
    _blink = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _cursorOn = !_cursorOn);
    });
  }

  // 是否处于「=」态：表达式里有运算符或括号 = 还没算完
  bool get _isExprMode =>
      _expr.isNotEmpty && RegExp(r'[+\-−×÷()]').hasMatch(_expr);

  @override
  void dispose() {
    _blink?.cancel();
    _noteFocus.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── 上下文文案（对齐原型 paintSheet）─────────────

  Envelope? _env(LedgerState s, String? id) =>
      id == null ? null : s.envelopes[id];

  String _title(LedgerState s) {
    final r = widget.request;
    if (r.titleOverride != null) return r.titleOverride!;
    switch (r.action) {
      case KeypadAction.assign:
        return keypadAssignTitle(
          _env(s, r.envelopeId)?.name ?? unknownEnvelope,
        );
      case KeypadAction.unassign:
        return keypadUnassignTitle(
          _env(s, r.envelopeId)?.name ?? unknownEnvelope,
        );
      case KeypadAction.transfer:
        return keypadTransferTitle(
          _env(s, r.fromId)?.name ?? unknownEnvelope,
          _env(s, r.envelopeId)?.name ?? unknownEnvelope,
        );
      case KeypadAction.expense:
        return keypadExpenseTitle;
      case KeypadAction.income:
        return keypadIncomeTitle;
      case KeypadAction.editAmount:
        return keypadEditAmountTitle;
    }
  }

  String _subtitle(LedgerState s, String symbol) {
    final r = widget.request;
    if (r.subtitleOverride != null) return r.subtitleOverride!;
    switch (r.action) {
      case KeypadAction.assign:
        return keypadAssignSubtitle(s.toBudget, symbol: symbol);
      case KeypadAction.unassign:
        final e = _env(s, r.envelopeId);
        return keypadUnassignSubtitle(e?.available ?? 0, symbol: symbol);
      case KeypadAction.transfer:
        final f = _env(s, r.fromId);
        return keypadTransferSubtitle(
          f?.name ?? unknownEnvelope,
          f?.available ?? 0,
          symbol: symbol,
        );
      case KeypadAction.expense:
        final e = _env(s, r.envelopeId);
        return keypadExpenseSubtitle(
          e?.name ?? unknownEnvelope,
          e?.available ?? 0,
          symbol: symbol,
        );
      case KeypadAction.income:
        return keypadIncomeSubtitle;
      case KeypadAction.editAmount:
        final tx = r.editTx!;
        return keypadEditAmountSubtitle(
          tx.amount,
          tx.description,
          symbol: symbol,
        );
    }
  }

  // 描述栏占位文案把兜底结果直接说出来（ADR-0008）
  String _placeholder(LedgerState s) {
    final r = widget.request;
    switch (r.action) {
      case KeypadAction.assign:
        return placeholderAssign(
          _env(s, r.envelopeId)?.name ?? unknownEnvelope,
        );
      case KeypadAction.unassign:
        return placeholderUnassign(
          _env(s, r.envelopeId)?.name ?? unknownEnvelope,
        );
      case KeypadAction.transfer:
        return placeholderTransfer(
          _env(s, r.fromId)?.name ?? unknownEnvelope,
          _env(s, r.envelopeId)?.name ?? unknownEnvelope,
        );
      case KeypadAction.expense:
        return placeholderExpense(_env(s, r.envelopeId)?.name ?? '一笔支出');
      case KeypadAction.income:
        return placeholderIncome;
      case KeypadAction.editAmount:
        return placeholderEditAmount(r.editTx?.description ?? '');
    }
  }

  // ── 校验 ─────────────────────────────────────

  // hard 时「确定」置灰；warn 只提示不拦截（透支合法，不变量①）
  ({bool hard, String? warn}) _check(LedgerState s, double v, String symbol) {
    final r = widget.request;
    switch (r.action) {
      case KeypadAction.assign:
        final err = validateAssign(s, v, symbol: symbol);
        return (hard: err != null, warn: err);
      case KeypadAction.unassign:
        return (
          hard: false,
          warn: warnUnassign(s, r.envelopeId!, v, symbol: symbol),
        );
      case KeypadAction.transfer:
        return (
          hard: false,
          warn: warnTransfer(s, r.fromId!, v, symbol: symbol),
        );
      case KeypadAction.expense:
        return (
          hard: false,
          warn: warnExpense(s, r.envelopeId!, v, symbol: symbol),
        );
      case KeypadAction.income:
        return (hard: false, warn: null);
      case KeypadAction.editAmount:
        return validateEditAmount(s, r.editTx!, v, symbol: symbol);
    }
  }

  // ── 时间行与历史候选（v1.3.0 票 01/03）─────────

  // 改金额语境不显示时间行与候选：编辑不动时间、不记历史（不变量⑥/ADR-0019）
  bool get _isEditAmount => widget.request.action == KeypadAction.editAmount;

  // 本次键盘所对信封（含待规划）的 id 集：历史候选展示与记录归属共用同一映射
  // （ADR-0020：支出记支出信封、收入记待规划、转移 from/to 两侧、分配/撤销记所对信封）
  List<String> _historyEnvelopeIds() {
    final r = widget.request;
    return switch (r.action) {
      KeypadAction.expense ||
      KeypadAction.assign ||
      KeypadAction.unassign => [r.envelopeId!],
      KeypadAction.income => [kToBudget],
      KeypadAction.transfer => [r.fromId!, r.envelopeId!],
      KeypadAction.editAmount => const [],
    };
  }

  // 时间行（票 01）：时钟图标 + 时刻文本 + 箭头，点击进滚轮弹层补记。
  // 文本用 atLabel——非当年带年份（与详情页时间行同一条跨年规则）。
  Widget _timeRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickTime,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: 14,
                color: T.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                atLabel(_at, DateTime.now()),
                style: const TextStyle(
                  fontSize: T.typeXs,
                  color: T.textSecondary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 16, color: T.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // 点时间行 → 复用详情页滚轮弹层（同一交互语言，ADR-0019：上限今天、无下限）
  Future<void> _pickTime() async {
    final picked = await showTimeEditSheet(context, initial: _at);
    if (picked == null || !mounted) return;
    setState(() => _at = picked);
  }

  // 历史候选胶囊行（票 03）：描述栏聚焦且该信封有历史时浮出；转移语境合并
  // from/to 两侧（去重、最近优先）；点胶囊即填入并收起输入法。
  Widget _historyChips() {
    final ledger = ref.watch(activeLedgerProvider);
    if (ledger == null) return const SizedBox.shrink();
    final seen = <String>{};
    final chips = <String>[];
    for (final id in _historyEnvelopeIds()) {
      final list =
          ref.watch(descriptionHistoryProvider((ledger.id, id))).value ??
          const <String>[];
      for (final d in list) {
        if (seen.add(d) && chips.length < kDescriptionHistoryLimit) {
          chips.add(d);
        }
      }
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _QuickChip(
            label: chips[i],
            onTap: () {
              _noteCtrl.text = chips[i];
              // 点候选 = 完成输入：填入并收起输入法
              _noteFocus.unfocus();
            },
          ),
        ),
      ),
    );
  }

  // ── 提交 ─────────────────────────────────────

  // 普通按键：数字 / 运算符 / 括号 / 小数点 / C 清空
  void _onKey(String k) {
    setState(() {
      _hint = null;
      if (k == 'C') {
        _expr = '';
        _evaluated = false;
        return;
      }
      // 刚按过 =：按数字或小数点 → 重新开始输入；按运算符 → 在结果上继续算
      if (_evaluated) {
        _evaluated = false;
        if (RegExp(r'^[\d.]$').hasMatch(k)) _expr = '';
      }
      // 智能括号：有未闭合括号且前面是数字/右括号 → 这个键插 ')'
      if (k == '(') {
        final open =
            '('.allMatches(_expr).length - ')'.allMatches(_expr).length;
        final last = _expr.isEmpty ? '' : _expr.substring(_expr.length - 1);
        if (open > 0 && RegExp(r'[\d)]').hasMatch(last)) k = ')';
      }
      final next = appendKeyToExpr(_expr, k);
      if (next != null) _expr = next;
    });
  }

  // 按「=」：先修复表达式（去掉尾部无效符号、补齐括号）再求值
  void _doEquals() {
    final v = evaluateExpression(normalizeForEval(_expr));
    if (v == null) {
      setState(() => _hint = keypadEvalErrorHint);
      return;
    }
    setState(() {
      _expr = _fmtExpr(v);
      _evaluated = true;
      _hint = null;
    });
  }

  // 快捷胶囊：在当前表达式（修复后）的求值结果上累加
  void _onQuickAdd(double quick) {
    setState(() {
      _hint = null;
      _evaluated = false;
      final cur = evaluateExpression(normalizeForEval(_expr)) ?? 0;
      _expr = _fmtExpr(round2(cur + quick));
    });
  }

  // ALL IN 胶囊：把表达式整体替换为资金来源全额（替换而非累加，可重复按）
  void _onAllIn(double full) {
    setState(() {
      _hint = null;
      _evaluated = false;
      _expr = _fmtExpr(round2(full));
    });
  }

  Future<void> _confirm(LedgerState s) async {
    final v = evaluateExpression(normalizeForEval(_expr));
    if (v == null || v <= 0) return;
    if (_check(s, v, ref.read(currencySymbolProvider)).hard) return;
    final note = _noteCtrl.text.trim();
    Navigator.of(context).pop(true);
    await widget.onConfirm(v, note, _at);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerStateProvider);
    // 当前账本货币符号（ADR-0017）：上下文文案与金额行前缀共用
    final symbol = ref.watch(currencySymbolProvider);
    final value = evaluateExpression(_expr);
    final check = value != null && value > 0
        ? _check(state, value, symbol)
        : (hard: false, warn: null);
    // 提示行优先显示手动提示（= 求值失败等）
    final warn = _hint ?? check.warn;
    final okEnabled = value != null && value > 0 && !check.hard;
    // ALL IN 的资金来源全额：支出/转移取来源信封剩余，分配取待规划；其余语境不显示胶囊
    final allIn = switch (widget.request.action) {
      KeypadAction.expense => _env(state, widget.request.envelopeId)?.available,
      KeypadAction.transfer => _env(state, widget.request.fromId)?.available,
      KeypadAction.assign => state.toBudget,
      _ => null,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        // 高度由内容决定（键盘区是 Flexible，空间不足时钳高裁底，见下方注释），
        // 任何机型、任何字号都不会产生 RenderFlex 溢出报错
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
          children: [
            const SizedBox(height: 20),
            // 拖拽把手 36×4
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE3DCD0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // 上下文行
            Text(
              _title(state),
              style: const TextStyle(
                fontSize: T.typeMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _subtitle(state, symbol),
              style: const TextStyle(
                fontSize: T.typeXs,
                color: T.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            // 金额行：货币符号 + 表达式 + 闪烁光标
            SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    symbol,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _expr.isEmpty ? '0' : _expr,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: _expr.isEmpty ? T.textTertiary : T.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  // 光标
                  Container(
                    width: 2,
                    height: 32,
                    color: _cursorOn ? T.primary : Colors.transparent,
                  ),
                ],
              ),
            ),
            // 校验提示行
            SizedBox(
              height: warn == null ? 0 : 16,
              child: Text(
                warn ?? '',
                style: const TextStyle(fontSize: T.typeXs, color: T.overspend),
              ),
            ),
            const SizedBox(height: 6),
            // 时间行（v1.3.0 票 01 / ADR-0019）：默认当前时间，点击滚轮补记到
            // 任意过去时刻（上限今天）；改金额语境不显示（编辑不动时间）
            if (!_isEditAmount) ...[
              _timeRow(),
              const SizedBox(height: 6),
            ],
            // 历史候选胶囊（v1.3.0 票 03）：描述栏聚焦（输入法弹起）时浮出；
            // 无历史 / 改金额语境不占位
            if (!_isEditAmount && _noteFocus.hasFocus) _historyChips(),
            // 描述栏（整张键盘唯一的选填字段）
            Container(
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: T.surfaceSubtle,
                borderRadius: BorderRadius.circular(T.radiusKey),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    size: 16,
                    color: T.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _noteCtrl,
                      focusNode: _noteFocus,
                      style: const TextStyle(
                        fontSize: T.typeBase,
                        color: T.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: _placeholder(state),
                        hintStyle: const TextStyle(
                          fontSize: T.typeBase,
                          color: T.textTertiary,
                        ),
                      ),
                      inputFormatters: [LengthLimitingTextInputFormatter(30)],
                    ),
                  ),
                ],
              ),
            ),
            // 快捷胶囊 + 数字键盘：空间富余时原样显示；描述栏唤起输入法、
            // 整体高度超过可用空间时钳到剩余高度并裁掉底部——键盘原地不动、
            // 被输入法「掠过」盖住下半截，描述栏始终在输入法上方可见（DESIGN.md §5）
            Flexible(
              // 只负责空间不足时「钳高裁底」，不允许用户滚动（键盘不该滚）
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
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
                            // ALL IN：来源透支或为零时置灰（想法：透支无效）
                            if (allIn != null)
                              _QuickChip(
                                label: 'ALL IN',
                                onTap: allIn > 0 ? () => _onAllIn(allIn) : null,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 5 行键盘：C ÷ × ⌫ / 123− / 456+ / 789= / () 0 .
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _Pad(
                        onKey: _onKey,
                        onDelete: () => setState(() {
                          _hint = null;
                          _evaluated = false;
                          if (_expr.isNotEmpty) {
                            _expr = _expr.substring(0, _expr.length - 1);
                          }
                        }),
                        onEquals: _doEquals,
                        onOk: () => _confirm(state),
                        showEquals: _isExprMode,
                        equalsEnabled: _expr.isNotEmpty,
                        okEnabled: okEnabled,
                        okLabel: widget.request.okLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// 快捷金额胶囊（onTap 为 null 时置灰禁用——ALL IN 的透支/零额态）
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

// 5 行键盘 — 参照计算器排布：
//   C  ÷  ×  ⌫
//   1  2  3  −
//   4  5  6  +
//   7  8  9  =(跨两行)
//   () 0  .  ↓
// 含运算符/括号时右下大键显示「=」（先求值），求出结果显示 okLabel（再落账）。
class _Pad extends StatelessWidget {
  const _Pad({
    required this.onKey,
    required this.onDelete,
    required this.onEquals,
    required this.onOk,
    required this.showEquals,
    required this.equalsEnabled,
    required this.okEnabled,
    required this.okLabel,
  });

  final void Function(String key) onKey;
  final VoidCallback onDelete;

  // 按「=」：修复表达式并求值
  final VoidCallback onEquals;

  // 按「确定」：提交交易
  final VoidCallback onOk;

  // true = 右下大键显示「=」；false = 显示 okLabel
  final bool showEquals;
  final bool equalsEnabled;
  final bool okEnabled;
  final String okLabel;

  // 键帽高度（比原型的 45 加高，提升触控手感）
  static const double _keyH = 56;

  // 行/列间距
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    // 左 3 列 × 5 行 + 右 1 列（= 键跨 2 行）
    return SizedBox(
      height: 5 * _keyH + 4 * _gap, // 312
      child: Row(
        children: [
          // ── 左 3 列 ──
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _row(['C', '÷', '×']),
                _vGap,
                _row(['1', '2', '3']),
                _vGap,
                _row(['4', '5', '6']),
                _vGap,
                _row(['7', '8', '9']),
                _vGap,
                _row(['()', '0', '.']),
              ],
            ),
          ),
          const SizedBox(width: _gap),
          // ── 右 1 列：⌫ − + =（= 跨 2 行）──
          Expanded(
            child: Column(
              children: [
                Expanded(child: _keyWidget('⌫')),
                _vGap,
                Expanded(child: _keyWidget('−')),
                _vGap,
                Expanded(child: _keyWidget('+')),
                _vGap,
                Expanded(flex: 2, child: _equalsKey()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 一行 3 键（等宽 + 列间距）
  Widget _row(List<String> keys) {
    return Expanded(
      child: Row(
        children: [
          for (var c = 0; c < keys.length; c++) ...[
            if (c > 0) const SizedBox(width: _gap),
            Expanded(child: _keyWidget(keys[c])),
          ],
        ],
      ),
    );
  }

  // 垂直间距
  Widget get _vGap => const SizedBox(height: _gap);

  // 单个键位 → 对应键帽组件
  Widget _keyWidget(String key) {
    switch (key) {
      case '⌫':
        return _Key(
          onTap: onDelete,
          child: const Icon(
            Icons.backspace_outlined,
            size: 21,
            color: T.textPrimary,
          ),
        );
      case '()':
        // 智能括号：可开括号时插 '('，否则插 ')'
        return _Key(
          onTap: () => onKey('('),
          secondary: true,
          child: const Text(
            '( )',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: T.textSecondary,
            ),
          ),
        );
      case '+':
      case '−':
      case '×':
      case '÷':
        return _Key(
          onTap: () => onKey(key),
          secondary: true,
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: T.textSecondary,
            ),
          ),
        );
      case 'C':
        return _Key(
          onTap: () => onKey('C'),
          secondary: true,
          child: const Text(
            'C',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: T.textSecondary,
            ),
          ),
        );
      default:
        // 数字与小数点
        return _Key(
          onTap: () => onKey(key),
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: T.textPrimary,
            ),
          ),
        );
    }
  }

  // 右下大键：= 态（求值）/ 确定态（落账），全键盘唯一的黄色实心按钮
  Widget _equalsKey() {
    final enabled = showEquals ? equalsEnabled : okEnabled;
    return Material(
      // 置灰态：#F3EFE7 底 + #CCC4B8 字
      color: enabled ? T.primary : const Color(0xFFF3EFE7),
      borderRadius: BorderRadius.circular(T.radiusKey),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.radiusKey),
        onTap: enabled
            ? () {
                if (showEquals) {
                  onEquals();
                } else {
                  onOk();
                }
              }
            : null,
        child: Center(
          child: Text(
            showEquals ? '=' : okLabel,
            style: TextStyle(
              fontSize: showEquals ? 24 : T.typeMd,
              fontWeight: FontWeight.w700,
              color: enabled ? T.textPrimary : const Color(0xFFCCC4B8),
            ),
          ),
        ),
      ),
    );
  }
}

// 普通键帽：#F7F2E8 底、圆角 12、高 56
class _Key extends StatelessWidget {
  const _Key({
    required this.onTap,
    required this.child,
    this.secondary = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool secondary;

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

// 快捷加法后把数值回写成表达式串
String _fmtExpr(double v) {
  final isInt = v == v.roundToDouble();
  return isInt ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
