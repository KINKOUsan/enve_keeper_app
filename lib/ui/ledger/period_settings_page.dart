// 预算周期与结转设置页（DESIGN.md §9 v1.1.0 · ADR-0013）。
// 周期类型四选一（每账本独立）；自定义起始日 1–28；切换时按需弹确认预告
// 「立即按新周期结转」并保存；自由周期显示本期起点与「结束本期」；
// 页面落定三条结转铁律文案。选择即保存，无独立保存按钮。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart' as db;
import '../../domain/period_logic.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../copy.dart';
import '../keypad/keypad_flow.dart';

class PeriodSettingsPage extends ConsumerWidget {
  const PeriodSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(activeLedgerProvider);

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: ledger == null
            // 没有激活账本时给一个可返回的空壳（正常流程不会出现）
            ? _EmptyShell(onBack: () => Navigator.of(context).pop())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // ── 页头：返回 + 标题 ──
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        _CircleButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '预算周期与结转',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 提示行：周期属于账本（ADR-0011/0013）
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '对「${ledger.name}」生效；每本账本的预算周期互相独立。',
                      style: const TextStyle(
                        fontSize: T.typeXs,
                        color: Color(0xFFB4AC9F),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── 周期类型四选一 ──
                  _TypeCard(ledger: ledger),
                  // ── 自定义起始日（仅自定义类型显示）──
                  if (periodTypeFromDb(ledger.periodType) ==
                      BudgetPeriodType.customStartDay) ...[
                    const SizedBox(height: 14),
                    _StartDayCard(ledger: ledger),
                  ],
                  // ── 自由周期：本期起点 + 结束本期（仅自由类型显示）──
                  if (periodTypeFromDb(ledger.periodType) ==
                      BudgetPeriodType.free) ...[
                    const SizedBox(height: 14),
                    _FreePeriodCard(ledger: ledger),
                  ],
                  const SizedBox(height: 14),
                  // ── 三条结转铁律说明（ADR-0013 §6）──
                  const _RulesCard(),
                ],
              ),
      ),
    );
  }
}

// ── 共用确认框与保存流程 ────────────────────────

/// 通用确认框（取消 / 确认）；[content] 按 ADR-0013 预告结转后果
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 选择/修改后的统一保存流程：按需确认 → 保存 → 按 repo 实际结果 toast。
/// [previewNow] 用于确认框前的结转预告判定；执行时重取 now（弹窗停留可能跨天，
/// 起点必须以「点击确认那一刻」为准，ADR-0013 §5）。
Future<void> _applyPeriodChange(
  BuildContext context, {
  required WidgetRef ref,
  required String ledgerId,
  required DateTime? storedStart,
  required BudgetPeriodType newType,
  required int? newStartDay,
  required DateTime previewNow,
  required String confirmTitle,
  required String confirmLabel,
  required String changedToast,
  required String unchangedToast,
}) async {
  final repo = ref.read(repoProvider);
  // 预告判定与 repo 执行共用同一纯函数（预告什么就发生什么）
  final needRoll = switchRequiresCarryover(
    newType: newType,
    newStartDay: newStartDay,
    storedStart: storedStart,
    now: previewNow,
  );
  if (needRoll) {
    // 关键步骤：确认框预告（DESIGN.md §9：将立即按新周期结转）
    final ok = await _confirm(
      context,
      title: confirmTitle,
      content: carryoverConfirmBody,
      confirmLabel: confirmLabel,
    );
    if (!ok) return;
  }
  // 执行时重取当前时刻：确认停留跨零点也不会把起点写成昨天
  final rolled = await repo.updateBudgetPeriod(
    ledgerId,
    type: newType,
    startDay: newStartDay,
    now: DateTime.now(),
  );
  if (context.mounted) {
    appToast(context, rolled ? changedToast : unchangedToast);
  }
}

// ── 周期类型四选一卡 ────────────────────────────

/// 白卡：四个类型行单选；选择即按需确认并保存，无独立保存按钮。
/// [_busy] 防快速双击叠两个确认框。
class _TypeCard extends ConsumerStatefulWidget {
  const _TypeCard({required this.ledger});

  final db.Ledger ledger;

  @override
  ConsumerState<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends ConsumerState<_TypeCard> {
  // 防重入标志：确认框/保存进行中忽略再次点击
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final current = periodTypeFromDb(ledger.periodType);
    final currentStartDay = ledger.periodStartDay ?? 1;

    // 类型行数据：类型 / 名称 / 一句话说明 / 图标
    ({BudgetPeriodType type, String name, String desc, IconData icon}) option(
      BudgetPeriodType t,
      String name,
      String desc,
      IconData icon,
    ) => (type: t, name: name, desc: desc, icon: icon);

    final options = [
      option(
        BudgetPeriodType.naturalMonth,
        '自然月',
        '每月 1 号开始新的一期',
        Icons.calendar_month_outlined,
      ),
      option(
        BudgetPeriodType.weekly,
        '每周',
        '每周一开始新的一期',
        Icons.date_range_outlined,
      ),
      option(
        BudgetPeriodType.customStartDay,
        '自定义起始日',
        '每月固定某号开始新的一期',
        Icons.event_available_outlined,
      ),
      option(
        BudgetPeriodType.free,
        '自由周期',
        '不按日历，由你手动结束本期',
        Icons.lock_clock_outlined,
      ),
    ];

    return _Card(
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: T.border),
            _TypeRow(
              data: options[i],
              selected: current == options[i].type,
              currentStartDay: currentStartDay,
              onTap: () => _pick(options[i].type),
            ),
          ],
        ],
      ),
    );
  }

  /// 选择一个周期类型：同类型 no-op；重算起点不变则静默保存；
  /// 起点会变则弹确认框预告「立即按新周期结转」。
  Future<void> _pick(BudgetPeriodType newType) async {
    if (_busy) return;
    final ledger = widget.ledger;
    final current = periodTypeFromDb(ledger.periodType);
    final currentStartDay = ledger.periodStartDay ?? 1;
    final newStartDay = newType == BudgetPeriodType.customStartDay
        ? currentStartDay
        : null;
    // 同类型同起始日：什么都不做
    if (newType == current && newStartDay == currentStartDay) return;
    _busy = true;
    try {
      await _applyPeriodChange(
        context,
        ref: ref,
        ledgerId: ledger.id,
        storedStart: tryParseIsoDate(ledger.lastPeriodStart),
        newType: newType,
        newStartDay: newStartDay,
        previewNow: DateTime.now(),
        confirmTitle: '切换预算周期？',
        confirmLabel: '切换',
        changedToast: '已切换，本期已按新周期结转',
        unchangedToast: '已切换',
      );
    } finally {
      _busy = false;
    }
  }
}

/// 一个类型选项行：32dp 图标块 + 名称/说明 + 选中标记
class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.data,
    required this.selected,
    required this.currentStartDay,
    required this.onTap,
  });

  final ({BudgetPeriodType type, String name, String desc, IconData icon}) data;
  final bool selected;

  // 当前已存的起始日（自定义类型的说明里带上具体号数）
  final int currentStartDay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 自定义类型的说明带上当前号数，让「每月 X 号」可见
    final desc = data.type == BudgetPeriodType.customStartDay
        ? '每月 $currentStartDay 号开始新的一期'
        : data.desc;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            // 32dp 图标块：选中用暖黄底（与账本管理页的激活样式一致）
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? T.primarySoft : T.surfaceSubtle,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(data.icon, size: 16, color: const Color(0xFF6E675C)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.name,
                    style: const TextStyle(
                      fontSize: T.typeBase,
                      fontWeight: FontWeight.w500,
                      color: T.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: T.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // 选中标记：实心对勾
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: T.primaryDeep,
              ),
          ],
        ),
      ),
    );
  }
}

// ── 自定义起始日卡（1–28）────────────────────────

/// 白卡：7 列 × 4 行的号数网格；点号数即按「修改起始日」流程确认并保存。
/// [_busy] 防快速双击叠两个确认框。
class _StartDayCard extends ConsumerStatefulWidget {
  const _StartDayCard({required this.ledger});

  final db.Ledger ledger;

  @override
  ConsumerState<_StartDayCard> createState() => _StartDayCardState();
}

class _StartDayCardState extends ConsumerState<_StartDayCard> {
  // 防重入标志：确认框/保存进行中忽略再次点击
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final current = widget.ledger.periodStartDay ?? 1;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每月起始日（1–28 号）',
              style: TextStyle(
                fontSize: T.typeBase,
                fontWeight: FontWeight.w500,
                color: T.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '1–28 每个月都有，不会出现「2 月 30 日」这类对不齐的日子。',
              style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
            ),
            const SizedBox(height: 10),
            // 7 列网格：28 个号数块
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var day = 1; day <= 28; day++)
                  _DayCell(
                    day: day,
                    selected: day == current,
                    onTap: day == current ? null : () => _pickDay(day),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 修改起始日：重算起点不变 → 静默保存；变了 → 确认框预告结转
  Future<void> _pickDay(int day) async {
    if (_busy) return;
    final ledger = widget.ledger;
    _busy = true;
    try {
      await _applyPeriodChange(
        context,
        ref: ref,
        ledgerId: ledger.id,
        storedStart: tryParseIsoDate(ledger.lastPeriodStart),
        newType: BudgetPeriodType.customStartDay,
        newStartDay: day,
        previewNow: DateTime.now(),
        confirmTitle: '改为每月 $day 号？',
        confirmLabel: '切换',
        changedToast: '已切换，本期已按新周期结转',
        unchangedToast: '已改为每月 $day 号',
      );
    } finally {
      _busy = false;
    }
  }
}

/// 一个号数块：圆角方块，选中暖黄实底
class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, this.onTap});

  final int day;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? T.primary : T.surfaceSubtle,
      borderRadius: BorderRadius.circular(T.radiusKey),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.radiusKey),
        onTap: onTap,
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: T.typeSm,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? T.textPrimary : T.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── 自由周期卡（本期起点 + 结束本期）──────────────

/// 白卡：显示当前期起点 + 「结束本期」按钮（唯一手动结转入口，ADR-0013 §5）。
/// [_busy] 防快速双击叠两个确认框。
class _FreePeriodCard extends ConsumerStatefulWidget {
  const _FreePeriodCard({required this.ledger});

  final db.Ledger ledger;

  @override
  ConsumerState<_FreePeriodCard> createState() => _FreePeriodCardState();
}

class _FreePeriodCardState extends ConsumerState<_FreePeriodCard> {
  // 防重入标志：确认框/保存进行中忽略再次点击
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final start =
        tryParseIsoDate(widget.ledger.lastPeriodStart) ??
        dateOnly(DateTime.now());
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '本期起点',
                  style: TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w500,
                    color: T.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${start.month}月${start.day}日',
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w500,
                    color: T.primaryDeep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '不按日历：什么时候结账由你决定，App 不会自动替你结转。',
              style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
            ),
            const SizedBox(height: 10),
            // 「结束本期」：暖黄描边按钮（DESIGN.md §13 的追加动作样式）
            SizedBox(
              height: 48,
              child: Material(
                color: const Color(0xFFFFF3D1),
                // StadiumBorder 自带全圆角，不能再同时给 borderRadius（断言冲突）
                shape: StadiumBorder(
                  side: BorderSide(color: const Color(0xFFFFE49B), width: 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(T.radiusKey),
                  onTap: _closePeriod,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_rounded, size: 18, color: T.primaryDeep),
                      SizedBox(width: 6),
                      Text(
                        '结束本期',
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
          ],
        ),
      ),
    );
  }

  /// 结束本期：二次确认 → 结转 → 新一期从今天开始；重复点击不重复结转
  ///（repo 层守卫：本期起点已是今天就直接拒绝）。
  Future<void> _closePeriod() async {
    if (_busy) return;
    _busy = true;
    try {
      final ok = await _confirm(
        context,
        title: '结束本期？',
        content: closePeriodConfirmBody,
        confirmLabel: '结束',
      );
      if (!ok) return;
      final repo = ref.read(repoProvider);
      // 关键步骤：起点 = 点击确认当日（重取 now，弹窗停留跨零点也不写错）
      final rolled = await repo.closeFreePeriod(
        widget.ledger.id,
        DateTime.now(),
      );
      if (mounted) {
        appToast(context, rolled ? '已结束本期，新一期从今天开始' : '本期已从今天开始');
      }
    } finally {
      _busy = false;
    }
  }
}

// ── 结转铁律说明卡 ────────────────────────────

/// 白卡：三条结转铁律（ADR-0013 §6）逐条落定文案
class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    // 一条铁律：序号徽标 + 说明
    Widget rule(String no, String text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 序号徽标
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: T.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                no,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: T.primaryDeep,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: T.typeSm,
                  height: 1.5,
                  color: T.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '结转的三条铁律',
              style: TextStyle(
                fontSize: T.typeBase,
                fontWeight: FontWeight.w500,
                color: T.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            rule('1', '正结余：看信封自己的结转开关——开了带入下期，关了退回待规划。'),
            rule('2', '负缺口：无论开关都带入下期，透支欠账不会凭空消失。'),
            rule('3', '待规划原样带入下期；每期的「已使用」一律归零。'),
          ],
        ),
      ),
    );
  }
}

// ── 复用小组件 ────────────────────────────────

/// 白卡圆角 18 + 投影（与分组卡一致）
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
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
      child: child,
    );
  }
}

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

/// 无激活账本的空壳（兜底，正常流程不会出现）
class _EmptyShell extends StatelessWidget {
  const _EmptyShell({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
                const SizedBox(width: 10),
                const Text(
                  '预算周期与结转',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Center(
            child: Text(
              '没有正在使用的账本',
              style: TextStyle(fontSize: T.typeBase, color: T.textTertiary),
            ),
          ),
        ),
      ],
    );
  }
}
