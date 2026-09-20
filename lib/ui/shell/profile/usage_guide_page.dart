// 使用说明页（DESIGN.md §9 · v1.2.x 票 04）。
// README「使用说明」节按 App 排版语言手写的静态重排（拷问决策 2026-09-20：
// 不引 markdown 渲染包）；README 更新后需手动同步页内文案（copy.dart）。
// 内容：信封预算法（sspai 外链）→ 记收入/分配/记消费三张 GIF → 信封的作用
// → 灵活调整（转移 GIF）→ 预算周期与结转（进度条公式的人话版）→ 数据安全。
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
            // ── 什么是信封预算法（sspai 外链）──
            _GuideCard(
              title: '什么是「信封预算法」',
              children: [
                const _BodyText(guideEnvelopeIntroBody),
                const SizedBox(height: 8),
                const _BodyText(guideArticleIntroBody),
                const _LinkRow(
                  label: guideArticleLinkLabel,
                  url: kEnvelopeBudgetArticleUrl,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 让每一块钱都有分工（三步 + GIF）──
            const _GuideCard(
              title: '让每一块钱都有「分工」',
              children: [
                _BodyText(guideAllocationBody),
                SizedBox(height: 12),
                _GuideStep(
                  stepLabel: '记收入',
                  desc: guideStepIncomeDesc,
                  asset: _kIncomeGif,
                ),
                _GuideStep(
                  stepLabel: '分配金额',
                  desc: guideStepAllocateDesc,
                  asset: _kAllocateGif,
                ),
                _GuideStep(
                  stepLabel: '记消费',
                  desc: guideStepSpendDesc,
                  asset: _kSpendGif,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 信封的作用 ──
            const _GuideCard(
              title: '信封的作用',
              children: [
                _BodyText(guideEnvelopeRoleBody),
                SizedBox(height: 8),
                _BodyText(guideEnvelopePriorityBody),
              ],
            ),
            const SizedBox(height: 14),
            // ── 灵活调整预算（转移 GIF）──
            const _GuideCard(
              title: '灵活调整预算',
              children: [
                _BodyText(guideFlexAdjustBody),
                SizedBox(height: 8),
                _BodyText(guideOverdraftBody),
                SizedBox(height: 12),
                _GuideStep(
                  stepLabel: '信封之间转移',
                  desc: guideStepTransferDesc,
                  asset: _kTransferGif,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 预算周期与结转（进度条公式的人话版）──
            const _GuideCard(
              title: '预算周期与结转',
              children: [
                _BodyText(guidePeriodBody),
                SizedBox(height: 8),
                _BodyText(guideProgressbarBody),
                SizedBox(height: 8),
                _BodyText(guideCarryoverBody),
                SizedBox(height: 12),
                _GuideImage(asset: _kPeriodPng),
              ],
            ),
            const SizedBox(height: 14),
            // ── 数据安全 ──
            const _GuideCard(
              title: '数据安全',
              children: [
                _BodyText(guidePrivacyBody),
                SizedBox(height: 8),
                _BodyText(guideDataSafetyBody),
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
          child: const Icon(Icons.arrow_back_rounded, size: 16, color: T.textPrimary),
        ),
      ),
    );
  }
}

/// 白卡圆角 18：组标题 15 SemiBold + 若干内容块
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.title, required this.children});

  final String title;
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
          Text(
            title,
            style: const TextStyle(
              fontSize: T.typeMd,
              fontWeight: FontWeight.w600,
              color: T.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
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

/// 一个操作步骤：步骤名 + 说明 + 演示动图
class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.stepLabel, required this.desc, required this.asset});

  final String stepLabel;
  final String desc;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stepLabel,
          style: const TextStyle(
            fontSize: T.typeBase,
            fontWeight: FontWeight.w600,
            color: T.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        _BodyText(desc),
        const SizedBox(height: 10),
        _GuideImage(asset: asset),
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

/// sspai 外链行：琥珀色文章标题 + 打开图标，点按跳外部浏览器
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openExternalLink(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w500,
                  color: T.primaryDeep,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 16, color: T.textTertiary),
          ],
        ),
      ),
    );
  }
}
