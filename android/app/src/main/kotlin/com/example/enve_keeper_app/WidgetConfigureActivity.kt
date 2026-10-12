package com.example.enve_keeper_app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 小组件配置入口（v1.3.0 票 07 / 票 11 / v1.3.1 ColorOS 修复）：无界面的中转 Activity。
 * - 长按已配置组件「重新配置」→ 系统启动本类 → 转 MainActivity 打开
 *   应用内编辑页（envekeeper://widget-edit）。
 * - 首次添加：只回 RESULT_OK 让组件立即落桌，**不再拉起 App**。桌面添加
 *   流程是「绑定 → 启动配置入口 → 等结果 → 落桌放置」，ColorOS 桌面会无视
 *   reconfigurable 强制走本入口，且容不得流程被打断：本类秒退的同时把
 *   MainActivity（新任务）推到前台，落桌动作被截断——组件绑定成功却永不
 *   显示（v1.3.0+7 ColorOS 用户实测：点添加进编辑页、保存后桌面没有）。
 *   占位/兜底组件本就「点按进编辑页」（票 06/07），当场编辑改由点组件触发。
 *
 * 「首次添加 vs 重新配置」的判据：Flutter 侧保存过实例配置会写
 * `binding_<id>`（信封卡）/ `statsRange_<id>`（统计卡）等键，appWidgetId
 * 由系统单调分配永不复用——存在任一 `_<id>` 结尾的键即视为重新配置。
 *
 * 票 11：重新配置时启动 MainActivity 必须带 home_widget 的
 * `HOME_WIDGET_LAUNCH_ACTION`——插件的深链分发（冷启动
 * `initiallyLaunchedFromHomeWidget` / 热启动 `widgetClicked` 流）只认这个
 * action，用普通 `ACTION_VIEW` 会被插件丢弃，URI 传不到 Flutter 侧
 * （260930 真机：长按编辑只开 App 首页）。NEW_TASK|CLEAR_TOP|SINGLE_TOP
 * 保证 App 存活时走 onNewIntent 热路径，不叠出第二个 MainActivity 实例
 * （双实例 = 双引擎双 drift 连接）。
 */
class WidgetConfigureActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
            // 先回 OK：添加流程不返回 OK 的话组件会被系统删掉
            setResult(
                RESULT_OK,
                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
            )
            // 重新配置（实例已有配置键）才拉起编辑页；首次添加到此为止，
            // 让桌面先把组件落完桌再谈别的（ColorOS 修复，见类注释）
            val configured = HomeWidgetPlugin.getData(this)
                .all.keys.any { it.endsWith("_$id") }
            if (configured) {
                startActivity(
                    Intent(this, MainActivity::class.java).apply {
                        action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                        data = Uri.parse("envekeeper://widget-edit?id=$id")
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        )
                    },
                )
            }
        } else {
            setResult(RESULT_CANCELED)
        }
        finish()
    }
}
