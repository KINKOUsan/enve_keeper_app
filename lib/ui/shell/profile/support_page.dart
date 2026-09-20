// 支持页（DESIGN.md §9 · v1.2.x 票 05）——关于页「支持」行进入的推入页。
// 开篇一句话 + 微信赞赏码与支付宝收款码上下排列的大图。
// 两张素材原样展示（含「感谢支持喵～」烙字，不裁剪不变形），扫码尺寸优先。
import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../../copy.dart';

// 收款码素材（用户提供的原样文件）
const _kWechatQr = 'assets/wechat_pay.png';
const _kAlipayQr = 'assets/alipay.png';

/// 支持页 — 推入页，无底导航
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

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
                    '支持',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 开篇一句话（无卡片，与备份页说明行同款排版）
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                supportIntroBody,
                style: TextStyle(
                  fontSize: T.typeBase,
                  height: 1.7,
                  color: T.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 微信赞赏码（原样大图，含烙字）
            const _QrCard(caption: '微信赞赏码', asset: _kWechatQr),
            const SizedBox(height: 14),
            // 支付宝收款码
            const _QrCard(caption: '支付宝收款码', asset: _kAlipayQr),
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

/// 收款码白卡：小标题 + 原样大图（BoxFit.contain 保比例不裁剪，宽随卡）
class _QrCard extends StatelessWidget {
  const _QrCard({required this.caption, required this.asset});

  final String caption;
  final String asset;

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
            caption,
            style: const TextStyle(
              fontSize: T.typeMd,
              fontWeight: FontWeight.w600,
              color: T.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // 宽撑满卡（contain 保比例）：解码尺寸随 dpr 变化，扫码尺寸优先取大
          Center(
            child: SizedBox(
              width: double.infinity,
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
