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
            // 先中和历史滤镜再放位图：复用控件树的桌面（ColorOS 17 实锤）会把
            // 上一次「无背景」更新留下的不透明 colorFilter 套到新位图上——照片
            // 被纯色滤镜整个糊死，表现为「设背景不生效」（装包重绑 = 全新
            // inflate 无滤镜，所以能显示；「直接换图」上次也是位图所以成功）。
            // setColorFilter(0) = 全透明 SRC_ATOP，视觉空操作，专职洗掉旧滤镜
            views.setInt(R.id.bg, "setColorFilter", 0)
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
     * ColorOS 位图兼容实测（2026-10-13/14，三轮迭代）：
     * - 真凶（17 实锤）：**复用控件树的桌面会把旧 colorFilter 套到新位图上**
     *   ——「设背景不生效」= 照片被上一次无背景更新留下的不透明滤镜糊死，
     *   与图片大小无关（0.41MB 也失败）。修复 = 位图前先 setColorFilter(0)
     *   洗掉旧滤镜（视觉空操作）；装包重绑全新 inflate 所以能显示、
     *   「直接换图」上次也是位图所以一直成功。
     * - 次要红线（15 实锤）：单次推送位图总量仍有上限（1.2MB 过 / 4.2MB
     *   拒）；17 实测 1.06MB 过。滤镜修复后按清晰度优先取档：信封 bg 480
     *   （1:1 ≈0.92MB）、统计 bg 512（2:1 ≈0.52MB）、图表 512、进度条 640
     *   ——两卡总量 ≤1.2MB，全部在实测通过值内。
     * - 保存路径已收敛为仅直调通道（广播+直调连发大包裹疑似加剧丢更新）。
     * 诊断口诀：views_bitmap_memory 大而桌面显示旧渲染 = 推送送达、
     * 桌面拒收/糊死。MIUI 无此红线（每次全量重建控件树）。
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
