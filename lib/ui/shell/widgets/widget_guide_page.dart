// 「我的-桌面小部件」页（v1.3.0 票 07 / ADR-0021）：使用说明 + 添加引导 +
// 已添加实例列表（信封卡片 / 统计卡片，点击进编辑页）。说明文案为按用户
// 手写使用说明风格起草的草稿，见 copy.dart 对应注释——用户逐字改定前不算
// 定稿（票 07 验收项）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../domain/models.dart';
import '../../../home_widget/stats_payload.dart';
import '../../../home_widget/widget_payload.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../common/app_route.dart';
import '../../copy.dart';
import 'widget_edit_page.dart';

/// 桌面小部件说明页 — 「我的」页关于组进入，推入页无底导航
class WidgetGuidePage extends ConsumerStatefulWidget {
  const WidgetGuidePage({super.key});

  @override
  ConsumerState<WidgetGuidePage> createState() => _WidgetGuidePageState();
}

class _WidgetGuidePageState extends ConsumerState<WidgetGuidePage> {
  // 已添加实例（null = 读取中；空表 = 没添加过）
  List<HomeWidgetInfo>? _installed;

  // 各实例的主配置（widgetId → 信封绑定 id / 统计区间 id，异步补齐）
  final Map<int, String?> _primaryConfig = {};

  // 统计卡实例的可视化配置（widgetId → 'ring'/'bars'，显示名用）
  final Map<int, String?> _chartConfig = {};

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  // 枚举实例并补齐配置信息（从编辑页返回后也走这里刷新）
  Future<void> _refresh() async {
    List<HomeWidgetInfo> widgets = const [];
    try {
      widgets = await HomeWidget.getInstalledWidgets();
    } on Exception {
      // 平台不可用（测试宿主 / 桌面调试）：按没有实例处理
    }
    final primary = <int, String?>{};
    final charts = <int, String?>{};
    for (final w in widgets) {
      final id = w.androidWidgetId;
      if (id == null) continue;
      final isStats =
          (w.androidClassName ?? '').contains('StatsWidgetProvider');
      try {
        primary[id] = await HomeWidget.getWidgetData<String>(
          isStats
              ? EnvelopeCardKeys.statsRange(id)
              : EnvelopeCardKeys.binding(id),
        );
        if (isStats) {
          charts[id] = await HomeWidget.getWidgetData<String>(
            EnvelopeCardKeys.statsChart(id),
          );
        }
      } on Exception {
        primary[id] = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _installed = widgets;
      _primaryConfig
        ..clear()
        ..addAll(primary);
      _chartConfig
        ..clear()
        ..addAll(charts);
    });
  }

  @override
  Widget build(BuildContext context) {
    final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 22,
                        color: T.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '桌面小部件',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── 说明 / 添加 / 编辑 三段（copy 草稿）──
            const _GuideCard(child: Text(widgetGuideIntroBody)),
            const SizedBox(height: 14),
            const _GuideCard(
              title: widgetGuideAddTitle,
              child: Text(widgetGuideAddBody),
            ),
            const SizedBox(height: 14),
            const _GuideCard(
              title: widgetGuideManageTitle,
              child: Text(widgetGuideManageBody),
            ),
            const SizedBox(height: 14),
            // ── 已添加实例 ──
            _GuideCard(title: '已添加的小组件', child: _instanceList(envelopes)),
          ],
        ),
      ),
    );
  }

  // 实例列表：本 App 的两类组件（信封卡片 / 统计卡片）；点行进编辑页
  Widget _instanceList(List<Envelope> envelopes) {
    final installed = _installed;
    if (installed == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final mine = installed
        .where((w) => w.androidWidgetId != null)
        .where(
          (w) =>
              (w.androidClassName ?? '').contains('EnvelopeWidgetProvider') ||
              (w.androidClassName ?? '').contains('StatsWidgetProvider'),
        )
        .toList();
    if (mine.isEmpty) {
      return const Text(
        widgetGuideEmptyBody,
        style: TextStyle(fontSize: T.typeBase, color: T.textSecondary),
      );
    }
    return Column(
      children: [
        for (final w in mine)
          _InstanceRow(
            widgetId: w.androidWidgetId!,
            isStats: (w.androidClassName ?? '').contains('StatsWidgetProvider'),
            displayName: _displayName(w.androidWidgetId!, envelopes),
            onTap: () async {
              await Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => WidgetEditPage(widgetId: w.androidWidgetId!),
                ),
              );
              await _refresh(); // 编辑（绑定/外观）可能已变，返回后刷新
            },
          ),
      ],
    );
  }

  // 行显示名：信封卡显示绑定信封名；统计卡显示「区间 · 可视化」
  String _displayName(int widgetId, List<Envelope> envelopes) {
    final isStats = (_installed ?? const <HomeWidgetInfo>[])
            .where((w) => w.androidWidgetId == widgetId)
            .firstOrNull !=
        null &&
        _chartConfig.containsKey(widgetId);
    final primary = _primaryConfig[widgetId];
    if (primary == null) return '未配置';
    if (isStats) {
      final range = WidgetStatsRangeX.parse(primary);
      final chart = WidgetStatsChartX.parse(_chartConfig[widgetId]);
      return '${range.label} · ${chart == WidgetStatsChart.ring ? '环形图' : '柱状图'}';
    }
    final env = envelopes.where((e) => e.id == primary).firstOrNull;
    return env?.name ?? '信封不在当前账本';
  }
}

// ── 小组件 ──────────────────────────────────

// 说明卡片：白底圆角 18，标题 + 正文（与使用说明页同视觉语言）
class _GuideCard extends StatelessWidget {
  const _GuideCard({this.title, required this.child});

  final String? title;
  final Widget child;

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
              ),
            ),
            const SizedBox(height: 8),
          ],
          DefaultTextStyle(
            style: const TextStyle(
              fontSize: T.typeBase,
              color: T.textPrimary,
              height: 1.7,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

// 实例行：卡片图标 + 「卡片类型 · 主配置」+ 箭头
class _InstanceRow extends StatelessWidget {
  const _InstanceRow({
    required this.widgetId,
    required this.isStats,
    required this.displayName,
    required this.onTap,
  });

  final int widgetId;
  final bool isStats;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: T.primarySoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                isStats ? Icons.bar_chart : Icons.mail_outline_rounded,
                size: 16,
                color: const Color(0xFF8A6A00),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${isStats ? '统计卡片' : '信封卡片'} · $displayName',
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w500,
                  color: T.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: T.textTertiary),
          ],
        ),
      ),
    );
  }
}
