package com.example.enve_keeper_app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * 小组件配置入口（v1.3.0 票 07 / 票 11 修复）：无界面的中转 Activity。
 * - Android 12+ 长按组件「重新配置」→ 系统启动本类 → 转 MainActivity 打开
 *   应用内编辑页（envekeeper://widget-edit）。
 * - Android 11 及以下添加组件时系统会强制先启动配置入口：本类立刻回 OK
 *   （让占位态组件先落桌面，符合「先占位、点按进编辑」的设计），同时仍
 *   打开编辑页方便当场完成绑定。
 *
 * 票 11：启动 MainActivity 必须带 home_widget 的
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

        // 先回 OK：添加流程不返回 OK 的话组件会被系统删掉
        if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
            setResult(
                RESULT_OK,
                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
            )
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
        } else {
            setResult(RESULT_CANCELED)
        }
        finish()
    }
}
