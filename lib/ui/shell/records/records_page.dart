// 流水页 — 页头（本月收支小计）+ 筛选/排序 + 按日分组的交易列表（DESIGN.md §7 + 票 04/05）。
// 核心不变量③的界面表达：转移行灰色弱化、不带正负号、**不算进日小计与月小计**；
// 转移默认隐藏（显示转移项开关持久化，票 04），聚焦收入与支出。
// 筛选与排序的纯逻辑在 domain/txn_filter.dart，面板/条件条/按钮与信封详情页共用。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../domain/txn_filter.dart';
import '../../../state/providers.dart';
import '../../../theme/envelope_icons.dart';
import '../../../theme/tokens.dart';
import '../../common/app_route.dart';
import '../../common/format.dart';
import '../../copy.dart';
import '../../overspend/fix_overspend_flow.dart';
import '../../txn/txn_batch.dart';
import '../../txn/txn_detail_page.dart';
import '../../txn/txn_filter_sheet.dart';

// ── 多选工具组件（与信封详情页共用样式）──────────

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

// 多选模式顶栏：已选 N + 全选 + 取消
class _SelectBar extends StatelessWidget {
  const _SelectBar({
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
        height: 46,
        child: Row(
          children: [
            // 退出多选
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
            // 全选 / 全不选
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

// 底部批量操作条：撤销所选
class _BatchBar extends StatelessWidget {
  const _BatchBar({required this.count, required this.onRevert});

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
            // 撤销按钮：黄底，未选时置灰
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

class RecordsPage extends ConsumerStatefulWidget {
  const RecordsPage({super.key});

  @override
  ConsumerState<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends ConsumerState<RecordsPage> {
  // 当前筛选条件（默认无任何条件 = 全量）
  TxnFilter _filter = const TxnFilter();

  // 排序方向（默认新→旧）
  TxnSort _sort = TxnSort.newest;

  // 多选状态（长按进入，ADR-0012 批量撤销）
  final _sel = TxnSelection();

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

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(txnsProvider).value ?? const <Txn>[];
    // 流水解析信封名用全部信封（含停用，ADR-0012）
    final envelopes =
        ref.watch(allEnvelopesProvider).value ?? const <Envelope>[];
    final envById = {for (final e in envelopes) e.id: e};
    // 当前账本货币符号（ADR-0017）：页头小计、日小计与流水行共用
    final symbol = ref.watch(currencySymbolProvider);

    // 本月小计（排除转移，不变量③）
    final now = DateTime.now();
    final monthTxns = txns
        .where((t) => t.at.year == now.year && t.at.month == now.month)
        .toList();
    final monthIncome = _sum(monthTxns, (t) => t.type == TxType.income);
    final monthExpense = _sum(monthTxns, (t) => t.type == TxType.expense);

    // 转移显隐（v1.2.0 票 04）：持久化开关叠到筛选条件上，
    // 隐藏时转移（含结转退回）不进列表——聚焦收支
    final showTransfers = ref.watch(showTransfersProvider);
    final effective = _filter.withShowTransfers(showTransfers);

    // 筛选 + 排序 + 按日分组（LinkedHashMap 按插入序，分组方向随排序）
    final filtered = sortTxns(txns.where(effective.match).toList(), _sort);
    // 多选池排除结转退回（ADR-0016：系统行为不可撤销，不许进批量撤销）
    final selectable = filtered.where((t) => t.type != TxType.refund).toList();
    final groups = <String, List<Txn>>{};
    for (final t in filtered) {
      final key =
          '${t.at.year}-${t.at.month.toString().padLeft(2, '0')}-${t.at.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(t);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 顶栏：多选工具栏替换常规页头 ──
            if (_sel.mode)
              _SelectBar(
                count: _sel.count,
                totalCount: selectable.length,
                onSelectAll: () => _sel.toggleAll(selectable),
                onExit: _sel.exit,
              )
            else ...[
              _Header(
                month: now.month,
                income: monthIncome,
                expense: monthExpense,
                symbol: symbol,
                sort: _sort,
                filterActive: _filter.isActive,
                onToggleSort: _toggleSort,
                onOpenFilter: _openFilter,
              ),
              const SizedBox(height: 14),
              // ── 待腾挪提示条（DESIGN.md §10）：有透支才出现，补完即消失 ──
              _FixHint(onFix: () => runFixOverspendFlow(context, ref)),
            ],
            // ── 条件条：筛选激活时逐项可移除（多选模式下也显示，提示当前可见范围）──
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
            // ── 转移显隐开关（票 04）：常驻于常规浏览态；多选模式下不显示，
            //    避免选中池在批量操作中途变化 ──
            if (!_sel.mode)
              _TransfersToggle(
                checked: showTransfers,
                onToggle: () => ref
                    .read(showTransfersProvider.notifier)
                    .set(!showTransfers),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? (txns.isEmpty ? _EmptyState() : _FilterEmptyState())
                  : ListView.builder(
                      // 底部留出操作条空间
                      padding: EdgeInsets.fromLTRB(
                        16,
                        6,
                        16,
                        _sel.mode ? 88 : 16,
                      ),
                      itemCount: groups.length,
                      itemBuilder: (context, i) {
                        final key = groups.keys.elementAt(i);
                        final list = groups[key]!;
                        return _DayGroup(
                          date: list.first.at,
                          now: now,
                          txns: list,
                          envById: envById,
                          symbol: symbol,
                          selection: _sel,
                          onTapTxn: _showTxnDetail,
                        );
                      },
                    ),
            ),
            // ── 底部操作条：批量撤销（只作用于筛选后可见的多选池）──
            if (_sel.mode)
              _BatchBar(
                count: _sel.count,
                onRevert: () => _revertSelected(selectable),
              ),
          ],
        ),
      ),
    );
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

  // 批量撤销所选（整批预检 + 二次确认，规则与未筛选时一致，不变量⑦）
  Future<void> _revertSelected(List<Txn> pool) async {
    final picked = _sel.pick(pool);
    if (picked.isEmpty) return;
    final ok = await confirmBatchRevert(context, ref, picked);
    if (!ok || !mounted) return;
    await executeBatchRevert(context, ref, picked);
    _sel.exit();
  }

  // 按谓词累加金额
  double _sum(List<Txn> txns, bool Function(Txn) predicate) =>
      txns.where(predicate).fold(0.0, (acc, t) => round2(acc + t.amount));

  // 进入交易详情
  void _showTxnDetail(Txn t) {
    Navigator.of(context)
        .push(AppPageRoute<void>(builder: (_) => TxnDetailPage(txn: t)));
  }
}

// ── 页头 ─────────────────────────────────────

/// 左「流水」+ 副行（本月 · 收入 · 支出，排除转移）；
/// 右排序切换胶囊（新→旧 ⇄ 旧→新）+ 36dp 筛选按钮（票 05）
class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.income,
    required this.expense,
    required this.symbol,
    required this.sort,
    required this.filterActive,
    required this.onToggleSort,
    required this.onOpenFilter,
  });

  final int month;
  final double income;
  final double expense;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  final TxnSort sort;
  final bool filterActive;
  final VoidCallback onToggleSort;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '流水',
                  style: TextStyle(
                    fontSize: 20,
                    height: 24 / 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$month月 · 收入 $symbol${money(income)} · 支出 $symbol${money(expense)}',
                  style: const TextStyle(
                    fontSize: T.typeXs,
                    height: 15 / 11,
                    color: T.textTertiary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            TxnSortButton(sort: sort, onToggle: onToggleSort),
            const SizedBox(width: 8),
            TxnFilterButton(active: filterActive, onTap: onOpenFilter),
          ],
        ),
      ),
    );
  }
}

// ── 待腾挪提示条 ────────────────────────────────

/// 高 56、圆角 16、红浅底描边；左警示图标 + 中文案 + 右「去补上」胶囊。
/// 单个透支：「「医疗」还缺 ¥120」；多个：「3 个信封还缺 ¥340」。
class _FixHint extends ConsumerWidget {
  const _FixHint({required this.onFix});

  final VoidCallback onFix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopes = ref.watch(envelopesProvider).value ?? const [];
    final overs = overspendingEnvelopes(envelopes);
    if (overs.isEmpty) return const SizedBox.shrink();

    // 当前账本货币符号（ADR-0017）
    final symbol = ref.watch(currencySymbolProvider);
    final total = totalShortfall(overs);
    final text = overs.length == 1
        ? overspendBannerSingle(overs.first.name, total, symbol: symbol)
        : overspendBannerMulti(overs.length, total, symbol: symbol);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          // DangerTint：#FDECEC 底 + #F6C9CB 描边
          color: DangerTint.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DangerTint.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: T.overspend,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w500,
                  color: DangerTint.text,
                ),
              ),
            ),
            // 30dp 高的黄色胶囊「去补上」
            Material(
              color: T.primary,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: onFix,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: const Text(
                    '去补上',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: T.textPrimary,
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

// ── 按日分组 ─────────────────────────────────────

/// 一天的组：日期行（左标签 + 右小计）+ 若干交易行（组内行距 2）。
/// 多选模式下点日期行 = 整组切换（按日区间选择，ADR-0012）。
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.date,
    required this.now,
    required this.txns,
    required this.envById,
    required this.symbol,
    required this.selection,
    required this.onTapTxn,
  });

  final DateTime date;
  final DateTime now;
  final List<Txn> txns;
  final Map<String, Envelope> envById;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  final TxnSelection selection;
  final ValueChanged<Txn> onTapTxn;

  @override
  Widget build(BuildContext context) {
    // 关键步骤：日小计只累加收入与支出，转移与结转退回排除（不变量③，零和）
    var net = 0.0;
    var hasSubtotal = false;
    for (final t in txns) {
      if (t.type == TxType.transfer || t.type == TxType.refund) continue;
      hasSubtotal = true;
      net = round2(net + (t.type == TxType.income ? t.amount : -t.amount));
    }

    // 组选择只覆盖可撤销的行（结转退回是系统行为，不进多选，ADR-0016）
    final selectable = txns.where((t) => t.type != TxType.refund).toList();
    final groupSelected =
        selectable.isNotEmpty &&
        selectable.every((t) => selection.ids.contains(t.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 日期行（多选模式下可点选整组）
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: selection.mode && selectable.isNotEmpty
                ? () => selection.toggleGroup(selectable)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (selection.mode) ...[
                    _CheckCircle(checked: groupSelected),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    dayLabel(date, now),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8A8378),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    // 全是转移 → 小计显示「—」
                    hasSubtotal
                        ? (net < 0
                              ? '−$symbol${money(-net)}'
                              : '+$symbol${money(net)}')
                        : '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: hasSubtotal
                          ? T.textPrimary
                          : const Color(0xFFB4AC9F),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 交易行，组内行距 2
          for (var i = 0; i < txns.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            _TxnRow(
              txn: txns[i],
              envById: envById,
              symbol: symbol,
              selection: selection,
              onTap: () => selection.mode
                  ? _toggleIfSelectable(txns[i])
                  : onTapTxn(txns[i]),
            ),
          ],
        ],
      ),
    );
  }

  // 多选模式下点行：结转退回不可选中（ADR-0016），其余正常切换
  void _toggleIfSelectable(Txn t) {
    if (t.type != TxType.refund) selection.toggle(t.id);
  }
}

// ── 交易行 ─────────────────────────────────────

/// 高 54：36dp 图标块 + 名称/副行 + 右对齐金额。
/// 金额语义色是唯一区分三种动作的地方（DESIGN.md §7 表格）。
/// 长按进入多选；多选模式下点行切换选中。
class _TxnRow extends StatelessWidget {
  const _TxnRow({
    required this.txn,
    required this.envById,
    required this.symbol,
    required this.selection,
    required this.onTap,
  });

  final Txn txn;
  final Map<String, Envelope> envById;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  final TxnSelection selection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = txn;
    final selected = selection.ids.contains(t.id);

    // 金额语义：支出红带负号 / 收入绿带加号 / 转移与结转退回灰不带符号
    final String amountText;
    final Color amountColor;
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

    // 副行文案
    final String subtitle;
    switch (t.type) {
      case TxType.expense:
        subtitle =
            '${envById[t.envelopeId]?.name ?? '未知'} · ${clockLabel(t.at)}';
      case TxType.income:
        subtitle = '收入';
      case TxType.transfer:
        subtitle = '转移';
      case TxType.refund:
        subtitle = '结转退回';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      // 长按进入多选模式（点第一下即选中该行）；
      // 结转退回是系统行为不可撤销（ADR-0016），长按与点选都不把它带进多选
      onLongPress: t.type == TxType.refund ? null : () => selection.enter(t.id),
      child: Container(
        height: 54,
        // 选中态：暖黄浅底描边
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selection.mode && selected
              ? T.primarySoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selection.mode && selected
              ? Border.all(color: T.primary)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            // 多选模式：行首勾选圈替换图标块
            if (selection.mode)
              _CheckCircle(checked: selected)
            else
              _IconBlock(txn: t, envById: envById),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    t.description,
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
                    subtitle,
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: Color(0xFF8A8378),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountText,
              style: TextStyle(
                fontSize: T.typeBase,
                fontWeight: FontWeight.w600,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 36dp 圆角图标块：支出 = 信封浅底描边图标；收入 = 暖黄底琥珀邮件；
/// 转移 = 来源侧的颜色（分配用暖黄，其余用来源信封色）。
class _IconBlock extends StatelessWidget {
  const _IconBlock({required this.txn, required this.envById});

  final Txn txn;
  final Map<String, Envelope> envById;

  @override
  Widget build(BuildContext context) {
    // 选底色与图标
    Color bg;
    Color iconColor;
    IconData icon;

    switch (txn.type) {
      case TxType.income:
        bg = T.primarySoft;
        iconColor = const Color(0xFFB08A00);
        icon = Icons.mail_outline_rounded;
      case TxType.expense:
        final e = envById[txn.envelopeId];
        final c = envelopeColorById(e?.color ?? 'clay');
        bg = c.tint;
        iconColor = c.main;
        icon = envelopeIconById(e?.icon ?? 'food');
      case TxType.transfer:
        // 来源侧：撤销分配/分配用暖黄，信封间转移用来源信封色
        final fromEnv = txn.fromId == kToBudget ? null : envById[txn.fromId];
        if (fromEnv == null) {
          bg = T.primarySoft;
          iconColor = const Color(0xFFB08A00);
        } else {
          final c = envelopeColorById(fromEnv.color);
          bg = c.tint;
          iconColor = c.main;
        }
        icon = Icons.swap_horiz_rounded;
      case TxType.refund:
        // 结转退回：来源信封色 + 退回箭头（与转移同族但图标可辨）
        final fromEnv = envById[txn.fromId];
        if (fromEnv == null) {
          bg = T.primarySoft;
          iconColor = const Color(0xFFB08A00);
        } else {
          final c = envelopeColorById(fromEnv.color);
          bg = c.tint;
          iconColor = c.main;
        }
        icon = Icons.reply_rounded;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: iconColor),
    );
  }
}

// ── 空状态 ─────────────────────────────────────

/// 没有任何流水时的兜底（与首页空态同一视觉语言）
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: T.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 32,
              color: Color(0xFFC9A63C),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            emptyTxnsTitle,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            emptyTxnsBody,
            style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 有流水但筛选无结果（票 05）：提示放宽条件
class _FilterEmptyState extends StatelessWidget {
  const _FilterEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: T.surfaceSubtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.filter_alt_off_outlined,
              size: 30,
              color: T.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            emptyFilteredTitle,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            emptyFilteredBody,
            style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── 转移显隐开关 ────────────────────────────────

/// 「显示转移项」开关行（票 04）：勾选圈 + 标签，整行可点。
/// 状态持久化在 showTransfersProvider；转移默认隐藏以聚焦收支。
class _TransfersToggle extends StatelessWidget {
  const _TransfersToggle({required this.checked, required this.onToggle});

  // 当前是否显示转移
  final bool checked;

  // 点按回调（由页面切换 provider 状态）
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggle,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              _CheckCircle(checked: checked),
              const SizedBox(width: 8),
              const Text(
                '显示转移项',
                style: TextStyle(fontSize: 13, color: T.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
