// 待规划弧形头部区（DESIGN.md §3 v1.1.0 · New HomePage.png）。
// 原「待规划卡」升格为页头背景：暖黄 #FFF2D1 弧形下缘收进页面底色，占满顶部。
// 行为由外层 GestureDetector 提供（点击 = 记收入、金额可拖出分配），这里只管视觉。
// 两种形态：有钱（暖黄）/ 归零（绿色系，提示行换「每一块钱都有去处了」——原型 .zero）。
// 金额隐私（v1.2.0 票 03）：hideAmount 为真时金额显「符号 + ••••」，只藏数字。
import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../../common/format.dart';

class BudgetArcHeader extends StatelessWidget {
  const BudgetArcHeader({
    super.key,
    required this.toBudget,
    required this.symbol,
    this.hideAmount = false,
  });

  final double toBudget;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  // 金额隐私：隐藏数字（符号 + ••••），仅首页生效（v1.2.0 票 03）
  final bool hideAmount;

  @override
  Widget build(BuildContext context) {
    final zero = toBudget <= 0;
    // 状态栏高度：头部向上延伸到状态栏背后，黄色即状态栏背景（用户需求 v1.1.0）。
    // 首页 SafeArea(top: false) 不消耗顶部 inset，这里能读到。
    final topInset = MediaQuery.paddingOf(context).top;
    // 归零态用绿色系（沿用原待规划卡的零态配色），有钱态用暖黄
    final bg = zero ? const Color(0xFFF3F7F1) : T.primarySoft;
    final labelColor = zero ? const Color(0xFF3D6B33) : T.primaryDeep;
    final hintColor = zero ? const Color(0xFF6E9A63) : T.primaryMid;

    return ClipPath(
      clipper: _ArcBottomClipper(),
      child: Container(
        // 定高：内容 148（DESIGN.md §3「弧形暖黄约 150」）+ 状态栏高度；
        // 弧形下缘占底部约 26
        height: 148 + topInset,
        color: bg,
        padding: EdgeInsets.fromLTRB(16, 10 + topInset, 16, 26),
        child: Column(
          children: [
            // 行一：左「待规划」+ 右「点击记一笔收入」
            Row(
              children: [
                Text(
                  '待规划',
                  style: TextStyle(
                    fontSize: T.typeBase,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                ),
                const Spacer(),
                Text(
                  '点击记一笔收入',
                  style: TextStyle(fontSize: T.typeXs, color: hintColor),
                ),
              ],
            ),
            // 行二：32px Bold 金额（居中）；隐私开启时只显符号 + ••••（票 03）
            Expanded(
              child: Center(
                child: Text(
                  hideAmount
                      ? moneyMasked(symbol: symbol)
                      : '$symbol${money(toBudget)}',
                  style: const TextStyle(
                    fontSize: T.typeXxl,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            // 行三：提示行（归零换文案）
            Text(
              zero ? '每一块钱都有去处了' : '拖到任意信封即可分配',
              style: TextStyle(fontSize: T.typeXs, color: hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

// 弧形下缘裁切：底边中央向下凸出（New HomePage.png 的形状）
class _ArcBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    // 直边高度 = 总高 − 26；弧顶再向下凸 26（二次贝塞尔，控制点在中央下方）
    final straight = size.height - 26;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(0, straight)
      ..quadraticBezierTo(
        size.width / 2,
        size.height + 22,
        size.width,
        straight,
      )
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ArcBottomClipper oldClipper) => false;
}
