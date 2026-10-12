// 桌面小组件直调刷新（v1.3.0 票 12）：绕开 APPWIDGET_UPDATE 广播，
// 经平台通道直调原生 AppWidgetManager.updateAppWidget 重画两组件。
// 背景：MIUI/HyperOS 对广播有不可控的节流，编辑页保存配置后的广播偶发
// 不落地（换背景图迟迟不刷新）；binder 直调与广播路径并行双保险。
// 通道未注册（测试宿主 / 桌面调试）时静默——广播路径仍在。
import 'package:flutter/services.dart';

const MethodChannel _kWidgetRefreshChannel =
    MethodChannel('enve_keeper_app/widget_refresh');

/// 直调刷新全部已放置的信封卡与统计卡实例。
/// 失败（无通道 / 原生异常）返回 false，调用方不感知——广播路径兜底。
Future<bool> refreshWidgetsDirect() async {
  try {
    return await _kWidgetRefreshChannel.invokeMethod<bool>('refreshAll') ?? false;
  } on Exception {
    return false;
  }
}

/// 安装「外部数据变更」监听（主引擎装一次，app.dart _Boot 调）：
/// 悬浮记账引擎（票 14）在另一个 drift 连接上写库，原生侧中转 dataChanged
/// 到主引擎，这里强制主连接的全部 watch 流重查——否则主 App 回前台见旧余额。
void installExternalDataChangedHandler(void Function() onChanged) {
  _kWidgetRefreshChannel.setMethodCallHandler((call) async {
    if (call.method == 'dataChanged') onChanged();
  });
}
