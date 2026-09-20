// 首次引导 — 三屏向导（DESIGN.md §11）：记收入 → 挑信封 → 分钱，三屏都可跳过。
// 键盘、按钮、配色全部复用既有组件（IMPLEMENTATION §4：键盘只有一个，不为引导另做一套）。
// 跳过落点 = 首页，第 1 屏已录的钱留在待规划里；完成或跳过都走 markOnboarded。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../theme/envelope_icons.dart';
import '../../theme/tokens.dart';
import '../common/format.dart';
import '../copy.dart';
import '../keypad/keypad_flow.dart';
import '../keypad/keypad_models.dart';

/// 引导门 — 账本未完成引导时的根页面；新用户与新账本都从这里进入（ADR-0011）。
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key, required this.ledgerId});

  final String ledgerId;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  // ── 状态 ──

  // 当前屏：0 记收入 / 1 挑信封 / 2 分钱
  int _step = 0;

  // 第 2 屏勾选的模板下标
  final Set<int> _picked = {};

  // 第 1 屏键盘被手动关掉后，显示重开按钮
  bool _reopen = false;

  // 键盘弹层是否开着（跳过时若开着要先关掉，避免弹层盖到主界面）
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    // 第 1 屏进入即弹键盘（§11：下方直接复用数字键盘弹层）
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIncomePad());
  }

  // ── 动作 ──

  // 跳过引导：先关掉可能开着的键盘弹层，再标记完成（激活账本流刷新后 _Boot 自动切主界面）
  Future<void> _skip() async {
    if (_sheetOpen && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await ref.read(repoProvider).markOnboarded(widget.ledgerId);
  }

  // 第 1 屏：复用键盘记一笔收入（确定键「下一步」），确认后进第 2 屏
  Future<void> _openIncomePad() async {
    _sheetOpen = true;
    final ok = await runKeypadFlow(
      context,
      ref,
      const KeypadRequest(action: KeypadAction.income, okLabel: '下一步'),
    );
    _sheetOpen = false;
    if (!mounted) return;
    setState(() {
      if (ok) {
        _step = 1;
      } else {
        _reopen = true;
      }
    });
  }

  // 第 2 屏：把勾选的模板建成信封（新账本几乎不会撞名，撞上就提示跳过），然后进第 3 屏
  Future<void> _confirmPick() async {
    final repo = ref.read(repoProvider);
    for (final i in _picked) {
      final t = _kTemplates[i];
      final r = await repo.createOrRestoreEnvelope(
        ledgerId: widget.ledgerId,
        name: t.name,
        icon: t.iconId,
        color: t.colorId,
      );
      if (r.conflict && mounted) {
        appToast(context, onboardNameConflictToast(t.name));
      }
    }
    if (mounted) setState(() => _step = 2);
  }

  // 第 3 屏：给某个信封分配（复用分配键盘；超额硬阻在键盘里，不变量②唯一执行点）
  Future<void> _allocateTo(String envelopeId) async {
    _sheetOpen = true;
    await runKeypadFlow(
      context,
      ref,
      KeypadRequest(action: KeypadAction.assign, envelopeId: envelopeId),
    );
    _sheetOpen = false;
  }

  // 完成引导：标记账本已完成
  Future<void> _finish() =>
      ref.read(repoProvider).markOnboarded(widget.ledgerId);

  // ── 三屏主体 ──

  // 第 1 屏：标题 + 说明；键盘以弹层复用，被关掉后给一个重开入口
  List<Widget> _screenIncome() => [
    const Text(onboardIncomeTitle, style: _kTitleStyle),
    const SizedBox(height: 12),
    const Text(onboardIncomeBody, style: _kSubtitleStyle),
    const Spacer(),
    if (_reopen)
      _PrimaryButton(label: onboardReopenKeypadLabel, onTap: _openIncomePad),
  ];

  // 第 2 屏：标题 + 模板卡两列网格 + 主按钮（可全不选直接下一步）
  List<Widget> _screenPick() => [
    const Text(onboardPickTitle, style: _kTitleStyle),
    const SizedBox(height: 12),
    const Text(onboardPickBody, style: _kSubtitleStyle),
    const SizedBox(height: 20),
    Expanded(
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 14,
        mainAxisExtent: 52,
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < _kTemplates.length; i++)
            _TemplateCard(
              template: _kTemplates[i],
              selected: _picked.contains(i),
              onTap: () => setState(() {
                _picked.contains(i) ? _picked.remove(i) : _picked.add(i);
              }),
            ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    _PrimaryButton(label: '下一步', onTap: _confirmPick),
  ];

  // 第 3 屏：暖黄余额条 + 每信封一行（点行改金额）+ 提示 + 主按钮
  List<Widget> _screenAllocate(
    List<Envelope> envelopes,
    double toBudget,
    String symbol,
  ) => [
    const Text(onboardAllocateTitle, style: _kTitleStyle),
    const SizedBox(height: 12),
    const Text(onboardAllocateBody, style: _kSubtitleStyle),
    const SizedBox(height: 20),
    // 还剩多少在待规划
    Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: T.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text(
            onboardRemainLabel,
            style: TextStyle(
              fontSize: T.typeBase,
              fontWeight: FontWeight.w500,
              color: T.primaryDeep,
            ),
          ),
          const Spacer(),
          Text(
            '$symbol${money(toBudget)}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: T.primaryDeep,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 6),
    // 分配行：色点 + 名称 + 已分配金额；点行弹出分配键盘
    for (final e in envelopes)
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _allocateTo(e.id),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: envelopeColorById(e.color).main,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w500,
                    color: T.textPrimary,
                  ),
                ),
              ),
              Text(
                '$symbol${money(e.planned)}',
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w600,
                  color: T.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    const SizedBox(height: 8),
    const Text(
      onboardAllocateHint,
      style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
    ),
    const Spacer(),
    _PrimaryButton(label: '开始记账', onTap: _finish),
  ];

  // ── 页面组装 ──

  @override
  Widget build(BuildContext context) {
    // 第 3 屏要用的信封与待规划余额（流式：分配后行与余额条自动刷新）
    final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
    final toBudget = ref.watch(settingsProvider).value?.toBudget ?? 0;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 页头：步骤圆点 + 跳过
              Row(
                children: [
                  _StepDots(step: _step),
                  const Spacer(),
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      skipCoachLabel,
                      style: TextStyle(
                        fontSize: T.typeBase,
                        color: T.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_step == 0)
                ..._screenIncome()
              else if (_step == 1)
                ..._screenPick()
              else
                ..._screenAllocate(
                  envelopes,
                  toBudget,
                  // 当前账本货币符号（ADR-0017）
                  ref.watch(currencySymbolProvider),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 引导模板数据 ──────────────────────────────────

/// 模板信封（硬编码：规格未决事项①）
class _Template {
  const _Template(this.name, this.iconId, this.colorId);

  final String name;
  final String iconId;
  final String colorId;
}

/// 6 个模板卡：名字 / 图标 / 配色与设计稿 §11 一一对应
const List<_Template> _kTemplates = [
  _Template('餐饮', 'food', 'clay'),
  _Template('交通', 'transport', 'slate'),
  _Template('日用', 'daily', 'moss'),
  _Template('娱乐', 'fun', 'mauve'),
  _Template('人情', 'social', 'amber'),
  _Template('储蓄', 'saving', 'umber'),
];

// ── 共用样式与小组件 ──────────────────────────────

// 引导屏共用文字样式：26 Bold 主标题 / 13 说明
const TextStyle _kTitleStyle = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w700,
  height: 1.3,
  color: T.textPrimary,
);
const TextStyle _kSubtitleStyle = TextStyle(
  fontSize: T.typeBase,
  height: 1.7,
  color: T.textSecondary,
);

/// 顶部步骤指示：6dp 圆点，当前步拉长成 18dp 胶囊（§11）
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Container(
            width: i == step ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == step ? T.primary : const Color(0xFFE3DCD0),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

/// 黄色实心主按钮（键盘确定键同款视觉：52 高、圆角 12）
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: T.primary,
        borderRadius: BorderRadius.circular(T.radiusKey),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.radiusKey),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: T.typeMd,
                fontWeight: FontWeight.w700,
                color: T.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 模板信封卡（两列 52 高、圆角 14）：tint 浅底，选中加同色 1.5dp 描边（§11）
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final _Template template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = envelopeColorById(template.colorId);
    return Material(
      color: color.tint,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          // 选中描边画在前景，不占布局空间
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color.main : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // 28dp 圆角图标块：主色实底 + 白图标
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.main,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  envelopeIconById(template.iconId),
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w500,
                    color: T.textPrimary,
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
