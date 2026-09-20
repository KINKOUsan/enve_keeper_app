// 我的页 — 用户卡 + 月度概览条 + 分组卡（DESIGN.md §9）。
// 账本管理入口在「预算」组首行（ADR-0011：账本入口在「我的」页）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart' show kDefaultCurrency;
import '../../../domain/period_logic.dart';
import '../../../state/profile.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../common/app_route.dart';
import '../../common/format.dart';
import '../../copy.dart';
import '../../ledger/ledger_manage_page.dart';
import '../../ledger/period_settings_page.dart';
import 'backup_restore_page.dart';
import 'csv_export.dart';
import 'about_page.dart';
import 'profile_edit_page.dart';
import 'usage_guide_page.dart';
import '../envelope/envelope_manage_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopes = ref.watch(envelopesProvider).value ?? const [];
    final toBudget = ref.watch(settingsProvider).value?.toBudget ?? 0;
    // 当前账本货币符号（ADR-0017）：概览条与设置行右侧值共用
    final currency = ref.watch(currencySymbolProvider);
    final activeLedger = ref.watch(activeLedgerProvider);
    final now = DateTime.now();
    // 月度概览条前缀随周期类型（DESIGN.md §9 v1.1.0）；无账本时按自然月兜底
    final overviewPrefix = periodOverviewLabel(
      type: activeLedger == null
          ? BudgetPeriodType.naturalMonth
          : periodTypeFromDb(activeLedger.periodType),
      startDay: activeLedger?.periodStartDay,
      storedStart: activeLedger == null
          ? null
          : tryParseIsoDate(activeLedger.lastPeriodStart),
      now: now,
    );
    // 「预算周期与结转」行的右侧值随周期类型
    final periodValue = activeLedger == null
        ? null
        : periodTypeShortLabel(
            periodTypeFromDb(activeLedger.periodType),
            activeLedger.periodStartDay,
          );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _UserCard(),
            const SizedBox(height: 14),
            _MonthBar(
              prefix: overviewPrefix,
              toBudget: toBudget,
              symbol: currency,
            ),
            const SizedBox(height: 14),
            // ── 预算组 ──
            _GroupCard(
              title: '预算',
              rows: [
                _RowData(
                  icon: Icons.auto_awesome_motion_outlined,
                  label: '账本管理',
                  value: activeLedger?.name ?? '-',
                  onTap: () => _openLedgers(context),
                ),
                _RowData(
                  icon: Icons.mail_outline_rounded,
                  label: '信封管理',
                  value: '${envelopes.length} 个',
                  onTap: () => _openEnvelopes(context),
                ),
                _RowData(
                  icon: Icons.school_outlined,
                  label: '重看手势引导',
                  onTap: () =>
                      ref.read(coachReplayRequestProvider.notifier).request(),
                ),
                _RowData(
                  icon: Icons.event_repeat_outlined,
                  label: '预算周期与结转',
                  value: periodValue,
                  onTap: () => _openPeriodSettings(context),
                ),
                _RowData(
                  icon: Icons.payments_outlined,
                  label: '货币符号',
                  value: currency,
                  onTap: () => _editCurrency(context, ref),
                ),
                _RowData(
                  icon: Icons.visibility_off_outlined,
                  label: '隐藏待规划金额',
                  // 首页金额隐私（v1.2.0 票 03）：开关就地生效，整行可点
                  trailing: Switch(
                    value: ref.watch(hideToBudgetProvider),
                    onChanged: (hide) =>
                        ref.read(hideToBudgetProvider.notifier).set(hide),
                  ),
                  onTap: () => ref
                      .read(hideToBudgetProvider.notifier)
                      .set(!ref.read(hideToBudgetProvider)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 数据组 ──
            _GroupCard(
              title: '数据',
              rows: [
                _RowData(
                  icon: Icons.backup_outlined,
                  label: '备份与恢复',
                  onTap: () => _openBackup(context),
                ),
                _RowData(
                  icon: Icons.ios_share_outlined,
                  label: '导出 CSV',
                  onTap: () => exportCsv(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 关于组 ──
            _GroupCard(
              title: '关于',
              rows: [
                _RowData(
                  icon: Icons.menu_book_outlined,
                  label: '使用说明',
                  onTap: () => _openUsageGuide(context),
                ),
                _RowData(
                  icon: Icons.info_outline,
                  label: '关于金打细算',
                  // 版本号与关于页同源（packageInfoProvider），读取中暂不显示
                  value: _versionLabel(ref),
                  onTap: () => _openAbout(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 进入账本管理页
  void _openLedgers(BuildContext context) {
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => const LedgerManagePage()));
  }

  // 进入预算周期设置页（v1.1.0）
  void _openPeriodSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => const PeriodSettingsPage()));
  }

  // 编辑货币符号（v1.2.0 票 02 / ADR-0017）：对话框确认后写入当前账本设置行。
  // 跨 async 前先取好 messenger（陷阱清单：pop 之后旧 context 失效）。
  Future<void> _editCurrency(BuildContext context, WidgetRef ref) async {
    final ledger = ref.read(activeLedgerProvider);
    if (ledger == null) return;
    final current = ref.read(currencySymbolProvider);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CurrencyDialog(current: current, ledgerName: ledger.name),
    );
    if (picked == null || picked == current || !context.mounted) return;
    await ref.read(repoProvider).updateCurrency(ledger.id, picked);
    messenger.showSnackBar(
      SnackBar(
        content: Text(currencySavedToast),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  // 进入信封管理页
  void _openEnvelopes(BuildContext context) {
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => const EnvelopeManagePage()));
  }

  // 进入备份与恢复页
  void _openBackup(BuildContext context) {
    Navigator.of(
      context,
    ).push(AppPageRoute<bool>(builder: (_) => const BackupRestorePage()));
  }

  // 版本行文案：包版本读出后显示 v x.y.z（与关于页同源，票 07）
  String? _versionLabel(WidgetRef ref) {
    final v = ref.watch(packageInfoProvider).value?.version;
    return v == null || v.isEmpty ? null : 'v$v';
  }

  // 进入关于页（票 07：反馈/许可收进关于页）
  void _openAbout(BuildContext context) {
    Navigator.of(context)
        .push(AppPageRoute<void>(builder: (_) => const AboutPage()));
  }

  // 进入使用说明页（v1.2.x 票 04：README「使用说明」节的 App 内重排）
  void _openUsageGuide(BuildContext context) {
    Navigator.of(context)
        .push(AppPageRoute<void>(builder: (_) => const UsageGuidePage()));
  }
}

// ── 用户卡 ─────────────────────────────────────

/// 白卡圆角 20：44dp 头像 + 昵称 + 签名 + 右箭头；点按进编辑资料页（profile-polish 票）。
/// 资料为装饰性本地数据：昵称/签名留空回退默认文案，头像留空/读取失败回退默认人像。
class _UserCard extends ConsumerWidget {
  const _UserCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    // 展示值：留空回退默认（copy.dart）
    final nickname = profile.nickname.isEmpty
        ? defaultNickname
        : profile.nickname;
    final signature = profile.signature.isEmpty
        ? defaultSignature
        : profile.signature;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          AppPageRoute<void>(builder: (_) => const ProfileEditPage()),
        ),
        child: Row(
          children: [
            // 44dp 圆头像：自定义图（读取失败回退）或暖黄底琥珀人像
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: T.primarySoft,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: profile.hasAvatar
                    ? Image.file(
                        File(profile.avatarPath),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        // 头像文件被清理或损坏时回退默认人像，不崩页面
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.person_outline,
                          size: 22,
                          color: Color(0xFFB08A00),
                        ),
                      )
                    : const Icon(
                        Icons.person_outline,
                        size: 22,
                        color: Color(0xFFB08A00),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 昵称超长单行省略，不撑爆卡片
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    signature,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: T.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: T.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ── 月度概览条 ─────────────────────────────────────

/// 暖黄底圆角 14：前缀文案随周期类型 + 「 · 未分配的预算 ¥1,500」
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.prefix,
    required this.toBudget,
    required this.symbol,
  });

  // 周期文案前缀：自然月「9月还剩 15 天」/ 其他「本期还剩 N 天」/ 自由「本期已进行 N 天」
  final String prefix;
  final double toBudget;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: T.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$prefix · 未分配的预算 $symbol${money(toBudget)}',
        style: const TextStyle(
          fontSize: T.typeBase,
          fontWeight: FontWeight.w500,
          color: T.primaryDeep,
        ),
      ),
    );
  }
}

// ── 货币符号设置对话框（v1.2.0 票 02 / ADR-0017）──

/// 预置 ¥ $ € £ 一键选择，或自定义输入 1–3 个字符（去首尾空白，容纳 HK$ 等复合符号）。
/// 确定返回选中的符号；取消/关闭返回 null（调用方不写入）。
class _CurrencyDialog extends StatefulWidget {
  const _CurrencyDialog({required this.current, required this.ledgerName});

  // 当前账本的符号（用于预选预置项）
  final String current;

  // 账本名（正文注明作用域用）
  final String ledgerName;

  @override
  State<_CurrencyDialog> createState() => _CurrencyDialogState();
}

class _CurrencyDialogState extends State<_CurrencyDialog> {
  // 预置符号：覆盖常见币种（¥ 来自 kDefaultCurrency 保持唯一出处），其余场景走自定义输入
  static const _presets = [kDefaultCurrency, '\$', '€', '£'];

  // 当前点选的预置项（null = 未选预置）
  String? _preset;

  // 自定义输入控制器
  late final TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController();
    // 当前符号是预置项之一时预选它（自定义符号则留空待输入）
    if (_presets.contains(widget.current)) _preset = widget.current;
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  // 待生效符号：自定义输入（去首尾空白）优先，其次预置项
  String? get _candidate {
    final custom = _customCtrl.text.trim();
    if (custom.isNotEmpty) return custom;
    return _preset;
  }

  // 自定义输入去空白后是否超长（按字形簇数，emoji 等也按 1 个字符计）
  bool get _tooLong => _customCtrl.text.trim().characters.length > 3;

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    final valid = candidate != null && !_tooLong;
    return AlertDialog(
      title: const Text('货币符号'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currencyDialogBody(widget.ledgerName),
            style: const TextStyle(fontSize: T.typeSm, color: T.textSecondary),
          ),
          const SizedBox(height: 14),
          // 预置四项：一键选择（输入框有内容时自定义优先）
          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text(p),
                  selected: _preset == p && _customCtrl.text.trim().isEmpty,
                  onSelected: (_) => setState(() {
                    _preset = p;
                    _customCtrl.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 自定义输入：不限输入长度，确定时按去空白后 1–3 字符校验
          TextField(
            controller: _customCtrl,
            decoration: InputDecoration(
              labelText: currencyCustomLabel,
              hintText: currencyCustomHint,
              // 超长提示（去空白后 > 3 字符）
              errorText: _tooLong ? currencyTooLongHint : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      // 注意：actions 是 OverflowBar（非 Flex），不能放 Expanded
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          // 无有效候选（未选预置且自定义去空白后为空）或超长时置灰
          onPressed: !valid ? null : () => Navigator.pop(context, candidate),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

// ── 分组卡 ─────────────────────────────────────

// 一行的数据描述
class _RowData {
  const _RowData({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;

  // 右侧值（可空）
  final String? value;
  final VoidCallback? onTap;

  // 右侧控件（开关等；给定时替代值与箭头，v1.2.0 票 03）
  final Widget? trailing;
}

/// 白卡圆角 18、内边距 8；组标题 11；行高 48
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.title, required this.rows});

  final String title;
  final List<_RowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: T.typeXs,
                fontWeight: FontWeight.w500,
                color: Color(0xFFB4AC9F),
              ),
            ),
          ),
          for (final r in rows)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: r.onTap,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    // 32dp 圆角图标块
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: T.surfaceSubtle,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        r.icon,
                        size: 16,
                        color: const Color(0xFF6E675C),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      r.label,
                      style: const TextStyle(
                        fontSize: T.typeBase,
                        fontWeight: FontWeight.w500,
                        color: T.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (r.trailing != null)
                      r.trailing!
                    else ...[
                      if (r.value != null)
                        Text(
                          r.value!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB4AC9F),
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: T.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
