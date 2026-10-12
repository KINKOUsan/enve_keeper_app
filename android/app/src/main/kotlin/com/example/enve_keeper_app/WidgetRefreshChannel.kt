package com.example.enve_keeper_app

import android.content.ComponentName
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 组件直调刷新通道（v1.3.0 票 12 / 票 14）：Dart → 原生直接调
 * `AppWidgetManager.updateAppWidget` 重画组件，不经 APPWIDGET_UPDATE 广播。
 * 背景：MIUI/HyperOS 对广播有不可控的节流/延迟表现，编辑页保存配置后
 * 「广播 → onUpdate」链路偶发不落地（260930 用户反馈换背景图迟迟不刷新；
 * 261011 真机实验证明冷启动推送链路通、但组件位图高达 2MB+，广播路径
 * 没有保障）。直调是 binder 调用，与广播路径并行双保险。
 *
 * MainActivity 与 QuickRecordActivity（票 14 悬浮记账）各装一份——
 * 两个引擎都能发起刷新。另承担双引擎中转：悬浮记账写库后
 * [notifyMainEngineDataChanged] 通知主引擎强制重查 drift 流。
 */
object WidgetRefreshChannel {

    private const val TAG = "EnveWidget"
    const val CHANNEL = "enve_keeper_app/widget_refresh"

    // 主引擎（MainActivity）引用：悬浮引擎写库后通知它刷新（票 14）。
    // 主引擎销毁时由 cleanUpFlutterEngine 清空。
    private var mainEngine: FlutterEngine? = null

    fun registerMainEngine(engine: FlutterEngine?) {
        mainEngine = engine
    }

    /** 悬浮记账写库后通知主引擎：另一连接的写入 drift 不自动感知。 */
    fun notifyMainEngineDataChanged() {
        val engine = mainEngine ?: return
        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("dataChanged", null)
        } catch (e: Exception) {
            // 引擎正在销毁等：通知落空无碍——主 App 下次打开冷启动自然读新数据
        }
    }

    fun install(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refreshAll" -> {
                        try {
                            EnvelopeWidgetProvider.pushAll(context.applicationContext)
                            StatsWidgetProvider.pushAll(context.applicationContext)
                            Log.d(TAG, "refreshAll: direct update dispatched")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.w(TAG, "refreshAll failed: ${e.message}")
                            result.error("refresh_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
