// 小组件实例编辑页（v1.3.0 票 07–09 / ADR-0021）。
// 两类组件共用一个入口，按实例的 Provider 类型分流：
// - 信封卡片：绑定信封 + 背景图 + 字体颜色 + 文字阴影；
// - 统计卡片：统计区间（周/月/近30日/年）+ 可视化（环形/柱状二选一）
//   + 背景图 + 字体颜色 + 文字阴影。
// 保存即写 home_widget 数据、触发组件刷新并自增配置版本（同步控制器重推）。
// 入口：未配置占位点击、Android 12+ 长按重新配置（经 WidgetConfigureActivity）、
// 「我的-桌面小部件」实例列表。
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../../domain/models.dart';
import '../../../home_widget/stats_payload.dart';
import '../../../home_widget/widget_bg.dart';
import '../../../home_widget/widget_payload.dart';
import '../../../home_widget/widget_refresh.dart';
import '../../../home_widget/widget_style.dart';
import '../../../home_widget/widget_sync.dart' show widgetConfigRevProvider;
import '../../../state/providers.dart';
import '../../../theme/envelope_icons.dart';
import '../../../theme/tokens.dart';
import '../../common/image_crop_page.dart';
import '../../copy.dart';
import '../../keypad/keypad_flow.dart' show appToast;

/// 编辑一张桌面小组件。[widgetId] 是 Android 的 appWidgetId。
class WidgetEditPage extends ConsumerStatefulWidget {
  const WidgetEditPage({super.key, required this.widgetId});

  final int widgetId;

  @override
  ConsumerState<WidgetEditPage> createState() => _WidgetEditPageState();
}

class _WidgetEditPageState extends ConsumerState<WidgetEditPage> {
  // 实例类型（信封卡 / 统计卡），枚举实例时判定
  bool _isStats = false;

  // 存储态（initState 里异步读入；_loading 期间禁交互）
  bool _loading = true;
  bool _saving = false;

  // 信封卡：绑定信封
  String? _binding;

  // 统计卡：区间 + 可视化 + 绑定账本（配置时所在的账本）
  WidgetStatsRange _range = WidgetStatsRange.month;
  WidgetStatsChart _chart = WidgetStatsChart.ring;
  String? _statsLedgerId;

  // 共用外观：字色（未手改时跟随建议）/ 背景图路径。
  // 票 16：底衬移除、阴影恒开——两者不再作为开关项
  late String _fontColorId;
  bool _colorTouched = false;
  String? _bgPath;

  // 背景图保存中（选图 → 裁剪 → 圆角落盘）
  bool _bgBusy = false;

  @override
  void initState() {
    super.initState();
    _fontColorId = kWidgetFontColors.first.id;
    unawaited(_load());
  }

  // 读入实例类型与当前配置（平台不可用按未配置的信封卡处理）
  Future<void> _load() async {
    String? storedColor;
    String? storedBg;
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      _isStats = widgets.any(
        (w) =>
            w.androidWidgetId == widget.widgetId &&
            (w.androidClassName ?? '').contains('StatsWidgetProvider'),
      );
      storedColor = await HomeWidget.getWidgetData<String>(
        EnvelopeCardKeys.fontColor(widget.widgetId),
      );
      storedBg = await HomeWidget.getWidgetData<String>(
        EnvelopeCardKeys.background(widget.widgetId),
      );
      if (_isStats) {
        _range = WidgetStatsRangeX.parse(
          await HomeWidget.getWidgetData<String>(
            EnvelopeCardKeys.statsRange(widget.widgetId),
          ),
        );
        _chart = WidgetStatsChartX.parse(
          await HomeWidget.getWidgetData<String>(
            EnvelopeCardKeys.statsChart(widget.widgetId),
          ),
        );
        _statsLedgerId = await HomeWidget.getWidgetData<String>(
          EnvelopeCardKeys.statsLedger(widget.widgetId),
        );
      } else {
        _binding = await HomeWidget.getWidgetData<String>(
          EnvelopeCardKeys.binding(widget.widgetId),
        );
      }
    } on Exception {
      // 测试宿主：保持默认（信封卡、未配置）
    }
    if (!mounted) return;
    setState(() {
      _fontColorId = storedColor ?? _suggestedColor();
      _colorTouched = storedColor != null;
      _bgPath = (storedBg == null || storedBg.isEmpty) ? null : storedBg;
      _loading = false;
    });
  }

  // 按当前（默认 = 第一个）信封主色明暗给建议字色
  String _suggestedColor() {
    final envs = ref.read(envelopesProvider).value ?? const <Envelope>[];
    final target = _binding == null
        ? (envs.isEmpty ? null : envs.first)
        : envs.where((e) => e.id == _binding).firstOrNull;
    if (target == null) return kWidgetFontColors.first.id;
    return suggestWidgetFontColor(envelopeColorById(target.color).main);
  }

  // 保存：类型相关的配置键 + 共用外观键 → 触发刷新 + 自增配置版本
  Future<void> _save() async {
    if (_saving) return;
    if (!_isStats && _binding == null) return;
    _saving = true;
    try {
      if (_isStats) {
        final ledgerId =
            _statsLedgerId ?? ref.read(activeLedgerProvider)?.id;
        await HomeWidget.saveWidgetData(
          EnvelopeCardKeys.statsRange(widget.widgetId),
          _range.id,
        );
        await HomeWidget.saveWidgetData(
          EnvelopeCardKeys.statsChart(widget.widgetId),
          _chart.id,
        );
        if (ledgerId != null) {
          await HomeWidget.saveWidgetData(
            EnvelopeCardKeys.statsLedger(widget.widgetId),
            ledgerId,
          );
        }
      } else {
        await HomeWidget.saveWidgetData(
          EnvelopeCardKeys.binding(widget.widgetId),
          _binding,
        );
      }
      await HomeWidget.saveWidgetData(
        EnvelopeCardKeys.fontColor(widget.widgetId),
        _fontColorId,
      );
      await HomeWidget.saveWidgetData(
        EnvelopeCardKeys.background(widget.widgetId),
        _bgPath ?? '',
      );
      // 统计卡的数字与位图由同步控制器按新配置现算（配置版本触发重推）
      ref.read(widgetConfigRevProvider.notifier).bump();
      // 只走直调通道（票 12 引入，MIUI/ColorOS 真机均验证可达）：广播+
      // 直调曾毫秒级连发两次同内容包裹，小更新无事、带位图的大更新疑似被
      // ColorOS 桌面当连发丢弃（261014：清除背景生效、设背景不生效的
      // 嫌疑帮凶），收敛为单次推送
      await refreshWidgetsDirect();
    } on Exception {
      // 平台不可用：不阻塞退出（真机上不会走到）
    }
    if (!mounted) return;
    appToast(context, widgetEditSavedToast);
    Navigator.of(context).pop();
  }

  // 选背景：相册 → 按组件比例裁剪（信封卡 1:1 / 统计卡 2:1）→ 圆角化落盘。
  // 裁剪中途取消 → 原背景不变、无残留文件。
  Future<void> _pickBackground() async {
    if (_bgBusy) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _bgBusy = true);
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      final cropped = await showImageCropPage(
        context,
        image: bytes,
        aspectRatio: _isStats ? 2 : 1,
        title: '裁剪背景',
        maxSide: 1024,
      );
      if (cropped == null || !mounted) return; // 取消：不动原背景
      final saved = await saveWidgetBackground(
        bytes: cropped,
        baseDir: await getApplicationSupportDirectory(),
        oldPath: _bgPath,
      );
      if (saved == null) {
        if (mounted) appToast(context, widgetBgSaveFailedToast);
        return;
      }
      setState(() => _bgPath = saved);
    } on FileSystemException {
      if (mounted) appToast(context, widgetBgSaveFailedToast);
    } finally {
      if (mounted) setState(() => _bgBusy = false);
    }
  }

  // 清除背景：删文件、清键，恢复信封主题色底
  Future<void> _clearBackground() async {
    await deleteWidgetBackground(_bgPath);
    if (!mounted) return;
    setState(() => _bgPath = null);
  }

  @override
  Widget build(BuildContext context) {
    final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _PageHeader(
                    title: _isStats
                        ? widgetEditStatsTitle
                        : widgetEditTitle,
                  ),
                  const SizedBox(height: 12),
                  if (_isStats) ...[
                    _SectionCard(
                      title: widgetEditStatsRangeSection,
                      child: _rangePicker(),
                    ),
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: widgetEditStatsChartSection,
                      child: _chartPicker(),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    _SectionCard(
                      title: widgetEditEnvelopeSection,
                      child: _envelopePicker(envelopes),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _SectionCard(
                    title: widgetEditBgSection,
                    child: _backgroundSection(),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: widgetEditFontColorSection,
                    child: _fontColorSection(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: T.primary,
                        foregroundColor: T.textPrimary,
                        disabledBackgroundColor: const Color(0xFFF3EFE7),
                        disabledForegroundColor: const Color(0xFFCCC4B8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(T.radiusKey),
                        ),
                      ),
                      // 信封卡未选信封（含无信封可绑）置灰；统计卡恒可存
                      onPressed: (!_isStats && _binding == null) ? null : _save,
                      child: const Text(
                        '保存',
                        style: TextStyle(
                          fontSize: T.typeMd,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── 区间选择（周/月/近30日/年，胶囊四选一）──
  Widget _rangePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in WidgetStatsRange.values)
          ChoiceChip(
            label: Text(r.label),
            selected: _range == r,
            onSelected: (_) => setState(() => _range = r),
          ),
      ],
    );
  }

  // ── 可视化选择（环形图/柱状图，二选一）──
  Widget _chartPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widgetEditStatsChartHint,
          style: const TextStyle(fontSize: T.typeXs, color: T.textTertiary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('支出构成环形图'),
              selected: _chart == WidgetStatsChart.ring,
              onSelected: (_) => setState(
                () => _chart = WidgetStatsChart.ring,
              ),
            ),
            ChoiceChip(
              label: const Text('支出趋势柱状图'),
              selected: _chart == WidgetStatsChart.bars,
              onSelected: (_) =>
                  setState(() => _chart = WidgetStatsChart.bars),
            ),
          ],
        ),
      ],
    );
  }

  // ── 信封绑定列表 ──
  Widget _envelopePicker(List<Envelope> envelopes) {
    if (envelopes.isEmpty) {
      return Text(
        widgetEditNoEnvelopeBody,
        style: const TextStyle(
          fontSize: T.typeBase,
          color: T.textSecondary,
          height: 1.6,
        ),
      );
    }
    return Column(
      children: [
        for (final e in envelopes)
          _EnvelopeOptionRow(
            envelope: e,
            selected: e.id == (_binding ?? ''),
            onTap: () => setState(() {
              _binding = e.id;
              // 字色未手动改过 → 跟随新信封主色的建议
              if (!_colorTouched) {
                _fontColorId = suggestWidgetFontColor(
                  envelopeColorById(e.color).main,
                );
              }
            }),
          ),
      ],
    );
  }

  // ── 背景图：预览 + 更换/清除 + 底衬开关 ──
  Widget _backgroundSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widgetEditBgHint,
          style: const TextStyle(fontSize: T.typeXs, color: T.textTertiary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // 预览（60dp，按组件比例）：无背景显示占位底
            Container(
              width: 60,
              height: _isStats ? 30 : 60,
              decoration: BoxDecoration(
                color: T.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: _bgPath == null
                  ? const Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: T.textTertiary,
                    )
                  : Image.file(
                      File(_bgPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: T.textTertiary,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _bgBusy ? null : _pickBackground,
                    child: Text(
                      _bgPath == null ? '选择图片' : '更换图片',
                    ),
                  ),
                  if (_bgPath != null)
                    OutlinedButton(
                      onPressed: _clearBackground,
                      child: const Text('清除背景'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 字色色板（建议项随背景明暗）──
  Widget _fontColorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widgetEditFontColorHint,
          style: const TextStyle(fontSize: T.typeXs, color: T.textTertiary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            for (final option in kWidgetFontColors)
              _FontColorDot(
                option: option,
                suggested: option.id == _suggestedColor(),
                selected: option.id == _fontColorId,
                onTap: () => setState(() {
                  _fontColorId = option.id;
                  _colorTouched = true;
                }),
              ),
          ],
        ),
      ],
    );
  }
}

// ── 小组件 ──────────────────────────────────

// 推入页页头（无底导航页的既有样式：返回 + 标题）
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// 白卡分组容器（与我的页分组卡同视觉语言）
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              fontSize: T.typeSm,
              fontWeight: FontWeight.w600,
              color: T.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// 信封选项行：图标 + 名字 + 色点 + 选中态
class _EnvelopeOptionRow extends StatelessWidget {
  const _EnvelopeOptionRow({
    required this.envelope,
    required this.selected,
    required this.onTap,
  });

  final Envelope envelope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = envelopeColorById(envelope.color);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(envelopeIconById(envelope.icon), size: 20, color: color.main),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                envelope.name,
                style: const TextStyle(
                  fontSize: T.typeBase,
                  fontWeight: FontWeight.w500,
                  color: T.textPrimary,
                ),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color.main,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected ? T.primary : T.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// 字色圆点：选中描边 + 建议角标（按背景明暗自动建议的那一项）
class _FontColorDot extends StatelessWidget {
  const _FontColorDot({
    required this.option,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  final WidgetFontColorOption option;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: option.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? T.primary : T.border,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 18, color: T.textPrimary)
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            suggested ? '${option.label} · 建议' : option.label,
            style: TextStyle(
              fontSize: T.typeXs,
              color: suggested ? T.textSecondary : T.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
