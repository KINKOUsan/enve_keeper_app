// 交易详情页 — 金额区 + 字段卡 + 撤销（DESIGN.md §16 + ADR-0012）。
// 推入页。编辑闭环：点金额区改金额（键盘 editAmount）、点描述行改描述；
// 「撤销」= 原「删除」（revert 余额 + 删行），确认框算出具体数字（§16.1），
// 会破坏待规划非负的撤销被挡住（不变量⑦）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../domain/tx_engine.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../common/format.dart';
import '../copy.dart';
import '../keypad/keypad_flow.dart';
import '../keypad/keypad_models.dart';

class TxnDetailPage extends ConsumerStatefulWidget {
  const TxnDetailPage({super.key, required this.txn});

  // 传入的交易（build 内会按 id 重取最新值，编辑后界面自动刷新）
  final Txn txn;

  @override
  ConsumerState<TxnDetailPage> createState() => _TxnDetailPageState();
}

class _TxnDetailPageState extends ConsumerState<TxnDetailPage> {
  // 自动关闭防重入：撤销/删除后交易行消失，drift 一次事务会刷新多个流导致
  // 连续多次 rebuild，若每次都注册 pop 会把底下的 home route 也弹掉（黑屏）。
  bool _autoPopped = false;

  @override
  Widget build(BuildContext context) {
    // 以 id 重取最新交易（金额/描述被改后刷新）
    final txns = ref.watch(txnsProvider).value ?? const <Txn>[];
    final t = txns.where((x) => x.id == widget.txn.id).firstOrNull;
    if (t == null) {
      // 已被撤销/删除：只安排一次关闭（pop 有过渡动画，动画期间 mounted 仍为 true，
      // 必须用标志位防止后续 postFrame 重复 pop）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_autoPopped) return;
        _autoPopped = true;
        if (context.mounted) Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final envelopes = ref.watch(envelopesProvider).value ?? const [];
    final envById = {for (final e in envelopes) e.id: e};

    // 结转退回是系统行为（ADR-0016）：不可编辑、不可撤销，详情页纯只读
    final isSystemRefund = t.type == TxType.refund;

    // 金额区的底色：支出/转移/结转退回用关联信封色，收入用暖黄
    final relatedEnv = t.type == TxType.expense
        ? envById[t.envelopeId]
        : ((t.type == TxType.transfer || t.type == TxType.refund)
              ? envById[t.fromId]
              : null);
    final tint = relatedEnv?.color != null
        ? envelopeColorById(relatedEnv!.color).tint
        : T.primarySoft;
    final borderColor = relatedEnv?.color != null
        ? envelopeColorById(relatedEnv!.color).main
        : const Color(0xFFFFE49B);

    // 类型胶囊文案
    final String typeLabel;
    switch (t.type) {
      case TxType.expense:
        typeLabel = '支出';
      case TxType.income:
        typeLabel = '收入';
      case TxType.transfer:
        typeLabel = '转移';
      case TxType.refund:
        typeLabel = '结转退回';
    }

    // 金额文本与颜色（语义色与流水页一致）；符号取当前账本设置（ADR-0017）
    final symbol = ref.watch(currencySymbolProvider);
    final String amountText;
    var amountColor = T.textPrimary;
    switch (t.type) {
      case TxType.expense:
        amountText = '−$symbol${money(t.amount)}';
        amountColor = T.overspend;
      case TxType.income:
        amountText = '+$symbol${money(t.amount)}';
        amountColor = const Color(0xFF17A673);
      case TxType.transfer:
        amountText = '$symbol${money(t.amount)}';
        amountColor = const Color(0xFF8A8378);
      case TxType.refund:
        amountText = '$symbol${money(t.amount)}';
        amountColor = const Color(0xFF8A8378);
    }

    return Scaffold(
      backgroundColor: T.bg,
      // 页面本身没有直接的文本输入（改描述走对话框、改金额走键盘弹层，
      // 二者各自处理输入法 inset），不随输入法缩放，避免固定高度的
      // 内容在输入法打开时溢出（对话框唤起输入法时页面在遮罩后仍会 rebuild）
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 页头：返回 + 标题 + 删除 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Material(
                        color: T.surfaceSubtle,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 16,
                            color: T.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '交易详情',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 撤销（红字无底色；原「删除」，ADR-0012 术语）
                    // 结转退回不提供撤销入口（ADR-0016：系统行为，撤销会破坏钱守恒）
                    if (!isSystemRefund)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _revert(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            '撤销',
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
            ),
            const SizedBox(height: 8),
            // ── 金额区（点它改金额；结转退回是系统行为不可改）──
            GestureDetector(
              onTap: isSystemRefund ? null : () => _editAmount(context, t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 144,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 类型胶囊
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: relatedEnv?.color != null
                              ? envelopeColorById(relatedEnv!.color)
                                    .withAlpha(0.18)
                              : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          typeLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6E675C),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        amountText,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: amountColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6E675C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // ── 字段卡 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: T.surface,
                  borderRadius: BorderRadius.circular(20),
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
                    _FieldRow(
                      label: '描述',
                      value: t.description,
                      // 结转退回描述写入时定型（系统行为，不开放编辑）
                      editable: !isSystemRefund,
                      onTap: () => _editDescription(context, t),
                    ),
                    // 信封 / 从 / 到：编辑引擎待扩展，先展示不给箭头
                    if (t.type == TxType.expense)
                      _FieldRow(
                        label: '信封',
                        value: envById[t.envelopeId]?.name ?? '未知',
                      ),
                    if (t.type == TxType.transfer ||
                        t.type == TxType.refund) ...[
                      _FieldRow(
                        label: '从',
                        value: t.fromId == kToBudget
                            ? '待规划'
                            : (envById[t.fromId]?.name ?? '未知'),
                      ),
                      _FieldRow(
                        label: '到',
                        value: t.toId == kToBudget
                            ? '待规划'
                            : (envById[t.toId]?.name ?? '未知'),
                      ),
                    ],
                    _FieldRow(
                      label: '时间',
                      value: '${t.at.month}月${t.at.day}日 ${clockLabel(t.at)}',
                    ),
                    // 类型不可改（ADR-0009）：字色降 + 无箭头
                    _FieldRow(
                      label: '类型',
                      value: '$typeLabel · 不可修改',
                      dim: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 规则提示行（结转退回换成系统行为说明，不出现「点金额改」误导）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                isSystemRefund ? refundDetailHint : txnEditRulesHint,
                style: const TextStyle(
                  fontSize: T.typeXs,
                  height: 1.6,
                  color: Color(0xFFB4AC9F),
                ),
              ),
            ),
            const Spacer(),
            // ── 撤销按钮：红浅底描边，不是实心红（原「删除这笔记录」）──
            // 结转退回是系统行为：不提供撤销入口（ADR-0016）
            if (!isSystemRefund)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 52,
                  child: Material(
                    color: DangerTint.bg,
                    shape: StadiumBorder(
                      side: BorderSide(color: DangerTint.border, width: 1),
                    ),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _revert(context),
                      child: const Center(
                        child: Text(
                          '撤销这笔记录',
                          style: TextStyle(
                            fontSize: T.typeBase,
                            fontWeight: FontWeight.w600,
                            color: T.overspend,
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

  // ── 编辑动作 ────────────────────────────────

  // 改金额：复用数字键盘，动作名「改金额」、描述栏预填当前描述（§16.2）
  Future<void> _editAmount(BuildContext context, Txn t) async {
    await runKeypadFlow(
      context,
      ref,
      KeypadRequest(
        action: KeypadAction.editAmount,
        editTx: t,
        initialExpr: _fmtExpr(t.amount),
        titleOverride: '改金额',
      ),
    );
  }

  // 改描述：文本输入对话框
  Future<void> _editDescription(BuildContext context, Txn t) async {
    final ctrl = TextEditingController(text: t.description);
    final desc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改描述'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: editDescriptionHint),
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
    if (desc == null || desc.isEmpty || desc == t.description) return;
    await ref.read(repoProvider).editTransactionDescription(t.id, desc);
  }

  // 撤销（原删除，ADR-0012）：先校验不变量⑦，再在确认框里算出后果数字（§16.1）。
  // 涉及停用信封的笔：不碰任何余额（repo 分流），确认框单独说明。
  Future<void> _revert(BuildContext context) async {
    final t = widget.txn;
    final state = ref.read(ledgerStateProvider);

    // 停用信封检测（ADR-0012）：撤销它的流水不改变任何余额，只是移除档案记录
    final all = ref.read(allEnvelopesProvider).value ?? const <Envelope>[];
    final archivedName = archivedEnvelopeNameOf(t, all);

    // 不变量⑦检查只对会动余额的笔有意义
    String consequence;
    if (archivedName != null) {
      consequence = revertArchivedConsequence(archivedName);
    } else {
      // 不变量⑦：撤销会让待规划变负 → 挡住并说明
      if (!deleteKeepsToBudgetNonNegative(state, t)) {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('撤不掉'),
              content: const Text(revertWouldGoNegativeBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 算出撤销后的变化，写进确认文案
      final after = applyTx(state, t, kRevert);
      consequence = _consequenceText(
        state,
        after,
        t,
        ref.read(currencySymbolProvider),
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销这笔记录？'),
        content: Text('$consequence\n$revertIrreversibleLine'),
        // 注意：AlertDialog 的 actions 是 OverflowBar（非 Flex），
        // 放 Expanded 会抛 ParentDataWidget 异常导致整页崩溃
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: T.surfaceSubtle,
              foregroundColor: T.textSecondary,
              minimumSize: const Size(110, 44),
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: T.overspend,
              foregroundColor: Colors.white,
              minimumSize: const Size(110, 44),
            ),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ledger = ref.read(activeLedgerProvider);
    await ref
        .read(repoProvider)
        .revertTransaction(ledgerId: ledger!.id, txn: t);
    if (context.mounted) {
      // 关键：先占住自动关闭标志——撤销后交易行消失会触发 build 的 postFrame 自动 pop，
      // 而 pop 动画期间 context.mounted 仍为 true，不占标志会造成双重 pop 弹空导航栈
      _autoPopped = true;
      appToast(context, toastReverted);
      Navigator.of(context).pop();
    }
  }

  // 后果文案：对比撤销前后的关键数字（§16.1 的「饮食的已使用从 760 退回 692」）
  String _consequenceText(
    LedgerState before,
    LedgerState after,
    Txn t,
    String symbol,
  ) {
    switch (t.type) {
      case TxType.expense:
        final e = before.envelopes[t.envelopeId];
        final ea = after.envelopes[t.envelopeId];
        if (e == null || ea == null) return revertFallbackConsequence;
        return revertExpenseConsequence(
          e.name,
          e.used,
          ea.used,
          ea.available,
          symbol: symbol,
        );
      case TxType.income:
        return revertIncomeConsequence(
          before.toBudget,
          after.toBudget,
          symbol: symbol,
        );
      case TxType.transfer:
        final from = before.envelopes[t.fromId];
        final to = before.envelopes[t.toId];
        final fromA = after.envelopes[t.fromId];
        if (t.isAssign) {
          return revertAssignConsequence(
            to?.name,
            to?.planned ?? 0,
            fromA != null ? after.envelopes[to!.id]?.planned ?? 0 : 0,
            after.toBudget,
            symbol: symbol,
          );
        }
        if (t.isUnassign) {
          return revertUnassignConsequence(
            from?.name,
            from?.planned ?? 0,
            after.envelopes[from!.id]?.planned ?? 0,
            symbol: symbol,
          );
        }
        return revertTransferConsequence(from?.name, to?.name);
      case TxType.refund:
        // 结转退回无撤销入口（ADR-0016），此处仅穷尽性兜底
        return revertFallbackConsequence;
    }
  }
}

// 字段卡的一行：字段名固定 56 + 值 + 可选右箭头（没箭头 = 不可点）
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    this.editable = false,
    this.dim = false,
    this.onTap,
  });

  final String label;
  final String value;

  // true = 显示右箭头、可点
  final bool editable;

  // 字色降一档（类型行）
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: editable ? onTap : null,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8378)),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w500,
                  color: dim ? const Color(0xFFB5AB9E) : T.textPrimary,
                ),
              ),
            ),
            if (editable)
              const Icon(Icons.chevron_right, size: 16, color: T.textTertiary),
          ],
        ),
      ),
    );
  }
}

// 金额转表达式串（编辑预填）
String _fmtExpr(double v) {
  final isInt = v == v.roundToDouble();
  return isInt ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
