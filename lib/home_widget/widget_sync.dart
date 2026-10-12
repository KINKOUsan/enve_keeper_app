// 桌面小组件数据同步控制器（v1.3.0 票 05/09 / ADR-0021）：
// App 内每次数据变动（交易 / 隐藏开关 / 信封改动 / 账本切换 / 组件配置变更）
// 即推送刷新——无后台轮询、不申请任何权限；纯本地记账的数据只有 App 自己
// 能改，前台推送即「随时同步」的全部含义。
// 生命周期归属：app.dart 的 _Boot watch 保持全应用存活（同 autoBackup 模式）。
// 刻意不用防抖计时器：数据变动是人触发的低频事件，直推更简单，
// 也避免 widget 测试里留下未决 Timer（陷阱清单）。
//
// 推送范围（票 09 起多账本正确）：**全部账本**的在用信封负载（组件绑定的
// 是具体信封/账本，App 内切账本不影响桌面组件）+ 已配置统计卡的实例数据
// （按各实例的区间/可视化配置现算现画）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_repository.dart';
import '../data/db/database.dart' as db;
import '../domain/models.dart';
import '../state/providers.dart';
import 'icon_raster.dart';
import 'stats_payload.dart';
import 'stats_render.dart';
import 'widget_payload.dart';
import 'widget_refresh.dart';

// 组件配置版本号：编辑页每保存一次自增——同步控制器 watch 它，
// 配置变更（绑定/区间/可视化/外观）立即触发一次重推
class WidgetConfigRev extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final widgetConfigRevProvider = NotifierProvider<WidgetConfigRev, int>(
  WidgetConfigRev.new,
);

class WidgetSyncController extends Notifier<bool> {
  // 待推送令牌：build 每次重跑（依赖变化）置位，推送循环消费
  bool _dirty = false;
  bool _pushing = false;
  bool _active = true;

  @override
  bool build() {
    _active = true;
    // 依赖集：交易（统计聚合与余额随流水变）、在用信封（触发器）、货币符号、
    // 隐藏开关、账本列表（增删账本）、激活账本（默认绑定兜底）、配置版本
    ref.watch(txnsProvider);
    ref.watch(envelopesProvider);
    ref.watch(currencySymbolProvider);
    ref.watch(hiddenEnvelopeIdsProvider);
    ref.watch(ledgersProvider);
    final ledger = ref.watch(activeLedgerProvider);
    ref.watch(widgetConfigRevProvider);

    _dirty = true;
    unawaited(_drain(ledger?.id));
    ref.onDispose(() => _active = false);
    return true;
  }

  // 推送循环：_dirty 被置位就再推一轮；推送期间又有变化自然续上
  Future<void> _drain(String? activeLedgerId) async {
    if (_pushing || !_active) return;
    _pushing = true;
    try {
      while (_active && _dirty) {
        _dirty = false;
        await pushWidgetPayloads(
          ref.read(repoProvider),
          ledgers: ref.read(ledgersProvider).value,
          hiddenIds: ref.read(hiddenEnvelopeIdsProvider),
          activeLedgerId: activeLedgerId,
        );
      }
    } finally {
      _pushing = false;
    }
  }
}

// 一次完整推送：全部账本的信封卡负载 + 图标位图 + 已配置统计卡实例数据。
// 主引擎的同步控制器与悬浮记账引擎（票 14 记账成功后一次性推送）共用；
// 依赖显式注入（不收 Ref——悬浮页手里是 WidgetRef，Riverpod 3 两者不通用）。
// 平台不可用（桌面调试 / 测试宿主）静默——下次变动会再推。
Future<void> pushWidgetPayloads(
  AppRepository repo, {
  List<db.Ledger>? ledgers,
  Set<String> hiddenIds = const <String>{},
  String? activeLedgerId,
}) async {
  try {
    final support = await getApplicationSupportDirectory();
    final payloads = <String, String>{};

    // ── 信封卡：全部账本的在用信封（组件绑定具体信封，切账本不影响）──
    final ledgerIds = (ledgers == null || ledgers.isEmpty)
        ? (activeLedgerId == null ? const <String>[] : [activeLedgerId])
        : ledgers.map((l) => l.id).toList();

    String? defaultId;
    for (final ledgerId in ledgerIds) {
      final envelopes = await repo.getEnvelopesOnce(ledgerId);
      final settings = await repo.getSettingsOnce(ledgerId);
      final symbol = settings?.currency ?? kDefaultCurrency;
      payloads.addAll(
        buildEnvelopeCardPayloads(
          envelopes: envelopes,
          symbol: symbol,
          hiddenIds: hiddenIds,
          defaultId: ledgerId == activeLedgerId && envelopes.isNotEmpty
              ? envelopes.first.id
              : null,
        ),
      );
      if (ledgerId == activeLedgerId &&
          defaultId == null &&
          envelopes.isNotEmpty) {
        defaultId = envelopes.first.id;
      }
      for (final e in envelopes) {
        final icon = await rasterizeEnvelopeIcon(
          iconId: e.icon,
          baseDir: support,
        );
        if (icon != null) payloads[EnvelopeCardKeys.icon(e.id)] = icon;
      }
    }

    // ── 统计卡：枚举实例，按各实例配置现算现画（票 09）──
    final widgets = await HomeWidget.getInstalledWidgets();
    final statsInstances = widgets
        .where(
          (w) =>
              w.androidWidgetId != null &&
              (w.androidClassName ?? '').contains('StatsWidgetProvider'),
        )
        .map((w) => w.androidWidgetId!)
        .toList();
    // 按账本缓存一次性读取（多张卡常共用同一账本）
    final txnsCache = <String, List<Txn>>{};
    final envsCache = <String, List<Envelope>>{};
    final symbolCache = <String, String>{};
    List<Txn> txnsOf(String id) => txnsCache[id] ??= [];
    List<Envelope> envsOf(String id) => envsCache[id] ??= [];
    String symbolOf(String id) =>
        symbolCache[id] ??= kDefaultCurrency;

    final now = DateTime.now();
    for (final widgetId in statsInstances) {
      final rangeStored = await HomeWidget.getWidgetData<String>(
        EnvelopeCardKeys.statsRange(widgetId),
      );
      if (rangeStored == null) continue; // 未配置：保持占位
      final range = WidgetStatsRangeX.parse(rangeStored);
      final chart = WidgetStatsChartX.parse(
        await HomeWidget.getWidgetData<String>(
          EnvelopeCardKeys.statsChart(widgetId),
        ),
      );
      final ledgerId =
          await HomeWidget.getWidgetData<String>(
            EnvelopeCardKeys.statsLedger(widgetId),
          ) ??
          activeLedgerId ??
          (ledgerIds.isEmpty ? null : ledgerIds.first);
      if (ledgerId == null) continue;
      txnsCache[ledgerId] = await repo.getTransactionsOnce(ledgerId);
      envsCache[ledgerId] = await repo.getEnvelopesOnce(ledgerId);
      symbolCache[ledgerId] =
          (await repo.getSettingsOnce(ledgerId))?.currency ?? kDefaultCurrency;

      final data = computeWidgetStats(
        range: range,
        txns: txnsOf(ledgerId),
        envelopes: envsOf(ledgerId),
        symbol: symbolOf(ledgerId),
        now: now,
      );
      final chartPath = await renderStatsChartBitmap(
        data: data,
        chart: chart,
        baseDir: support,
        widgetId: widgetId,
      );
      final barPath = await renderStatsProgressBar(
        progress: data.progress,
        baseDir: support,
        widgetId: widgetId,
      );
      payloads[EnvelopeCardKeys.statsLabel(widgetId)] = data.labelBase;
      final endMillis = data.endMillis;
      if (endMillis != null) {
        payloads[EnvelopeCardKeys.statsEndMillis(widgetId)] =
            '$endMillis';
      } else {
        // 滚动区间（近7日/近30日）没有倒计时——必须写空值覆盖旧键：
        // saveWidgetData 只写不清，切区间后残留的 end_millis 会让原生
        // 照旧拼「还剩 N 天」（261012 用户实测）
        payloads[EnvelopeCardKeys.statsEndMillis(widgetId)] = '';
      }
      payloads[EnvelopeCardKeys.statsPlanned(widgetId)] = data.plannedText;
      payloads[EnvelopeCardKeys.statsUsed(widgetId)] = data.usedText;
      payloads[EnvelopeCardKeys.statsLeft(widgetId)] = data.leftText;
      if (barPath != null) {
        payloads[EnvelopeCardKeys.statsBar(widgetId)] = barPath;
      }
      if (chartPath != null) {
        payloads[EnvelopeCardKeys.statsChartPath(widgetId)] = chartPath;
      }
    }

    for (final entry in payloads.entries) {
      await HomeWidget.saveWidgetData(entry.key, entry.value);
    }
    // qualifiedAndroidName 按 namespace 定位（debug 变体的 applicationId 带
    // .debug 后缀，androidName 拼包名会 ClassNotFound → 组件收不到更新）
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.example.enve_keeper_app.EnvelopeWidgetProvider',
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.example.enve_keeper_app.StatsWidgetProvider',
    );
    // 直调刷新双保险（票 12）：广播在 MIUI 上偶发不落地
    await refreshWidgetsDirect();
  } on Exception {
    // MissingPluginException 等：无桌面组件宿主的环境（测试 / 桌面调试）
    // 或推送失败——下次数据变动会再推，不值得打扰用户
  }
}

// 桌面小组件同步（_Boot watch 常驻）
final widgetSyncProvider = NotifierProvider<WidgetSyncController, bool>(
  WidgetSyncController.new,
);
