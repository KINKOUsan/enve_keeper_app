// 手势引导遮罩 — 三步 coach marks（DESIGN.md §17）。
// 做法：52% 黑遮罩铺满全屏（含底导航），把要教的元素**原样重画**盖在遮罩上（非挖洞，
// 避免圆角/阴影边缘毛刺）：
//   第 1 步 · 分配 —— 高亮待规划卡，气泡在卡正下方；
//   第 2 步 · 记一笔支出 —— 高亮第一张信封卡，气泡移到屏幕顶部，
//   从卡片下沿画黄色虚线箭头指向底部落点带（92% 实色常显），一次教到位。
//   第 3 步 · 双击也能记支出 —— 同一张信封卡，气泡回到卡下方，
//   卡上叠加双击涟漪动画（两连圈扩散）示意「点两下」。
// 遮罩吸收全部点击，只有气泡按钮可点；三步都可跳过。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../copy.dart';
import 'budget_arc_header.dart';
import 'envelope_card.dart';
import 'home_controller.dart';

/// 引导遮罩 — 由 AppShell 以 Stack 覆盖层挂载；onExit 在跳过或走完三步时回调。
/// [gesture] 是 AppShell 拥有的首页手势状态机，借它的 GlobalKey 注册表定位高亮元素。
class GestureCoachOverlay extends ConsumerStatefulWidget {
  const GestureCoachOverlay({
    super.key,
    required this.onExit,
    required this.gesture,
  });

  final VoidCallback onExit;
  final HomeController gesture;

  @override
  ConsumerState<GestureCoachOverlay> createState() =>
      _GestureCoachOverlayState();
}

class _GestureCoachOverlayState extends ConsumerState<GestureCoachOverlay> {
  // 当前步：0 分配 / 1 记一笔支出 / 2 双击记支出
  int _step = 0;

  // 底部导航总高（1px 分割线 + 55 导航行 + 24 手势区）；首页真实落点带贴在它上方
  static const double _navHeight = 80;

  // 取目标的屏幕矩形（克隆重画与气泡定位用）
  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // 下一步：第 2/3 步需要至少一张信封卡可高亮，没有就直接结束
  void _next() {
    final envelopes = ref.read(envelopesProvider).value ?? const <Envelope>[];
    if (_step < 2 && envelopes.isNotEmpty) {
      setState(() => _step += 1);
    } else {
      widget.onExit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
    final toBudget = ref.watch(settingsProvider).value?.toBudget ?? 0;
    // 高亮克隆体的金额符号与真身一致（ADR-0017）
    final symbol = ref.watch(currencySymbolProvider);

    // 目标：第 1 步 = 待规划卡；第 2/3 步 = 第一张在用信封卡
    Rect? target;
    if (_step == 0) {
      target = _rectOf(widget.gesture.budgetKey);
    } else {
      final key = envelopes.isEmpty
          ? null
          : widget.gesture.envKeys[envelopes.first.id];
      if (key != null) target = _rectOf(key);
    }

    // 键还没完成布局（刚挂载的极小概率）：等一帧重试
    if (target == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    final screenH = MediaQuery.sizeOf(context).height;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 52% 黑遮罩 + 吸收全部点击（只有气泡按钮可点）
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const ColoredBox(color: Color(0x85000000)),
              ),
            ),
            // 高亮克隆体：原样重画盖在遮罩上
            if (target != null)
              Positioned(
                left: target.left,
                top: target.top,
                width: target.width,
                height: target.height,
                child: _step == 0
                    ? BudgetArcHeader(toBudget: toBudget, symbol: symbol)
                    : EnvelopeCard(envelope: envelopes.first, symbol: symbol),
              ),
            // 第 2 步专属：黄色虚线箭头 + 92% 实色落点带
            if (_step == 1 && target != null) ...[
              // 落点带（与首页真实落点带同位：底导航上方）
              const Positioned(
                left: 0,
                right: 0,
                bottom: _navHeight,
                child: _CoachBand(),
              ),
              // 虚线箭头：从卡片下沿画到实心条上沿
              if (screenH - _navHeight - 56 - target.bottom - 16 > 0)
                Positioned(
                  left: target.center.dx - 7,
                  top: target.bottom + 8,
                  child: _DashedArrow(
                    height: screenH - _navHeight - 56 - target.bottom - 16,
                  ),
                ),
            ],
            // 第 3 步专属：双击涟漪示意（两连圈扩散，暗示「点两下」）
            if (_step == 2 && target != null)
              Positioned.fromRect(rect: target, child: const _DoubleTapRipple()),
            // 气泡：第 1/3 步在目标卡正下方，第 2 步移到屏幕顶部给拖拽路径让位
            Positioned(
              left: 20,
              right: 20,
              top: _step == 1 ? 96 : (target?.bottom ?? 240) + 12,
              child: _CoachBubble(
                step: _step,
                title: switch (_step) {
                  0 => coachStep1Title,
                  1 => coachStep2Title,
                  _ => coachStep3Title,
                },
                body: switch (_step) {
                  0 => coachStep1Body(
                      envelopes.isEmpty ? '饮食' : envelopes.first.name,
                    ),
                  1 => coachStep2Body,
                  _ => coachStep3Body,
                },
                actionLabel: _step == 2 ? '知道了' : '下一步',
                onAction: _next,
                onSkip: widget.onExit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 遮罩内的小组件 ──────────────────────────────

/// 引导里的落点带 — 与首页拖拽落点带同款结构（渐变 104 + 实心 56），92% 不透明常显
class _CoachBand extends StatelessWidget {
  const _CoachBand();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.92,
        child: SizedBox(
          height: 160,
          child: Stack(
            children: [
              // 渐变区
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                height: 104,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.5, 1],
                      colors: [
                        Color(0x00FFC72B),
                        Color(0x29FFC72B),
                        Color(0x73FFC72B),
                      ],
                    ),
                  ),
                ),
              ),
              // 实心落点条
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 56,
                child: Container(
                  color: T.primary,
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded, size: 18, color: T.textPrimary),
                      SizedBox(width: 6),
                      Text(
                        dragEdgeBandLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: T.textPrimary,
                        ),
                      ),
                    ],
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

/// 黄色虚线箭头 — 从高亮卡下沿指向落点带（§17：3dp 宽、带箭头）
class _DashedArrow extends StatelessWidget {
  const _DashedArrow({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 14,
        height: height,
        child: CustomPaint(painter: _DashedArrowPainter()),
      ),
    );
  }
}

// 竖向虚线（6 画 5 空）+ 底部实心三角箭头
class _DashedArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = T.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final lineBottom = size.height - 10;
    for (double y = 0; y < lineBottom; y += 11) {
      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, (y + 6).clamp(0.0, lineBottom)),
        paint,
      );
    }
    // 箭头三角
    canvas.drawPath(
      Path()
        ..moveTo(cx - 6, lineBottom)
        ..lineTo(cx + 6, lineBottom)
        ..lineTo(cx, size.height)
        ..close(),
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedArrowPainter oldDelegate) => false;
}

/// 双击涟漪示意 — 两连圈黄色涟漪按「点点…点点」节奏循环扩散（§17 第 3 步）
class _DoubleTapRipple extends StatefulWidget {
  const _DoubleTapRipple();

  @override
  State<_DoubleTapRipple> createState() => _DoubleTapRippleState();
}

class _DoubleTapRippleState extends State<_DoubleTapRipple>
    with SingleTickerProviderStateMixin {
  // 一个循环 = 点两下 + 停顿；第二圈比第一圈晚约 0.12 周期（双击节奏）
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) =>
            CustomPaint(painter: _RipplePainter(_ctrl.value)),
      ),
    );
  }
}

// 两圈涟漪：每圈占 45% 周期，从 10dp 扩到 52dp 渐隐；圈心 = 卡片中心
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t);

  // 周期进度 0..1
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final delay in const [0.0, 0.12]) {
      final p = ((t - delay) / 0.45).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final r = 10 + (52 - 10) * p;
      final alpha = (1 - p) * 0.55;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = T.primary.withValues(alpha: alpha * 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = T.primary.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) => oldDelegate.t != t;
}

/// 气泡 — 白卡圆角 16：标题 + 步骤点 + 正文 + 「跳过引导」/ 黄色主按钮
class _CoachBubble extends StatelessWidget {
  const _CoachBubble({
    required this.step,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    required this.onSkip,
  });

  final int step;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E1A140A),
            offset: Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题 + 步骤点
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _CoachDots(step: step),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: T.typeBase,
              height: 1.7,
              color: T.textSecondary,
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
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
                const Spacer(),
                Material(
                  color: T.primary,
                  borderRadius: BorderRadius.circular(T.radiusPill),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(T.radiusPill),
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          fontSize: T.typeBase,
                          fontWeight: FontWeight.w700,
                          color: T.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 步骤点 — 共三步：当前步拉长成胶囊
class _CoachDots extends StatelessWidget {
  const _CoachDots({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 5),
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
