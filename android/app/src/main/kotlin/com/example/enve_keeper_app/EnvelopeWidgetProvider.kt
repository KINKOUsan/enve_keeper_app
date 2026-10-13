package com.example.enve_keeper_app

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 信封卡片（v1.3.0 票 05–07 / ADR-0021）：2×2 桌面组件。
 * 数据由 Flutter 侧在每次变动后推送（home_widget 的 HomeWidgetPreferences），
 * 本类只做排版显示，不含任何业务逻辑；未配置 / 找不到数据时显示占位态。
 *
 * 点击（票 06「快速记账」：Android 画不了应用界面，点组件 = 带 URI 启动
 * MainActivity，Flutter 侧直达该信封的数字键盘）：
 * - 已配置：envekeeper://quick-record?env=<信封id>
 * - 未配置 / 停用：envekeeper://widget-edit?id=<appWidgetId>
 *
 * 实例级配置（票 07）：binding_<id> / fgColor_<id> / shadow_<id> / bg_<id>，
 * 键名与 Flutter 侧 lib/home_widget/widget_payload.dart 约定一致。
 *
 * ⚠️ 设文本必须用官方具名 API `setTextViewText`：泛型 `setString(id,"setText",..)`
 * 在 Android 16 上按 setText(String) 精确签名反射，而 MIUI 桌面把 TextView 换成
 * 自家 HomeMIUIWidgetTextView、TextView 家族没有 setText(String) —— 反射失败，
 * 桌面显示「载入窗口小部件时出现问题」（260929 真机定位）。
 */
class EnvelopeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // 行车记录仪（票 12 追踪「图片偶发不更新」）：确认更新是否到达渲染层
        android.util.Log.d("EnveWidget", "envelope onUpdate ids=${appWidgetIds.joinToString()}")
        val data = HomeWidgetPlugin.getData(context)
        for (id in appWidgetIds) {
            // 绑定优先级：实例级绑定键 → 默认兜底（第一个信封）
            val binding = data.getString("binding_$id", null)
                ?: data.getString(KEY_DEFAULT, null)
            appWidgetManager.updateAppWidget(id, render(context, data, id, binding))
        }
    }

    /** 渲染一个实例：有数据走配置态，否则占位态 */
    private fun render(
        context: Context,
        data: SharedPreferences,
        widgetId: Int,
        binding: String?,
    ): RemoteViews {
        val name = binding?.let { data.getString("envelope.$it.name", null) }

        // 渲染一个实例：有数据走配置态，否则占位态。
        // 票 16：阴影恒开，布局统一用 envelope_widget（已并入阴影属性）
        val views = RemoteViews(
            context.packageName,
            R.layout.envelope_widget,
        )

        if (binding == null || name == null) {
            // 占位态：暖浅底 + 「未配置」，金额与图标隐藏；点击进编辑页（票 07）
            WidgetStyleHelper.apply(
                views, data, widgetId, "#F0E8DB",
                intArrayOf(R.id.name, R.id.amount, R.id.hint),
                // 540 做实（≈1.2MB）：ColorOS 桌面对单次更新位图有红线，
                // 4.2MB 整包被拒、1.2MB 实测可达（见 WidgetStyleHelper 注释）
                bgMaxLongSide = 540,
            )
            views.setTextViewText(
                R.id.name,
                context.getString(R.string.envelope_widget_placeholder_title),
            )
            views.setTextColor(R.id.name, Color.parseColor("#8A8278"))
            views.setViewVisibility(R.id.amount, View.GONE)
            views.setViewVisibility(R.id.icon, View.GONE)
            views.setTextViewText(
                R.id.hint,
                context.getString(R.string.envelope_widget_placeholder_hint),
            )
            views.setViewVisibility(R.id.hint, View.VISIBLE)
            views.setOnClickPendingIntent(
                R.id.root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("envekeeper://widget-edit?id=$widgetId"),
                ),
            )
            return views
        }

        // 配置态：信封主题色底（或背景图）+ 图标 / 信封名 / 剩余金额；点击快速记账（票 06）
        WidgetStyleHelper.apply(
            views, data, widgetId,
            data.getString("envelope.$binding.color", null) ?: "#C77D70",
            intArrayOf(R.id.name, R.id.amount, R.id.hint),
            // 同上：540 做实保交付
            bgMaxLongSide = 540,
        )
        views.setTextViewText(R.id.name, name)
        views.setViewVisibility(R.id.name, View.VISIBLE)
        views.setViewVisibility(R.id.hint, View.GONE)

        views.setTextViewText(
            R.id.amount,
            data.getString("envelope.$binding.amount", null) ?: "",
        )
        views.setViewVisibility(R.id.amount, View.VISIBLE)

        // 图标位图由 Flutter 侧预渲染（ADR-0021：图形预渲染成图片推送）
        val iconPath = data.getString("envelope.$binding.icon", null)
        val icon = iconPath?.let { BitmapFactory.decodeFile(it) }
        if (icon != null) {
            views.setImageViewBitmap(R.id.icon, icon)
            views.setViewVisibility(R.id.icon, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.icon, View.GONE)
        }
        views.setOnClickPendingIntent(
            R.id.root,
            quickRecordPendingIntent(context, binding),
        )
        return views
    }

    companion object {
        private const val KEY_DEFAULT = "envelope.default"

        /**
         * 快速记账的点击 PendingIntent（票 14）：直指透明浮层
         * QuickRecordActivity——点下先见遮罩浮层，不把 App 拉到前台。
         * URI 带 env（信封 id）与 w（appWidgetId，异常回退直达编辑页）。
         * Android 14+ 组件点击属后台启动场景，需放开
         * backgroundActivityStartMode（home_widget 同款处理）。
         */
        fun quickRecordPendingIntent(context: Context, envelopeId: String): PendingIntent {
            val intent = Intent(context, QuickRecordActivity::class.java).apply {
                action = QuickRecordActivity.ACTION_QUICK_RECORD
                data = Uri.parse("envekeeper://quick-record?env=$envelopeId")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                return PendingIntent.getActivity(context, 0, intent, flags)
            }
            val options = ActivityOptions.makeBasic()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                options.setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                )
            } else {
                options.pendingIntentBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }
            return PendingIntent.getActivity(context, 0, intent, flags, options.toBundle())
        }

        /**
         * 直调刷新（票 12）：不经广播，直接对本 Provider 的全部实例跑一遍
         * onUpdate 渲染并 updateAppWidget——binder 直调，绕开 MIUI 广播节流。
         * 编辑页保存配置后由 WidgetRefreshChannel 调用。
         */
        fun pushAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, EnvelopeWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            EnvelopeWidgetProvider().onUpdate(context, manager, ids)
        }
    }
}
