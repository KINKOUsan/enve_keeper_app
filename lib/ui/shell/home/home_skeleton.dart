// 首页骨架 — 数据超过 200ms 未就绪才显示（DESIGN.md §18）。
// 沿用首页真实几何：页头 + 待规划卡 124 + 分区标题 + 8 张 158×93 灰块；
// 灰块 #F0E9DC / #EDE6DA，无动画不闪烁；底导航不在骨架内（AppShell 的真导航立即可用）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

/// 骨架门 — [loading] 期间超过 200ms 才切到骨架，数据就绪立即回到真实内容。
/// 快启动（通常 <50ms）永远看不到骨架，避免「闪一下反而显得慢」。
class HomeSkeletonGate extends StatefulWidget {
  const HomeSkeletonGate({
    super.key,
    required this.loading,
    required this.child,
  });

  // 数据是否仍在加载（信封流或设置流任一 loading）
  final bool loading;

  // 加载完成后的真实内容
  final Widget child;

  @override
  State<HomeSkeletonGate> createState() => _HomeSkeletonGateState();
}

class _HomeSkeletonGateState extends State<HomeSkeletonGate> {
  // 200ms 延迟计时器（§18：只在超过 200ms 时才显示）
  Timer? _timer;

  // 骨架是否可见
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sync(widget.loading);
  }

  @override
  void didUpdateWidget(HomeSkeletonGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading != oldWidget.loading) _sync(widget.loading);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // loading 与骨架可见性的单向同步：进入 loading 启动 200ms 计时，就绪立即收回
  void _sync(bool loading) {
    if (loading) {
      _timer ??= Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _visible = true);
      });
    } else {
      _timer?.cancel();
      _timer = null;
      if (_visible) setState(() => _visible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && _visible) return const _HomeSkeleton();
    return widget.child;
  }
}

// 骨架本体 — 全灰块、无交互、无动画
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 页头：左标题块 + 右圆形按钮块
          Padding(
            padding: const EdgeInsets.fromLTRB(T.spaceLg, 8, T.spaceLg, 0),
            child: SizedBox(
              height: 46,
              child: Row(
                children: [
                  _block(w: 72, h: 26, r: 8),
                  const Spacer(),
                  _block(w: 36, h: 36, r: 18, color: _subtle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 待规划卡 124
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
            child: _block(w: double.infinity, h: 124, r: T.radiusCardLg),
          ),
          const SizedBox(height: 14),
          // 分区标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.spaceLg),
            child: _block(w: 48, h: 14, r: 6, color: _subtle),
          ),
          const SizedBox(height: 8),
          // 8 张 158×93 信封卡灰块
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.fromLTRB(
                T.spaceLg,
                6,
                T.spaceLg,
                T.spaceLg,
              ),
              crossAxisCount: 2,
              mainAxisSpacing: T.spaceMd,
              crossAxisSpacing: T.spaceMd,
              childAspectRatio: 158 / 93,
              children: [
                for (var i = 0; i < 8; i++)
                  _block(
                    w: double.infinity,
                    h: double.infinity,
                    r: T.radiusCard,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 灰块两档色（§18）：卡片 #F0E9DC、次级 #EDE6DA
  static const Color _card = Color(0xFFF0E9DC);
  static const Color _subtle = Color(0xFFEDE6DA);

  // 生成一个灰块
  Widget _block({
    required double w,
    required double h,
    required double r,
    Color color = _card,
  }) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}
