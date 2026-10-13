package com.example.enve_keeper_app

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * 小组件点击的统一启动构造（v1.3.2 修订）：主界面深链 PendingIntent。
 *
 * ⚠️ 不用 home_widget 的 HomeWidgetLaunchIntent.getActivity——它不带任何
 * 启动旗子，桌面代为启动时走冷启动还是热路径全看各厂商桌面习惯。配合
 * 清单里 MainActivity 的正常 affinity + 此处显式 NEW_TASK|SINGLE_TOP：
 * 永远唤起同一个窗口走 onNewIntent 热路径（Flutter 侧 3 秒去重兜底）。
 * 此前 MainActivity 曾声明 taskAffinity=""（无户口），按 affinity 归位的
 * 启动找不到老任务，点一次开一个新窗口、各带一套页面记录——后台多窗口
 * 与「点统计卡串回编辑页」的根源（261013 真机定位）。
 *
 * Android 14+ 组件点击属后台启动场景，需放开
 * backgroundActivityStartMode（home_widget 同款处理）。
 */
object WidgetLaunchIntents {

    fun mainActivityPendingIntent(context: Context, uri: Uri): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = uri
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
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
}
