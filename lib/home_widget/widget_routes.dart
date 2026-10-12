// 桌面小组件的点击路由（v1.3.0 票 06/07 / ADR-0021）：
// Android 不允许把应用界面画到桌面，点组件 = 带 URI 启动 MainActivity，
// Flutter 侧解析后分流——「快速记账」直达该信封的数字键盘（CONTEXT.md
// 术语），「编辑组件」推入实例编辑页，「看统计」切到统计 Tab（票 15）。
// URI 约定与原生侧一致：
//   envekeeper://quick-record?env=<信封id>
//   envekeeper://widget-edit?id=<appWidgetId>
//   envekeeper://open-stats
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../ui/common/app_route.dart';
import '../ui/keypad/keypad_flow.dart';
import '../ui/keypad/keypad_models.dart';
import '../ui/shell/widgets/widget_edit_page.dart';

// URI 方案
const _kScheme = 'envekeeper';
const _kQuickRecordHost = 'quick-record';
const _kWidgetEditHost = 'widget-edit';
const _kOpenStatsHost = 'open-stats';

/// 解析后的组件点击路由
sealed class WidgetRoute {
  const WidgetRoute();
}

/// 快速记账：直达该信封的数字键盘
class WidgetQuickRecord extends WidgetRoute {
  const WidgetQuickRecord(this.envelopeId);
  final String envelopeId;
}

/// 编辑组件：进实例编辑页
class WidgetEditRoute extends WidgetRoute {
  const WidgetEditRoute(this.widgetId);
  final int widgetId;
}

/// 看统计：切到统计 Tab（票 15）
class WidgetStatsRoute extends WidgetRoute {
  const WidgetStatsRoute();
}

/// 解析组件点击 URI；不是本 App 的组件路由返回 null
WidgetRoute? parseWidgetUri(Uri? uri) {
  if (uri == null || !uri.hasScheme || uri.scheme != _kScheme) return null;
  if (uri.host == _kQuickRecordHost) {
    final env = uri.queryParameters['env'];
    if (env == null || env.isEmpty) return null;
    return WidgetQuickRecord(env);
  }
  if (uri.host == _kWidgetEditHost) {
    final id = int.tryParse(uri.queryParameters['id'] ?? '');
    if (id == null) return null;
    return WidgetEditRoute(id);
  }
  if (uri.host == _kOpenStatsHost) {
    return const WidgetStatsRoute();
  }
  return null;
}

/// 安装小组件点击的常驻分发（AppShell initState 调一次）：
/// - 冷启动：读 launch intent 里的 URI（initiallyLaunchedFromHomeWidget）；
/// - 热启动：widgetClicked 流（onNewIntent）。
/// 返回取消订阅句柄（AppShell dispose 调用）。
StreamSubscription<Uri?> installWidgetRouteDispatcher(
  BuildContext context,
  WidgetRef ref,
  void Function(WidgetRoute route) onRoute,
) {
  // 冷启动：本进程的 launch intent 上有 URI 就处理一次
  unawaited(
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      final route = parseWidgetUri(uri);
      if (route != null && context.mounted) onRoute(route);
    }).catchError((Object _) {}),
  );
  // 热启动：应用存活期间组件点击经 onNewIntent 进流
  // （测试宿主 / 桌面调试没有该通道：错误静默）
  return HomeWidget.widgetClicked.listen(
    (uri) {
      final route = parseWidgetUri(uri);
      if (route != null && context.mounted) onRoute(route);
    },
    onError: (Object _) {},
  );
}

/// 执行一条组件路由（AppShell 的回调里调用）
Future<void> runWidgetRoute(
  BuildContext context,
  WidgetRef ref,
  WidgetRoute route,
) async {
  switch (route) {
    case WidgetStatsRoute():
      // AppShell 直接切 Tab，不走这里（exhaustiveness 占位）
      return;

    case WidgetEditRoute(:final widgetId):
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => WidgetEditPage(widgetId: widgetId),
        ),
      );

    case WidgetQuickRecord(:final envelopeId):
      // 该信封不在当前账本（或不存在）时：找到归属账本先切换，找不到则忽略
      final envs = ref.read(envelopesProvider).value ?? const <Envelope>[];
      if (!envs.any((e) => e.id == envelopeId)) {
        final switched = await ensureEnvelopeReachable(ref, envelopeId);
        if (!switched || !context.mounted) return;
      }
      if (!context.mounted) return;
      await runKeypadFlow(
        context,
        ref,
        KeypadRequest(action: KeypadAction.expense, envelopeId: envelopeId),
      );
  }
}

/// 跨账本兜底（widget 点击路由与悬浮记账共用，票 14）：组件绑定的信封属于
/// 别的账本 → 切到那个账本并等它的信封流追上来（否则键盘标题会短暂显示
/// 「未知信封」）。信封不存在或切换失败返回 false。
Future<bool> ensureEnvelopeReachable(WidgetRef ref, String envelopeId) async {
  try {
    final repo = ref.read(repoProvider);
    final row = await repo.getEnvelopeRow(envelopeId);
    final active = ref.read(activeLedgerProvider);
    if (active?.id == row.ledgerId) return true;
    await ref.read(activeLedgerIdProvider.notifier).set(row.ledgerId);
    // 等在用信封流吐出该信封（2 秒兜底超时）
    final done = Completer<void>();
    bool has(List<Envelope> list) => list.any((e) => e.id == envelopeId);
    final current = ref.read(envelopesProvider).value;
    if (current != null && has(current)) return true;
    final sub = ref.listenManual<AsyncValue<List<Envelope>>>(
      envelopesProvider,
      (_, next) {
        final v = next.value;
        if (v != null && has(v) && !done.isCompleted) done.complete();
      },
    );
    try {
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    } finally {
      sub.close();
    }
    return true;
  } on Exception {
    // 信封不存在（getSingle 落空等）：当无事发生
    return false;
  }
}
