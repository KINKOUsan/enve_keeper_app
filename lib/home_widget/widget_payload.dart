// 桌面小组件·信封卡片的数据负载（v1.3.0 票 05 / ADR-0021）。
// 纯函数：App 侧把展示所需的字符串 / 颜色 / 图标路径全部算好，原生侧只负责
// 排版显示、不复制任何业务逻辑；所有值统一以字符串落 home_widget 的
// SharedPreferences，原生侧 getString 读取（跨版本最稳的载体类型）。
import '../../domain/models.dart';
import '../../theme/tokens.dart';
import '../ui/common/format.dart';

/// 数据键（与原生 EnvelopeWidgetProvider 约定一致，改动须两侧同步）
class EnvelopeCardKeys {
  EnvelopeCardKeys._();

  /// 新添加、未绑定实例的兜底信封 id（票 05 临时绑定 = 第一个信封；
  /// 票 07 编辑页写入实例级 `binding_<appWidgetId>` 后替代此兜底）
  static const defaultBinding = 'envelope.default';

  /// 当前推送的信封数（原生侧占位判断用）
  static const count = 'envelope.count';

  static String name(String id) => 'envelope.$id.name';
  static String amount(String id) => 'envelope.$id.amount';
  static String masked(String id) => 'envelope.$id.masked';
  static String color(String id) => 'envelope.$id.color';
  static String icon(String id) => 'envelope.$id.icon';

  // ── 实例级配置（票 06/07：按 appWidgetId 存，原生与编辑页共用）──

  /// 绑定的信封 id（编辑页写入；替代 defaultBinding 的正式绑定）
  static String binding(int widgetId) => 'binding_$widgetId';

  /// 字体颜色 hex（#RRGGBB，票 07 预设色板）
  static String fontColor(int widgetId) => 'fgColor_$widgetId';

  /// 背景图文件绝对路径（票 08；空/缺键 = 恢复信封主题色底）
  /// 票 16：`shadow_<id>`/`scrim_<id>` 键随「阴影恒开、底衬移除」一并作废
  static String background(int widgetId) => 'bg_$widgetId';

  // ── 统计卡片（票 09）：配置键 + 推送数据键，前缀 sw. ──

  /// 统计区间配置：'week' | 'month' | 'last7' | 'last30'（缺省按未配置处理；
  /// 旧配置 'year' 读取时回落本月，票 16 已移除该区间）
  static String statsRange(int widgetId) => 'statsRange_$widgetId';

  /// 可视化类型配置：'ring' | 'bars'
  static String statsChart(int widgetId) => 'statsChart_$widgetId';

  /// 绑定账本 id（配置时所在的账本；App 内切换账本不影响组件）
  static String statsLedger(int widgetId) => 'statsLedger_$widgetId';

  /// 区间标签基底（「本周」等；「还剩 N 天」由原生按 end_millis 动态拼）
  static String statsLabel(int widgetId) => 'sw.$widgetId.label';

  /// 区间结束时刻（epoch 毫秒字符串；滚动区间无此键）
  static String statsEndMillis(int widgetId) => 'sw.$widgetId.end_millis';

  /// 数字摘要三数（含货币符号，展示就绪）
  static String statsPlanned(int widgetId) => 'sw.$widgetId.planned';
  static String statsUsed(int widgetId) => 'sw.$widgetId.used';
  static String statsLeft(int widgetId) => 'sw.$widgetId.left';

  /// 执行进度：预渲染进度条位图文件路径（原生不画 ProgressBar——国产桌面
  /// 对它渲染不稳，是「载入窗口小部件时出现问题」的已知触发点）
  static String statsBar(int widgetId) => 'sw.$widgetId.bar';

  /// 可视化位图文件绝对路径（环形/柱状由 Flutter 预渲染）
  static String statsChartPath(int widgetId) => 'sw.$widgetId.chart';
}

/// 生成一批信封的卡片负载（逐键写入 home_widget 数据）。
/// [hiddenIds] 是「按信封隐藏金额」的开关节点：命中的信封金额显示遮蔽形态
/// （与 App 内首页/详情同一开关、同一形态）。[defaultId] 为空列表时忽略。
Map<String, String> buildEnvelopeCardPayloads({
  required List<Envelope> envelopes,
  required String symbol,
  required Set<String> hiddenIds,
  String? defaultId,
}) {
  final out = <String, String>{};
  for (final e in envelopes) {
    final masked = hiddenIds.contains(e.id);
    out[EnvelopeCardKeys.name(e.id)] = e.name;
    // 金额恒为展示就绪字符串：隐藏 → ¥••••；透支 → −¥X（负号 U+2212，照记不拦）
    out[EnvelopeCardKeys.amount(e.id)] = masked
        ? moneyMasked(symbol: symbol)
        : moneySigned(e.available, symbol: symbol);
    out[EnvelopeCardKeys.masked(e.id)] = masked ? '1' : '0';
    // 主色 #RRGGBB（信封卡底色，与 App 内信封主题色一致）
    final argb = envelopeColorById(e.color).main.toARGB32();
    out[EnvelopeCardKeys.color(e.id)] =
        '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
  out[EnvelopeCardKeys.count] = '${envelopes.length}';
  if (defaultId != null && envelopes.isNotEmpty) {
    out[EnvelopeCardKeys.defaultBinding] = defaultId;
  }
  return out;
}
