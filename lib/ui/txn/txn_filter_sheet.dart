// 流水筛选与排序的共享 UI — 流水页 / 信封详情页同款（票 05）。
// 纯逻辑在 domain/txn_filter.dart；这里只有面板、条件条与按钮三类组件。
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/txn_filter.dart';
import '../../theme/tokens.dart';

// ── 文案小工具 ───────────────────────────────────

// 中文短日期：9月17日
String _cnDate(DateTime d) => '${d.month}月${d.day}日';

// 类型条件的条件条/面板文案
const _typeLabels = {
  TxType.expense: '支出',
  TxType.income: '收入',
  TxType.transfer: '转移',
};

// 面板类型行的可选胶囊（v1.2.0 票 04）：只留支出/收入——
// 转移的显隐改由流水页顶部「显示转移项」开关控制，不再作为类型筛选项
const _typeChoices = [TxType.expense, TxType.income];

// 日期条件的条件条文案：单日 → 「9月15日」；区间 → 「9月1日 – 9月9日」
String dateConditionLabel(TxnFilter f) {
  if (f.day != null) return _cnDate(f.day!);
  if (f.rangeStart != null) {
    final end = f.rangeEnd ?? f.rangeStart!;
    return '${_cnDate(f.rangeStart!)} – ${_cnDate(end)}';
  }
  return '';
}

// ── 底部筛选面板 ────────────────────────────────

/// 打开筛选面板。返回应用后的筛选条件（确定 → 面板草稿；清除筛选 → 全空；
/// 下拉关闭 → 原条件不变）。
Future<TxnFilter> showTxnFilterSheet(BuildContext context, TxnFilter current) {
  return showModalBottomSheet<TxnFilter>(
    context: context,
    backgroundColor: T.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(T.radiusSheet)),
    ),
    isScrollControlled: true,
    builder: (_) => _FilterSheet(initial: current),
  ).then((r) => r ?? current);
}

/// 面板主体：类型胶囊 + 日期（不限/单日/区间）+ 清除/确定。编辑在草稿上进行，
/// 只有点「确定」才生效，避免半遮罩状态下列表一直闪。
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final TxnFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

/// 面板 State 类：持有面板内的草稿条件，编辑只在草稿上进行，确定才交回
class _FilterSheetState extends State<_FilterSheet> {
  // 面板内的草稿条件
  TxnFilter _draft = const TxnFilter();

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  // 弹单日日历（已选日期作为初始值）
  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.day ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    // pop 竞态防护：跨 async 后先查 mounted 再 setState
    if (picked == null || !mounted) return;
    setState(() => _draft = _draft.withDay(picked));
  }

  // 弹区间日历（已选区间作为初始值）
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _draft.rangeStart == null
          ? null
          : DateTimeRange(
              start: _draft.rangeStart!,
              end: _draft.rangeEnd ?? _draft.rangeStart!,
            ),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      currentDate: now,
    );
    // pop 竞态防护：跨 async 后先查 mounted 再 setState
    if (picked == null || !mounted) return;
    setState(() => _draft = _draft.withRange(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    // 日期模式由草稿推导：单日 / 区间 / 不限
    final dateMode = _draft.day != null
        ? 1
        : _draft.rangeStart != null
        ? 2
        : 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行
            Row(
              children: [
                const Text(
                  '筛选',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 20, color: T.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 类型行
            const Text(
              '类型',
              style: TextStyle(fontSize: T.typeSm, color: T.textTertiary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in _typeChoices)
                  _chip(
                    label: _typeLabels[type]!,
                    selected: _draft.type == type,
                    onTap: () => setState(
                      // 再点一次已选类型 = 回到「全部」
                      () => _draft = _draft.withType(
                        _draft.type == type ? null : type,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // 日期行
            const Text(
              '日期',
              style: TextStyle(fontSize: T.typeSm, color: T.textTertiary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  label: '不限',
                  selected: dateMode == 0,
                  onTap: () => setState(
                    () => _draft = _draft.withoutDay().withoutRange(),
                  ),
                ),
                _chip(
                  label: '单日',
                  selected: dateMode == 1,
                  onTap: () {
                    if (dateMode == 1) return; // 已是单日：点值重选
                    _pickDay();
                  },
                ),
                _chip(
                  label: '区间',
                  selected: dateMode == 2,
                  onTap: () {
                    if (dateMode == 2) return;
                    _pickRange();
                  },
                ),
                // 已选日期值胶囊：点击重新选择
                if (dateMode == 1)
                  _chip(
                    label: dateConditionLabel(_draft),
                    selected: true,
                    onTap: _pickDay,
                  ),
                if (dateMode == 2)
                  _chip(
                    label: dateConditionLabel(_draft),
                    selected: true,
                    onTap: _pickRange,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            // 底部操作：清除筛选 + 确定
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _draft.isActive
                        ? () => Navigator.pop(context, const TxnFilter())
                        : null,
                    style: TextButton.styleFrom(
                      backgroundColor: T.surfaceSubtle,
                      foregroundColor: T.textSecondary,
                      disabledForegroundColor: const Color(0xFFCCC4B8),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(T.radiusKey),
                      ),
                    ),
                    child: const Text(
                      '清除筛选',
                      style: TextStyle(
                        fontSize: T.typeBase,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, _draft),
                    style: TextButton.styleFrom(
                      backgroundColor: T.primary,
                      foregroundColor: T.textPrimary,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(T.radiusKey),
                      ),
                    ),
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: T.typeBase,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 胶囊选项：选中黄底暖黑字，未选中浅底（与旧筛选条同视觉）。
  // 注意：不能给 Container 设 alignment——Wrap 有界宽松约束下会撑满整行，
  // 用内层 Center 定高居中，宽度由内容 + 内边距决定。
  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? T.primary : T.surfaceSubtle,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: T.typeBase,
              fontWeight: FontWeight.w500,
              color: selected ? T.textPrimary : const Color(0xFF6E675C),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 页头按钮（排序切换 / 筛选入口）──────────────

/// 排序切换胶囊：新→旧 ⇄ 旧→新，点按切换
class TxnSortButton extends StatelessWidget {
  const TxnSortButton({super.key, required this.sort, required this.onToggle});

  // 当前排序方向
  final TxnSort sort;

  // 点按回调（由页面切换方向并刷新）
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: T.surfaceSubtle,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onToggle,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                sort == TxnSort.newest
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 13,
                color: T.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                sort == TxnSort.newest ? '新→旧' : '旧→新',
                style: const TextStyle(
                  fontSize: T.typeSm,
                  fontWeight: FontWeight.w500,
                  color: T.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选按钮：36dp 圆形调音图标；有激活条件时黄底并带小圆点标记
class TxnFilterButton extends StatelessWidget {
  const TxnFilterButton({super.key, required this.active, required this.onTap});

  // 是否有激活的筛选条件（决定按钮底色与小圆点）
  final bool active;

  // 点按回调（由页面打开筛选面板）
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: active ? T.primary : T.surfaceSubtle,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.tune,
                size: 16,
                color: active ? T.textPrimary : T.textSecondary,
              ),
              if (active)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: T.overspend,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 条件条 ─────────────────────────────────────

/// 筛选激活时列表顶部的条件条：类型/日期逐项可移除，全部移除恢复全量。
/// 某条件为空时对应胶囊不出现。
class TxnConditionBar extends StatelessWidget {
  const TxnConditionBar({
    super.key,
    required this.filter,
    required this.onRemoveType,
    required this.onRemoveDay,
    required this.onRemoveRange,
  });

  // 当前筛选条件（决定显示哪些条件胶囊）
  final TxnFilter filter;

  // 三个逐项移除回调：移除类型 / 移除单日 / 移除区间
  final VoidCallback onRemoveType;
  final VoidCallback onRemoveDay;
  final VoidCallback onRemoveRange;

  @override
  Widget build(BuildContext context) {
    final showType = filter.type != null;
    final showDay = filter.day != null;
    final showRange = filter.rangeStart != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 30,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            if (showType)
              _condChip(
                label: _typeLabels[filter.type!]!,
                onRemove: onRemoveType,
              ),
            if (showDay)
              _condChip(
                label: dateConditionLabel(filter),
                onRemove: onRemoveDay,
              ),
            if (showRange)
              _condChip(
                label: dateConditionLabel(filter),
                onRemove: onRemoveRange,
              ),
          ],
        ),
      ),
    );
  }

  // 单个可移除的条件胶囊：浅底描边 + 文案 + x
  Widget _condChip({required String label, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: T.primarySoft,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: T.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: T.typeSm,
                fontWeight: FontWeight.w500,
                color: T.textPrimary,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close, size: 13, color: T.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
