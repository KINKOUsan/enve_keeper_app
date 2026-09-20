// 信封详情页 — 概览卡（信封色刷整块板）+ 该信封的流水列表（DESIGN.md §12 + ADR-0012）。
// 推入页。右上编辑按钮进编辑弹层（含停用）；流水列表支持多选批量撤销（长按进入）。
// 流水列表带与流水页同款的筛选 + 排序（票 05），组件共用 ui/txn/txn_filter_sheet.dart。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../domain/txn_filter.dart';
import '../../../state/providers.dart';
import '../../../theme/envelope_icons.dart';
import '../../../theme/tokens.dart';
import '../common/format.dart';
import '../copy.dart';
import '../keypad/keypad_flow.dart';
import '../txn/txn_batch.dart';
import '../txn/txn_detail_page.dart';
import '../txn/txn_filter_sheet.dart';
import 'envelope_edit_sheet.dart';

class EnvelopeDetailPage extends ConsumerStatefulWidget {
  const EnvelopeDetailPage({super.key, required this.envelopeId});

  final String envelopeId;

  @override
  ConsumerState<EnvelopeDetailPage> createState() => _EnvelopeDetailPageState();
}

class _EnvelopeDetailPageState extends ConsumerState<EnvelopeDetailPage> {
  // 多选状态（长按进入，批量撤销）
  final _sel = TxnSelection();

  // 流水列表的筛选条件与排序方向（与流水页同款，票 05）
  TxnFilter _filter = const TxnFilter();
  TxnSort _sort = TxnSort.newest;

  @override
  void initState() {
    super.initState();
    _sel.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sel.dispose();
    super.dispose();
  }

  // 切换排序方向
  void _toggleSort() => setState(
    () => _sort = _sort == TxnSort.newest ? TxnSort.oldest : TxnSort.newest,
  );

  // 打开筛选面板，应用返回的条件
  Future<void> _openFilter() async {
    final applied = await showTxnFilterSheet(context, _filter);
    if (!mounted) return;
    setState(() => _filter = applied);
  }

  @override
  Widget build(BuildContext context) {
    // 用全部信封查（含停用——停用瞬间本页可能还开着）
    final envelopes = ref.watch(allEnvelopesProvider).value ?? const [];
    final e = envelopes.where((x) => x.id == widget.envelopeId).firstOrNull;
    if (e == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final txns = ref.watch(txnsProvider).value ?? const <Txn>[];
    // 当前账本货币符号（ADR-0017）：概览卡与流水行共用
    final symbol = ref.watch(currencySymbolProvider);
    // 首页金额隐私的隐藏 id 集（v1.2.0 票 03）：开关读显只在这里，金额照常显示
    final hiddenIds = ref.watch(hiddenEnvelopeIdsProvider);
    final related = txns
        .where(
          (t) => t.envelopeId == e.id || t.fromId == e.id || t.toId == e.id,
        )
        .toList();
    // 筛选 + 排序后的可见列表（多选/批量撤销只作用于可见行，票 05）
    final visible = sortTxns(related.where(_filter.match).toList(), _sort);
    // 多选池排除结转退回（ADR-0016：系统行为不可撤销）
    final selectable = visible.where((t) => t.type != TxType.refund).toList();

    final color = envelopeColorById(e.color);
    final over = e.available < 0;
    final ratio = e.planned > 0 ? (e.used / e.planned).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 顶栏：多选工具栏替换常规页头 ──
            if (_sel.mode)
              _DetailSelectBar(
                count: _sel.count,
                totalCount: selectable.length,
                onSelectAll: () => _sel.toggleAll(selectable),
                onExit: _sel.exit,
              )
            else ...[
              // ── 页头：返回 + 名 + 编辑 ──
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
                      Expanded(
                        child: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // 编辑按钮
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Material(
                          color: T.surfaceSubtle,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              final archived = await showEditEnvelopeSheet(
                                context,
                                ref,
                                e,
                              );
                              if (!archived || !context.mounted) return;
                              // 停用成功：提示后一路返回主界面（信封已从首页消失）
                              appToast(context, '已停用「${e.name}」，新建同名可恢复');
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            },
                            child: const Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: T.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // ── 概览卡：信封 tint 底 + 同色描边 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 148,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.tint,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.main, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: color.main,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              envelopeIconById(e.icon),
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            e.name,
                            style: const TextStyle(
                              fontSize: T.typeBase,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6E675C),
                            ),
                          ),
                          const Spacer(),
                          // 白胶囊「金额可见 / 金额已隐藏」——首页金额隐私开关
                          // （v1.2.0 票 03：结转胶囊旁，点按就地切换，仅首页生效）
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                final ids = ref.read(hiddenEnvelopeIdsProvider);
                                ref
                                    .read(hiddenEnvelopeIdsProvider.notifier)
                                    .setHidden(e.id, !ids.contains(e.id));
                              },
                              child: _whiteCapsule(
                                hiddenIds.contains(e.id) ? '金额已隐藏' : '金额可见',
                              ),
                            ),
                          ),
                          // 白胶囊「结转 开 / 不结转」
                          _whiteCapsule(e.carryover ? '结转 开' : '不结转'),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        moneySigned(e.available, symbol: symbol),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: over ? T.overspend : T.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已规划 $symbol${money(e.planned)} · 已使用 $symbol${money(e.used)}',
                        style: const TextStyle(
                          fontSize: T.typeXs,
                          color: Color(0xFF8A8378),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 6dp 进度条
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              Container(color: color.withAlpha(0.2)),
                              FractionallySizedBox(
                                widthFactor: over ? 1.0 : ratio,
                                child: Container(
                                  color: over ? T.overspend : color.main,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            // ── 流水列表标题行：笔数 + 排序 + 筛选 + 批量撤销入口 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Text(
                    // 筛选激活时显示「可见/总数」
                    _filter.isActive
                        ? '流水 · ${visible.length}/${related.length} 笔'
                        : '流水 · ${related.length} 笔',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8A8378),
                    ),
                  ),
                  const Spacer(),
                  if (!_sel.mode && related.isNotEmpty) ...[
                    // 排序切换（与流水页同款）
                    TxnSortButton(sort: _sort, onToggle: _toggleSort),
                    const SizedBox(width: 6),
                    // 筛选入口（与流水页同款，激活时黄底带点）
                    TxnFilterButton(
                      active: _filter.isActive,
                      onTap: _openFilter,
                    ),
                    const SizedBox(width: 6),
                    // 长按也可进入多选；这里给显式入口（多选池不含结转退回）
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: selectable.isEmpty
                          ? null
                          : () => _sel.enter(selectable.first.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          '批量撤销',
                          style: TextStyle(
                            fontSize: T.typeXs,
                            fontWeight: FontWeight.w500,
                            color: visible.isEmpty
                                ? T.textTertiary
                                : const Color(0xFF8A6A00),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── 条件条：筛选激活时逐项可移除 ──
            if (_filter.isActive)
              TxnConditionBar(
                filter: _filter,
                onRemoveType: () =>
                    setState(() => _filter = _filter.withType(null)),
                onRemoveDay: () =>
                    setState(() => _filter = _filter.withoutDay()),
                onRemoveRange: () =>
                    setState(() => _filter = _filter.withoutRange()),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        // 有流水但被筛空 vs 本来就没有
                        related.isEmpty
                            ? emptyEnvelopeTxns
                            : emptyFilteredTitle,
                        style: const TextStyle(
                          fontSize: T.typeBase,
                          color: T.textTertiary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        _sel.mode ? 88 : 16,
                      ),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, i) {
                        final t = visible[i];
                        final selected = _sel.ids.contains(t.id);
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _sel.mode
                              ? _toggleIfSelectable(t)
                              : _openTxn(context, t),
                          // 长按进入多选；结转退回不可撤销（ADR-0016）不进多选
                          onLongPress: t.type == TxType.refund
                              ? null
                              : () => _sel.enter(t.id),
                          child: Container(
                            height: 54,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: _sel.mode && selected
                                  ? T.primarySoft
                                  : T.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: _sel.mode && selected
                                  ? Border.all(color: T.primary)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                if (_sel.mode) ...[
                                  _CheckCircle(checked: selected),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    t.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: T.typeBase,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _amountText(t, symbol),
                                  style: TextStyle(
                                    fontSize: T.typeBase,
                                    fontWeight: FontWeight.w600,
                                    color: _amountColor(t),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // ── 底部操作条：批量撤销（只作用于可见的多选池）──
            if (_sel.mode)
              _DetailBatchBar(
                count: _sel.count,
                onRevert: () => _revertSelected(selectable),
              ),
          ],
        ),
      ),
    );
  }

  // 批量撤销所选（整批预检 + 二次确认）
  Future<void> _revertSelected(List<Txn> pool) async {
    final picked = _sel.pick(pool);
    if (picked.isEmpty) return;
    final ok = await confirmBatchRevert(context, ref, picked);
    if (!ok || !mounted) return;
    await executeBatchRevert(context, ref, picked);
    _sel.exit();
  }

  // 多选模式下点行：结转退回不可选中（ADR-0016），其余正常切换
  void _toggleIfSelectable(Txn t) {
    if (t.type != TxType.refund) _sel.toggle(t.id);
  }

  // 金额文本：支出带负号 / 收入加号 / 转移与结转退回无符号
  String _amountText(Txn t, String symbol) {
    switch (t.type) {
      case TxType.expense:
        return '−$symbol${money(t.amount)}';
      case TxType.income:
        return '+$symbol${money(t.amount)}';
      case TxType.transfer:
      case TxType.refund:
        return '$symbol${money(t.amount)}';
    }
  }

  // 金额语义色
  Color _amountColor(Txn t) {
    switch (t.type) {
      case TxType.expense:
        return T.overspend;
      case TxType.income:
        return const Color(0xFF17A673);
      case TxType.transfer:
      case TxType.refund:
        return const Color(0xFF8A8378);
    }
  }

  // 进入交易详情
  void _openTxn(BuildContext context, Txn t) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => TxnDetailPage(txn: t)));
  }
}

// ── 概览卡白胶囊（DESIGN.md §12）：结转状态与金额隐私开关共用 ──

/// 高 24 白底胶囊：10 Medium 暖灰字，概览卡首行右侧的两种状态胶囊共用样式
Widget _whiteCapsule(String label) {
  return Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: T.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: Color(0xFF6E675C),
      ),
    ),
  );
}

// ── 多选工具（与流水页同视觉）──────────────────

// 勾选圈：20dp，选中黄底白勾
class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? T.primary : Colors.transparent,
        border: Border.all(
          color: checked ? T.primary : const Color(0xFFCCC4B8),
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 13, color: T.textPrimary)
          : null,
    );
  }
}

// 多选顶栏
class _DetailSelectBar extends StatelessWidget {
  const _DetailSelectBar({
    required this.count,
    required this.totalCount,
    required this.onSelectAll,
    required this.onExit,
  });

  final int count;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onExit,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 20, color: T.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '已选 $count 项',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onSelectAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  count >= totalCount ? '全不选' : '全选',
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8A6A00),
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

// 底部批量操作条
class _DetailBatchBar extends StatelessWidget {
  const _DetailBatchBar({required this.count, required this.onRevert});

  final int count;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: T.surface,
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Text(
              count > 0 ? '将撤销 $count 笔' : '选择要撤销的流水',
              style: const TextStyle(
                fontSize: T.typeBase,
                color: T.textSecondary,
              ),
            ),
            const Spacer(),
            Material(
              color: count > 0 ? T.primary : const Color(0xFFF3EFE7),
              borderRadius: BorderRadius.circular(T.radiusKey),
              child: InkWell(
                borderRadius: BorderRadius.circular(T.radiusKey),
                onTap: count > 0 ? onRevert : null,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  child: Text(
                    '撤销所选',
                    style: TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w700,
                      color: count > 0
                          ? T.textPrimary
                          : const Color(0xFFCCC4B8),
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
