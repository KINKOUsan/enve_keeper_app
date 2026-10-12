package com.example.enve_keeper_app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 悬浮快速记账浮层（v1.3.0 票 14 / ADR-0021 增补）：点信封卡不进 App——
 * 透明 Activity 盖在桌面上，窗口背景即半透明黑遮罩（点下立刻可见，先于
 * Flutter 首帧），Flutter 侧复用数字键盘，记完即关回桌面。
 *
 * 双引擎：与 MainActivity 同进程、各自持引擎。本引擎只跑记账最小装配
 * （repo + providers，main() 按初始路由分流），不启 autoBackup / 常驻
 * 组件同步。Flutter 侧经本类的通道收尾：
 * - finishAfterSave(toast)：记账成功 → 系统级 toast 飘在桌面 → 通知主引擎
 *   刷新 drift 流（跨连接写入不自动感知）→ finish；
 * - finish：取消 / 无动作直接关；
 * - openApp(widgetId)：绑定信封丢失等异常 → 回退打开 App（有 widgetId
 *   直达该实例编辑页），经票 11 的深链暗号。
 */
class QuickRecordActivity : FlutterActivity() {

    // 全透明：Flutter 未画到的区域露出窗口背景（原生遮罩）
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // 组件点进来的 URI（envekeeper://quick-record?env=<id>&w=<appWidgetId>）
    // 透传为 Flutter 初始路由，main() 据此进入悬浮模式
    override fun getInitialRoute(): String? {
        val route = intent?.data?.toString()
        Log.d(TAG, "getInitialRoute -> $route (action=${intent?.action})")
        return route
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 引擎在 BackgroundMode.transparent 时会把窗口背景刷成全透明
        // （configureWindowForTransparency，261011 真机：遮罩整层消失、
        // 「点了没反应」）——在它之后补回遮罩，冷启动点火期间也有
        // 「遮罩先盖下来」的体感
        window.setBackgroundDrawable(
            android.graphics.drawable.ColorDrawable(getColor(R.color.quick_record_scrim)),
        )
        Log.d(TAG, "onCreate data=${intent?.data} component=$componentName")
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "onUserLeaveHint")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine")
        WidgetRefreshChannel.install(flutterEngine, applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "channel <- ${call.method} ${call.arguments}")
                when (call.method) {
                    "initialIntentData" -> {
                        result.success(intent?.data?.toString())
                    }
                    "finishAfterSave" -> {
                        val toast = call.arguments as? String
                        if (!toast.isNullOrEmpty()) {
                            Toast.makeText(applicationContext, toast, Toast.LENGTH_SHORT).show()
                        }
                        WidgetRefreshChannel.notifyMainEngineDataChanged()
                        result.success(true)
                        finish()
                    }
                    "finish" -> {
                        result.success(true)
                        finish()
                    }
                    // 装配失败兜底（票 14 修订）：带上信封 id 回退打开主 App——
                    // 走旧路径在 App 内弹键盘（用户至少能记账），而非干巴巴的编辑页
                    "fallbackRecord" -> {
                        openMainWithDeepLink(
                            "envekeeper://quick-record?env=${call.arguments as? String ?: ""}",
                        )
                        result.success(true)
                    }
                    // 绑定信封丢失：打开该实例编辑页（重新绑定）
                    "fallbackEdit" -> {
                        openMainWithDeepLink("envekeeper://widget-edit?id=${call.arguments as? Int ?: 0}")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openMainWithDeepLink(uri: String) {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = Uri.parse(uri)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            },
        )
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTask：浮层已开时再点组件 → 换 intent 但不打断当前键盘
        // （极边缘场景：连续点两张不同的卡。收掉上层后旧浮层仍在）
        Log.d(TAG, "onNewIntent data=${intent.data}")
        setIntent(intent)
    }

    companion object {
        private const val TAG = "EnveOverlay"
        const val CHANNEL = "enve_keeper_app/quick_record"
        const val ACTION_QUICK_RECORD =
            "com.example.enve_keeper_app.action.QUICK_RECORD"
    }
}
