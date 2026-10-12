// 悬浮快速记账浮层（v1.3.0 票 14 / ADR-0021 增补）：点桌面信封卡不进 App——
// 原生透明 Activity 的窗口背景即半透明黑遮罩（点下立刻可见，先于 Flutter
// 首帧），本页只画键盘：复用 runKeypadFlow 全链路（提交 / 兜底描述 / 提示）。
// 记完（或取消）浮层即关回桌面。与主 App 同进程双引擎：
// - 本引擎只做记账最小装配，不启 autoBackup / 常驻组件同步控制器
//   （双引擎各跑一份会双推送、双备份）；
// - 记账成功 → 一次性推送组件负载 + 直调刷新（组件秒同步）→ 原生中转
//   通知主引擎重查 drift 流（跨连接写库主引擎不自动感知）→ 系统级 toast
//   飘在桌面 → finish 回桌面；
// - 自动备份由主 App 下次打开时追平（备份触发读流变化，重启即补）。
// 绑定信封丢失 / 引擎装配失败 → 回退打开 App 的组件编辑页（旧路径）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home_widget/widget_refresh.dart';
import '../../../home_widget/widget_routes.dart'
    show ensureEnvelopeReachable;
import '../../../home_widget/widget_sync.dart';
import '../../../state/providers.dart';
import '../../../theme/theme.dart';
import '../../keypad/keypad_flow.dart';
import '../../keypad/keypad_models.dart';

const MethodChannel _kOverlayChannel =
    MethodChannel('enve_keeper_app/quick_record');

// 浮层根：带本地化的 MaterialApp（SnackBar / 弹层需要中文本地化）
class QuickRecordOverlayApp extends StatelessWidget {
  const QuickRecordOverlayApp({
    super.key,
    required this.envelopeId,
    this.widgetId,
  });

  final String? envelopeId;

  // 发起点击的 appWidgetId（URI w= 参数）：信封丢失回退时直达该实例编辑页
  final int? widgetId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金打细算',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 引擎初始路由是 deep link URI（QuickRecordActivity 透传），WidgetsApp
      // 会拿它当初始路由找不到对应页——参数已在 main() 拆成构造入参，
      // 这里钉死 '/' 走 home（app.dart:1427 同款回退行为的反制）
      initialRoute: '/',
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: QuickRecordOverlayPage(
        envelopeId: envelopeId,
        widgetId: widgetId,
      ),
    );
  }
}

class QuickRecordOverlayPage extends ConsumerStatefulWidget {
  const QuickRecordOverlayPage({
    super.key,
    required this.envelopeId,
    this.widgetId,
  });

  final String? envelopeId;

  final int? widgetId;

  @override
  ConsumerState<QuickRecordOverlayPage> createState() =>
      _QuickRecordOverlayPageState();
}

class _QuickRecordOverlayPageState
    extends ConsumerState<QuickRecordOverlayPage> {
  // 键盘流程的成功文案（转系统级 toast 用——浮层关闭后仍飘在桌面）
  String _lastToast = '';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  // 浮层主流程：等账本就绪 → 信封可达 → 键盘 → 收尾。
  // 任何装配失败都回退打开 App；正常结束（提交或取消）直接关浮层。
  // 调试构建引擎+库点火慢（2–10 秒，发布版亚秒），超时给足 15 秒——
  // 期间遮罩已盖住桌面（原生层先画），只是键盘出现晚。
  Future<void> _run() async {
    final envId = widget.envelopeId;
    final sw = Stopwatch()..start();
    if (envId == null || envId.isEmpty) {
      _fallbackEdit();
      return;
    }
    try {
      // 等账本流吐出首帧（数据库直查亚秒即通；15 秒兜底防永久卡死）
      await ref
          .read(ledgersProvider.future)
          .timeout(const Duration(seconds: 15));
      debugPrint('── 浮层 step1 账本就绪 ${sw.elapsedMilliseconds}ms');
      if (ref.read(activeLedgerProvider) == null) {
        _fallbackRecord(envId);
        return;
      }
      // 信封归属别的账本时浮层内自动切换；信封不存在 → 打开编辑页重绑
      if (!await ensureEnvelopeReachable(ref, envId)) {
        debugPrint('── 浮层 step2 信封不可达 ${sw.elapsedMilliseconds}ms');
        _fallbackEdit();
        return;
      }
      debugPrint('── 浮层 step2 信封可达 ${sw.elapsedMilliseconds}ms');
      if (!mounted) return;
      final ok = await runKeypadFlow(
        context,
        ref,
        KeypadRequest(action: KeypadAction.expense, envelopeId: envId),
        onToast: (message) => _lastToast = message,
      );
      debugPrint('── 浮层 step3 键盘结束 ok=$ok ${sw.elapsedMilliseconds}ms');
      if (ok) {
        // 一次性推组件负载（本引擎没有常驻同步控制器）+ 直调刷新
        await pushWidgetPayloads(
          ref.read(repoProvider),
          ledgers: ref.read(ledgersProvider).value,
          hiddenIds: ref.read(hiddenEnvelopeIdsProvider),
          activeLedgerId: ref.read(activeLedgerProvider)?.id,
        );
        await refreshWidgetsDirect();
      }
      if (!mounted) return;
      unawaited(
        _kOverlayChannel.invokeMethod<void>(
          ok ? 'finishAfterSave' : 'finish',
          ok ? _lastToast : null,
        ),
      );
    } on Exception catch (e) {
      // 引擎装配失败（超时/读库异常）：带信封 id 回退开 App 内键盘（旧路径）
      debugPrint('── 浮层装配失败 ${sw.elapsedMilliseconds}ms：$e');
      _fallbackRecord(envId);
    }
  }

  // 装配失败兜底：打开主 App 在应用内弹该信封的键盘（旧快速记账路径）
  void _fallbackRecord(String envId) {
    unawaited(
      _kOverlayChannel
          .invokeMethod<void>('fallbackRecord', envId)
          .catchError((Object _) {}),
    );
  }

  // 信封丢失兜底：打开该实例的编辑页（重新绑定）
  void _fallbackEdit() {
    unawaited(
      _kOverlayChannel
          .invokeMethod<void>('fallbackEdit', widget.widgetId)
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 悬挂保险（261011 真机定位）：_run 里全是 ref.read——Riverpod 3 没有监听
    // 者的 provider 会被回收，drift 流订阅随之取消、首帧永远不来，
    // ledgersProvider.future 就此挂死（主引擎因 UI 全程 watch 而无此问题）。
    // 页面级 watch 让账本/激活账本/设置/信封流在浮层存活期内不回收。
    ref.watch(ledgersProvider);
    ref.watch(activeLedgerProvider);
    ref.watch(settingsProvider);
    ref.watch(envelopesProvider);
    return PopScope(
      // 系统返回键 = 取消浮层（有键盘弹层时由键盘自己的返回处理先接管）
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(
            _kOverlayChannel.invokeMethod<void>('finish').catchError(
                  (Object _) {},
                ),
          );
        }
      },
      // 遮罩由原生窗口背景画；这里全屏透明手势垫在键盘下面——
      // 键盘弹出前的准备阶段（冷启动约 1 秒）点遮罩即可取消
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(
            _kOverlayChannel.invokeMethod<void>('finish').catchError(
                  (Object _) {},
                ),
          );
        },
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox.expand(),
        ),
      ),
    );
  }
}
