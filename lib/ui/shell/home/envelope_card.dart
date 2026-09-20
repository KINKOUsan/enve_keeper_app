// 信封卡 — 固定网格里的单张卡（DESIGN.md §3 v1.1.0）：
// 圆角 18、信封色浅底、右侧大装饰圆探出裁切、进度条 = 剩余比例语义。
// 四种余额状态：正常（剩余>20%）/ 接近用尽（≤20% 转主色强调）/
// 用尽（空条）/ 透支（空红条 + 卡片红 tint + 「缺 ¥X」行）。
// 三种手势状态（DESIGN.md §4）：拖拽中源卡 30% 透明 / 悬停放大 1.03 + 阴影 /
// 按下 0.97 缩放（v1.2.x 票 01，裸 Listener 驱动见 home_page）。
// 卡片高度由网格弹性给定（5 行均分），内容经 FittedBox 小屏等比压缩。
import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/envelope_icons.dart';
import '../../../theme/tokens.dart';
import '../../common/format.dart';

/// 卡片进度状态（纯函数，供单测）：进度 = 剩余/已规划。
/// ratio ∈ [0,1]；over = 透支；strong = 接近用尽（0 < 剩余 ≤ 20%）转主色强调。
({double ratio, bool over, bool strong}) cardProgressOf(Envelope e) {
  final over = e.available < 0;
  if (over) return (ratio: 0.0, over: true, strong: false); // 透支：空红条
  if (e.planned <= 0) {
    return (ratio: 0.0, over: false, strong: false); // 已规划 0 → 空条
  }
  final ratio = (e.available / e.planned).clamp(0.0, 1.0);
  // 接近用尽：还有剩余但 ≤ 20%（用尽 ratio = 0 归「空条」状态，不强调）
  return (ratio: ratio, over: false, strong: ratio > 0 && ratio <= 0.2);
}

/// 按压缩放比例（DESIGN.md §4 2026-09-20 增补）：按下 0.97 / 松开回 1
const double kCardPressScale = 0.97;

/// 按压缩放的跟手时长：够快才有「按下瞬间」的感觉（悬停放大用 120ms）
const Duration kCardPressDuration = Duration(milliseconds: 100);

class EnvelopeCard extends StatelessWidget {
  const EnvelopeCard({
    super.key,
    required this.envelope,
    required this.symbol,
    this.hideAmount = false,
    this.dimmed = false,
    this.hovered = false,
    this.pressed = false,
  });

  final Envelope envelope;

  // 当前账本货币符号（ADR-0017）
  final String symbol;

  // 金额隐私：隐藏数字（符号 + ••••），进度条照常；仅首页生效（v1.2.0 票 03）
  final bool hideAmount;

  // 正被拖拽的源卡：30% 透明（原型 .dragging）
  final bool dimmed;

  // 拖拽悬停命中的卡：放大 + 阴影（原型 .hover）
  final bool hovered;

  // 手指按下：0.97 缩放，抬起/手势取消即恢复（裸 Listener 驱动，见 home_page）
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final e = envelope;
    final color = envelopeColorById(e.color);
    final icon = envelopeIconById(e.icon);
    final p = cardProgressOf(e);

    // 卡片实际尺寸由网格单元格给定（引导克隆体为 Positioned 固定尺寸）
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 158.0;
        final h = box.maxHeight.isFinite ? box.maxHeight : 93.0;

        // 横置封包的「翻盖」大圆（对照 envelope.png）：
        // 直径大于卡高 → 上下探出被卡片裁切成弧形翻盖；左缘探入卡片约 1/3 宽
        final flap = h * 1.45;
        final flapLeft = w * 0.66;

        final card = Container(
          decoration: BoxDecoration(
            // 透支：卡片底换成红的浅 tint（DESIGN.md §3 v1.1.0）
            color: p.over ? const Color(0xFFFDECEC) : color.tint,
            borderRadius: BorderRadius.circular(T.radiusCard),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F6B5738),
                offset: Offset(0, 3),
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(T.radiusCard),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封包翻盖：主色浅 tint 大圆，探出右缘与上下缘
                Positioned(
                  left: flapLeft,
                  top: (h - flap) / 2,
                  width: flap,
                  height: flap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.over
                          ? T.overspend.withValues(alpha: 0.14)
                          : color.main.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                // 内容块：小屏空间不足时整体等比压缩。
                // 关键：FittedBox 给子树无界宽度，进度条的 FractionallySizedBox 会算出
                // NaN（∞×0）导致整卡布局崩溃——子树必须定宽为内容区宽（w − 24）。
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: (w - 24).clamp(0.0, double.infinity),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 首行：24dp 圆角图标块（主色底 + 白图标）+ 信封名
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: p.over ? T.overspend : color.main,
                                  borderRadius: BorderRadius.circular(
                                    T.radiusChip,
                                  ),
                                ),
                                child: Icon(
                                  icon,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 限宽：超长名字截断而非撑破布局
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 110,
                                ),
                                child: Text(
                                  e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: T.typeSm,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6E675C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 第二行：19px Bold 剩余金额（透支转红带负号）；
                          // 隐私开启时只显符号 + ••••（票 03）
                          Text(
                            hideAmount
                                ? moneyMasked(symbol: symbol)
                                : moneySigned(e.available, symbol: symbol),
                            style: TextStyle(
                              fontSize: T.typeLg,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: p.over ? T.overspend : T.textPrimary,
                            ),
                          ),
                          // 透支时补「缺 ¥120」行（隐私开启同步遮蔽，不泄露数字）
                          if (p.over)
                            Text(
                              hideAmount
                                  ? '缺 ${moneyMasked(symbol: symbol)}'
                                  : '缺 $symbol${money(-e.available)}',
                              style: const TextStyle(
                                fontSize: T.typeXs,
                                fontWeight: FontWeight.w500,
                                color: T.overspend,
                              ),
                            ),
                          const SizedBox(height: 4),
                          // 第三行：5dp 进度条（槽 18% 主色 / 透支转红；条长 = 剩余比例）
                          _ProgressBar(
                            ratio: p.ratio,
                            over: p.over,
                            strong: p.strong,
                            color: color.main,
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

        // 按压反馈（DESIGN.md §4 2026-09-20 增补）：常驻 AnimatedScale，
        // 松开时靠参数变回 1.0 播放回弹——换成「条件性包裹」会跳变
        final scaled = AnimatedScale(
          scale: pressed ? kCardPressScale : 1.0,
          duration: kCardPressDuration,
          curve: Curves.easeOut,
          child: card,
        );

        // 拖拽中的源卡：30% 透明
        if (dimmed) return Opacity(opacity: 0.3, child: scaled);

        // 悬停命中的卡：放大 1.03 + 加深阴影（原型 .hover）
        if (hovered) {
          return AnimatedScale(
            scale: 1.03,
            duration: const Duration(milliseconds: 120),
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(T.radiusCard)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x2E3C2C14),
                    offset: Offset(0, 10),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: scaled,
            ),
          );
        }
        return scaled;
      },
    );
  }
}

// 5dp 进度条：槽 = 主色 18%（透支红）/ 条 = 主色（接近用尽转全强调）
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.ratio,
    required this.over,
    required this.strong,
    required this.color,
  });

  final double ratio;
  final bool over;
  final bool strong;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(T.radiusBar),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            // 轨道：透支转红，其余保持主色浅底
            Container(
              color: over
                  ? T.overspend.withValues(alpha: 0.25)
                  : color.withValues(alpha: 0.18),
            ),
            // 实条：长度 = 剩余比例；接近用尽转全不透明强调
            FractionallySizedBox(
              widthFactor: ratio,
              child: Container(
                color: strong ? color : color.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
