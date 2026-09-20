// 底部导航壳 — 4 个一级 Tab（信封 / 流水 / 统计 / 我的）。
// 视觉：底 80 = 1px 分割线 + 55 导航行 + 24 手势留白（§3 布局；票 08 起不再绘制模拟导航横条）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import 'home/gesture_coach.dart';
import 'home/home_controller.dart';
import 'home/home_page.dart';
import 'records/records_page.dart';
import 'profile/profile_page.dart';
import 'stats/stats_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  // 手势状态机：AppShell 拥有，注入首页与引导遮罩共享
  // （不放 provider：Riverpod 3 禁止在 initState/dispose 改 provider，构造注入最稳）
  late final HomeController _homeGesture;

  // 手势引导遮罩是否在显示
  bool _coachActive = false;

  // 本次会话是否已处理过自动触发（防重复弹）
  bool _autoCoachHandled = false;

  @override
  void initState() {
    super.initState();
    _homeGesture = HomeController();
  }

  @override
  void dispose() {
    _homeGesture.dispose();
    super.dispose();
  }

  // 关掉引导遮罩：走完或跳过都标记「已看过」，之后只从我的页重看
  void _closeCoach() {
    setState(() => _coachActive = false);
    ref.read(gestureCoachSeenProvider.notifier).markSeen();
  }

  @override
  Widget build(BuildContext context) {
    // 「重看手势引导」请求：切回首页 Tab 并重放遮罩（我的页触发）
    ref.listen(coachReplayRequestProvider, (prev, next) {
      if (prev != next) {
        setState(() {
          _index = 0;
          _coachActive = true;
        });
      }
    });

    // 首次进首页自动弹引导：没看过、且已有信封可教时；等一帧让首页布局稳定
    final seen = ref.watch(gestureCoachSeenProvider);
    final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
    if (!_coachActive && !_autoCoachHandled && !seen && envelopes.isNotEmpty) {
      _autoCoachHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _coachActive = true);
      });
    }

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              HomePage(gesture: _homeGesture),
              const RecordsPage(),
              const StatsPage(),
              const ProfilePage(),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: T.surface,
              border: Border(top: BorderSide(color: T.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 导航行 55
                SizedBox(
                  height: 55,
                  child: Row(
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: _NavButton(
                            index: i,
                            selected: _index == i,
                            onTap: () => setState(() => _index = i),
                          ),
                        ),
                    ],
                  ),
                ),
                // 手势留白 24：仅占位，不再绘制模拟全面屏导航横条（v1.2.0 票 08）
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        // 手势引导遮罩：盖住含底导航的全屏（DESIGN.md §17）
        if (_coachActive)
          GestureCoachOverlay(onExit: _closeCoach, gesture: _homeGesture),
      ],
    );
  }
}

/// 单个导航按钮：选中时图标下面垫 56×28 黄色胶囊
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = ['信封', '流水', '统计', '我的'];
  static const _icons = [
    Icons.mail_outline_rounded,
    Icons.subject_rounded,
    Icons.bar_chart_rounded,
    Icons.person_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? T.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _icons[index],
              size: 20,
              color: selected ? T.textPrimary : T.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _labels[index],
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? T.textPrimary : T.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
