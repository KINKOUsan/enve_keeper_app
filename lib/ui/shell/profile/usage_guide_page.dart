// 使用说明页（DESIGN.md §9 · v1.2.x 票 04）。
// README「使用说明」节按 App 排版语言重排：正文逐字忠实还原原文（用户要求
// 2026-09-21），仅做结构化排版；唯一改写处是工单明示的 LaTeX 公式人话版。
// 手写静态页而非 markdown 渲染包（拷问决策 2026-09-20）；README 更新后需
// 手动同步页内文案（copy.dart）。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../../common/external_link.dart';
import '../../copy.dart';

// 演示图资产（README 四张 GIF 的压缩版 + 预算周期示意，原素材保留在 assets/ 根）
const _kIncomeGif = 'assets/guide/income.gif';
const _kAllocateGif = 'assets/guide/allocate.gif';
const _kSpendGif = 'assets/guide/spend.gif';
const _kTransferGif = 'assets/guide/transfer.gif';
const _kPeriodPng = 'assets/guide/period.png';

/// 使用说明页 — 「我的」页关于组进入，推入页无底导航
class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ── 页头：返回 + 标题 ──
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  const _BackButton(),
                  const SizedBox(width: 10),
                  const Text(
                    '使用说明',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── 开篇段（原文，内嵌 sspai 链接可点）──
            const _GuideCard(
              children: [_LinkifiedIntro()],
            ),
            const SizedBox(height: 14),
            // ── 让得到的每一块钱都做好「分工」──
            const _GuideCard(
              title: '让得到的每一块钱都做好「分工」',
              children: [
                _BodyText(guideAllocationBody),
                SizedBox(height: 12),
                _GuideStep(
                  label: guideStepIncomeLabel,
                  desc: guideStepIncomeDesc,
                  asset: _kIncomeGif,
                ),
                _GuideStep(
                  label: guideStepAllocateLabel,
                  desc: guideStepAllocateDesc,
                  asset: _kAllocateGif,
                ),
                _GuideStep(
                  label: guideStepSpendLabel,
                  desc: guideStepSpendDesc,
                  asset: _kSpendGif,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 设置信封的作用 ──
            const _GuideCard(
              title: '设置信封的作用',
              children: [
                _BodyText(guideEnvelopeRoleBody),
                SizedBox(height: 8),
                _BodyText(guideEnvelopePriorityBody),
              ],
            ),
            const SizedBox(height: 14),
            // ── 灵活调整预算 ──
            const _GuideCard(
              title: '灵活调整预算',
              children: [
                _BodyText(guideFlexAdjustBody),
                SizedBox(height: 8),
                _BodyText(guideOverdraftBody),
                SizedBox(height: 12),
                _GuideStep(
                  label: guideStepTransferLabel,
                  desc: guideStepTransferDesc,
                  asset: _kTransferGif,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 预算周期与结转（公式为人话版）──
            const _GuideCard(
              title: '预算周期与结转',
              children: [
                _SubHeading(guidePeriodHeading),
                _BodyText(guidePeriodBody),
                SizedBox(height: 8),
                _BodyText(guideProgressbarBody + guideFormulaPlain),
                SizedBox(height: 8),
                _SubHeading(guideCarryoverHeading),
                _BodyText(guideCarryoverBody),
                SizedBox(height: 8),
                _BodyText(guideCarryoverOverdraftBody),
                SizedBox(height: 12),
                _GuideImage(asset: _kPeriodPng),
              ],
            ),
            const SizedBox(height: 14),
            // ── 数据安全 ──
            const _GuideCard(
              title: '数据安全',
              children: [
                _GuideStep(label: guidePrivacyLabel, desc: guidePrivacyBody),
                SizedBox(height: 8),
                _GuideStep(
                  label: guideDataSafetyLabel,
                  desc: guideDataSafetyBody,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 页面小件 ──────────────────────────────────

/// 36dp 圆形返回按钮（与关于页同款）
class _BackButton extends StatelessWidget {
  const _BackButton();

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
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(
            Icons.arrow_back_rounded,
            size: 16,
            color: T.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 白卡圆角 18：可选节标题 + 若干内容块
class _GuideCard extends StatelessWidget {
  const _GuideCard({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: T.typeMd,
                fontWeight: FontWeight.w600,
                color: T.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// 正文段：13 Regular 暖灰、1.7 行高
class _BodyText extends StatelessWidget {
  const _BodyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: T.typeBase,
        height: 1.7,
        color: T.textSecondary,
      ),
    );
  }
}

/// 节内小标题（原文的 **预算周期**：/**结转**：加粗行）
class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: T.typeBase,
        fontWeight: FontWeight.w600,
        color: T.textPrimary,
      ),
    );
  }
}

/// 开篇段（原文整段）：内嵌链接标题可点，跳 sspai 外部浏览器
class _LinkifiedIntro extends StatefulWidget {
  const _LinkifiedIntro();

  @override
  State<_LinkifiedIntro> createState() => _LinkifiedIntroState();
}

class _LinkifiedIntroState extends State<_LinkifiedIntro> {
  late final TapGestureRecognizer _linkTap;

  @override
  void initState() {
    super.initState();
    _linkTap = TapGestureRecognizer()
      ..onTap = () => openExternalLink(context, kEnvelopeBudgetArticleUrl);
  }

  @override
  void dispose() {
    _linkTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(
      fontSize: T.typeBase,
      height: 1.7,
      color: T.textSecondary,
    );
    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          const TextSpan(text: guideIntroBeforeLink),
          TextSpan(
            text: guideArticleLinkLabel,
            style: const TextStyle(color: T.primaryDeep),
            recognizer: _linkTap,
          ),
          const TextSpan(text: guideIntroAfterLink),
        ],
      ),
    );
  }
}

/// 一个条目（原文的粗体标签行）：**标签**：正文，可配演示图
class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.label, required this.desc, this.asset});

  final String label;
  final String desc;

  // 演示图（可空——数据安全两条没有图）
  final String? asset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label：',
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w600,
                  color: T.textPrimary,
                ),
              ),
              TextSpan(
                text: desc,
                style: const TextStyle(
                  fontSize: T.typeBase,
                  height: 1.7,
                  color: T.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (asset != null) ...[
          const SizedBox(height: 10),
          _GuideImage(asset: asset!),
        ],
      ],
    );
  }
}

/// 演示图：圆角 12 居中展示（GIF 自动播放；宽 280 与 README 版式一致）
class _GuideImage extends StatelessWidget {
  const _GuideImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          asset,
          width: 280,
          fit: BoxFit.fitWidth,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
