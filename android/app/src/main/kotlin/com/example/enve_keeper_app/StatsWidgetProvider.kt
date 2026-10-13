package com.example.enve_keeper_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File
import kotlin.math.ceil
import kotlin.math.max

/**
 * 统计卡片（v1.3.0 票 09 / ADR-0021）：4×2 桌面组件。
 * 布局：区间标签（含「还剩 N 天」）+ 可视化位图（Flutter 预渲染的环形/柱状图）
 * + 数字摘要三数 + 执行进度条位图（同为预渲染 PNG）。数字与位图由 Flutter
 * 同步控制器按实例配置现算现推（sw.<id>.* 键）；本类只排版显示。
 *
 * 「还剩 N 天」在原生侧按到期毫秒现算：updatePeriodMillis 定期触发 onUpdate，
 * 跨天后不开 App 也会更新（ADR-0021 的兜底刷新）。
 *
 * 实例配置键：statsRange_<id>（'week'|'month'|'last30'|'year'，缺省 = 未配置占位）、
 * statsChart_<id>（'ring'|'bars'）、statsLedger_<id>；共用外观键见 WidgetStyleHelper。
 */
class StatsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // 行车记录仪（票 12 追踪「图片偶发不更新」）
        android.util.Log.d("EnveWidget", "stats onUpdate ids=${appWidgetIds.joinToString()}")
        val data = HomeWidgetPlugin.getData(context)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, render(context, data, id))
        }
    }

    /** 渲染一个实例：已配置且有数据走数据态，否则占位态 */
    private fun render(
        context: Context,
        data: SharedPreferences,
        widgetId: Int,
    ): RemoteViews {
        // 票 16：阴影恒开，布局统一用 stats_widget（已并入阴影属性）
        val views = RemoteViews(
            context.packageName,
            R.layout.stats_widget,
        )
        val configured = data.getString("statsRange_$widgetId", null) != null
        val planned = data.getString("sw.$widgetId.planned", null)

        if (!configured || planned == null) {
            // 占位态：暖浅底 + 「未配置」+ 一行提示，数字区/图表/进度隐藏
            WidgetStyleHelper.apply(
                views, data, widgetId, "#F0E8DB",
                intArrayOf(R.id.label, R.id.v0, R.id.v1, R.id.v2),
                bgMaxLongSide = 540,
            )
            views.setTextViewText(
                R.id.label,
                context.getString(R.string.envelope_widget_placeholder_title),
            )
            views.setTextColor(R.id.label, Color_GreyText)
            views.setViewVisibility(R.id.chart, View.GONE)
            views.setViewVisibility(R.id.progress, View.GONE)
            views.setViewVisibility(R.id.l0, View.GONE)
            views.setViewVisibility(R.id.v0, View.GONE)
            views.setViewVisibility(R.id.v1, View.GONE)
            views.setViewVisibility(R.id.v2, View.GONE)
            views.setViewVisibility(R.id.l2, View.GONE)
            views.setTextViewText(
                R.id.l1,
                context.getString(R.string.envelope_widget_placeholder_hint),
            )
            views.setTextColor(R.id.l1, Color_GreyText)
            views.setOnClickPendingIntent(
                R.id.root,
                WidgetLaunchIntents.mainActivityPendingIntent(
                    context,
                    Uri.parse("envekeeper://widget-edit?id=$widgetId"),
                ),
            )
            return views
        }

        // 数据态：中性暖灰底（统计卡没有信封主题色）
        WidgetStyleHelper.apply(
            views, data, widgetId, "#8A8278",
            intArrayOf(R.id.label, R.id.v0, R.id.v1, R.id.v2),
            // 540 同信封卡：ColorOS 桌面位图红线，bg+图表总量实测 1.73MB 可达
            bgMaxLongSide = 540,
        )
        views.setViewVisibility(R.id.l0, View.VISIBLE)
        views.setViewVisibility(R.id.l1, View.VISIBLE)
        views.setViewVisibility(R.id.l2, View.VISIBLE)

        // 区间标签：「本周 · 还剩 3 天」——天数按到期毫秒现算（跨天自动更新）
        val base = data.getString("sw.$widgetId.label", null) ?: ""
        val endMillis = data.getString("sw.$widgetId.end_millis", null)?.toLongOrNull()
        val label = if (endMillis == null) {
            base // 滚动区间（近30日）没有倒计时
        } else {
            val days = max(0, ceil((endMillis - System.currentTimeMillis()) / 86_400_000.0).toInt())
            "$base · 还剩 $days 天"
        }
        views.setTextViewText(R.id.label, label)

        // 数字摘要三数 + 执行进度（预渲染 PNG；位图解码而非 setImageViewUri——
        // file:// URI 会触发 FileUriExposedException，见 WidgetStyleHelper 注释）
        views.setTextViewText(R.id.v0, planned)
        views.setTextViewText(R.id.v1, data.getString("sw.$widgetId.used", null) ?: "")
        views.setTextViewText(R.id.v2, data.getString("sw.$widgetId.left", null) ?: "")
        val barPath = data.getString("sw.$widgetId.bar", null)
        val bar = barPath?.let { File(it) }?.takeIf { it.exists() }
            ?.let { WidgetStyleHelper.decodeScaled(it, maxLongSide = 800) }
        if (bar != null) {
            views.setImageViewBitmap(R.id.progress, bar)
            views.setViewVisibility(R.id.progress, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.progress, View.GONE)
        }

        // 可视化位图（环形/柱状，Flutter 预渲染推送的文件路径）
        val chartPath = data.getString("sw.$widgetId.chart", null)
        val chart = chartPath?.let { BitmapFactory.decodeFile(it) }
        if (chart != null) {
            views.setImageViewBitmap(R.id.chart, chart)
            views.setViewVisibility(R.id.chart, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.chart, View.GONE)
        }

        // 点击：进 App 统计页（票 15，深链 open-stats 由 AppShell 切 Tab）；
        // 占位态上方已单独挂 widget-edit
        views.setOnClickPendingIntent(
            R.id.root,
            WidgetLaunchIntents.mainActivityPendingIntent(
                context,
                Uri.parse("envekeeper://open-stats"),
            ),
        )
        return views
    }

    companion object {
        private const val Color_GreyText = 0xFF8A8278.toInt()

        /** 直调刷新（票 12）：同 EnvelopeWidgetProvider.pushAll。 */
        fun pushAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, StatsWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            StatsWidgetProvider().onUpdate(context, manager, ids)
        }
    }
}
