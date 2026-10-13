package com.example.enve_keeper_app

import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.widget.RemoteViews
import java.io.File
import kotlin.math.roundToInt

/**
 * 小组件共用外观应用（v1.3.0 票 08/09 / 票 16）：背景图与字体颜色。
 * 两类组件（信封卡片 / 统计卡片）的实例级键名一致：
 * bg_<id> / fgColor_<id>（与 Flutter 侧 widget_payload.dart 对应）。
 * 票 16：文字底衬（scrim）移除——其固定 18dp 圆角与背景图按比例的圆角
 * 不一致会从角上溢出；可读性由恒开的文字阴影保证（布局层），阴影不再是
 * 开关项（shadow_<id> 键与双布局变体机制一并作废）。
 *
 * ⚠️ 图片一律走 setImageViewBitmap + 降采样解码：setImageViewUri(file://…) 会触发
 * FileUriExposedException（Android 7+ StrictMode 禁止 file URI 跨进程暴露，
 * 260929 真机闪退定位）；content URI 又需要跨进程读授权，桌面侧不保证配合。
 */
object WidgetStyleHelper {

    /// 应用背景与字色到已构造好的 [views]。
    /// [defaultBgColor] 为无背景图时的底色（信封主题色 / 统计卡默认色）；
    /// [textViewIds] 为需要着色的文本视图；[bgMaxLongSide] 控制背景图解码
    /// 体积（票 12：RemoteViews 位图太大是 MIUI 桌面吞更新的风险点——
    /// 信封卡显示尺寸小，540 足够；统计卡 4×2 面积大，保 720）。
    fun apply(
        views: RemoteViews,
        data: SharedPreferences,
        widgetId: Int,
        defaultBgColor: String,
        textViewIds: IntArray,
        bgMaxLongSide: Int = 720,
    ) {
        val bgFile = data.getString("bg_$widgetId", null)
            ?.let(::File)
            ?.takeIf { it.exists() }
        // 行车记录仪：bg 键与文件是否对上（不存在/丢失会回落主题色底）
        android.util.Log.d(
            "EnveWidget",
            "apply wid=$widgetId bg=${bgFile?.name ?: data.getString("bg_$widgetId", null) ?: "none"}",
        )
        val bg = bgFile?.let { decodeScaled(it, maxLongSide = bgMaxLongSide) }
        if (bg != null) {
            views.setImageViewBitmap(R.id.bg, bg)
        } else {
            views.setInt(R.id.bg, "setColorFilter", Color.parseColor(defaultBgColor))
        }
        val fontColor = Color.parseColor(
            data.getString("fgColor_$widgetId", null) ?: "#FFFFFF",
        )
        for (id in textViewIds) {
            views.setTextColor(id, fontColor)
        }
    }

    /**
     * 按需降采样解码图片（背景/进度条共用）：长边压到 [maxLongSide] 以内。
     * 控制跨进程序列化的位图体积（原图 1024px 的 ARGB 会到 4MB，浪费且不稳）。
     * 解码失败返回 null（调用方回落默认底色）。
     *
     * ⚠️ 二段缩放必须做实：inSampleSize 只按 2 的幂走，540 上限实测会放行到
     * ~1029² ≈ 4.2MB——MIUI 桌面吞得下，ColorOS 桌面对单次更新位图有更严的
     * 体积红线，超线的更新**整包被拒**（组件冻结在上一次小体积渲染，表现为
     * 「改字色/绑定生效、背景图永不生效」，v1.3.1 ColorOS 真机 dumpsys 定位：
     * 服务侧 views_bitmap_memory=4.2MB 但桌面仍显示回落纯色）。末段按比例
     * 精确缩放把长边做实到 [maxLongSide]。
     *
     * ColorOS 红线实测（一加，ColorOS 15 / Android 16，2026-10-13）：
     * 单卡更新 ≤1.2MB（信封 540²）与总量 1.73MB（统计卡 bg+图表）均正常
     * 应用；4.2MB 整包被拒。发货值 540 留 ~3× 余量；若未来用户反馈同类
     * 「部分生效」，先查 dumpsys appwidget 的 views_bitmap_memory。
     */
    fun decodeScaled(file: File, maxLongSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxLongSide) {
            sample *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            file.path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null
        val long = maxOf(decoded.width, decoded.height)
        if (long <= maxLongSide) return decoded
        val scale = maxLongSide.toFloat() / long
        val scaled = Bitmap.createScaledBitmap(
            decoded,
            maxOf(1, (decoded.width * scale).roundToInt()),
            maxOf(1, (decoded.height * scale).roundToInt()),
            true,
        )
        if (scaled != decoded) decoded.recycle()
        return scaled
    }
}
