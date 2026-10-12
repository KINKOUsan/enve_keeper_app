package com.example.enve_keeper_app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 自动备份写公共目录的通道（v1.2.x 票 02 · ADR-0018）
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 组件直调刷新通道（v1.3.0 票 12）+ 主引擎登记（票 14 悬浮记账中转）
        WidgetRefreshChannel.install(flutterEngine, applicationContext)
        WidgetRefreshChannel.registerMainEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "enve_keeper_app/autobackup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeAutoBackup" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val subdir = call.argument<String>("subdir") ?: "金打细算"
                        val fileName = call.argument<String>("fileName") ?: "金打细算-自动备份.jx"
                        if (bytes == null) {
                            result.error("badargs", "bytes required", null)
                            return@setMethodCallHandler
                        }
                        // MediaStore 是磁盘 IO：放后台线程跑，结果回主线程
                        Thread {
                            val written = writeToDownloads(applicationContext, subdir, fileName, bytes)
                            runOnUiThread { result.success(written) }
                        }.start()
                    }
                    "readAutoBackup" -> {
                        val subdir = call.argument<String>("subdir") ?: "金打细算"
                        val fileName = call.argument<String>("fileName") ?: "金打细算-自动备份.jx"
                        Thread {
                            val bytes = readFromDownloads(applicationContext, subdir, fileName)
                            runOnUiThread { result.success(bytes) }
                        }.start()
                    }
                    "statAutoBackup" -> {
                        val subdir = call.argument<String>("subdir") ?: "金打细算"
                        val fileName = call.argument<String>("fileName") ?: "金打细算-自动备份.jx"
                        Thread {
                            val modified = statFromDownloads(applicationContext, subdir, fileName)
                            runOnUiThread { result.success(modified) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 主引擎销毁（用户退出 App）：清登记，防通知打到已销毁的引擎
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        WidgetRefreshChannel.registerMainEngine(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // 自动备份候选行：uri 定位内容，displayName 记名字，modifiedAt 是 MediaStore 的 epoch 秒
    private data class BackupCandidate(
        val uri: Uri,
        val displayName: String,
        val modifiedAt: Long,
    )

    /**
     * 查 Download/<subdir>/ 里的自动备份候选（260922 修复）：
     * 精确固定名 + 系统重名加序号档「金打细算-自动备份 (N).jx」都算——
     * MediaStore 只让本应用看见自有文件，可一旦与看不见的外来同名文件撞车
     * （另一变体安装/重装后属主丢失，票 03），插入就被系统改名成 (N)，
     * 此后只按精确名查永远落空，每次写入都再插一个新文件，重复文件越滚越多。
     * 按最近写入倒序返回；LIKE 先宽后严：括号里必须是纯数字才算序号档，
     * 用户手改的名字（如「自动备份 (重要).jx」）不碰。
     */
    private fun queryBackupCandidates(
        context: Context,
        subdir: String,
        fileName: String,
    ): List<BackupCandidate> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val stem = fileName.substringBeforeLast('.')
        val ext = fileName.substringAfterLast('.')
        val found = mutableListOf<BackupCandidate>()
        try {
            context.contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(
                    MediaStore.MediaColumns._ID,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    MediaStore.MediaColumns.DATE_MODIFIED,
                ),
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
                    "(${MediaStore.MediaColumns.DISPLAY_NAME}=? OR " +
                    "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?)",
                arrayOf("Download/$subdir/", fileName, "${stem} (%.$ext"),
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC, ${MediaStore.MediaColumns._ID} DESC",
            )?.use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(1) ?: continue
                    if (name != fileName && !isSystemNumberedName(name, stem, ext)) continue
                    found.add(
                        BackupCandidate(
                            uri = ContentUris.withAppendedId(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                c.getLong(0),
                            ),
                            displayName = name,
                            modifiedAt = c.getLong(2),
                        ),
                    )
                }
            }
        } catch (e: Exception) {
            // 查询失败当无候选：写路径走插入，读/状态路径当没有文件
        }
        return found
    }

    /** 系统加序号重名档：「<stem> (纯数字).<ext>」；其余名字一律不认。 */
    private fun isSystemNumberedName(name: String, stem: String, ext: String): Boolean {
        if (!name.startsWith("$stem (") || !name.endsWith(".$ext")) return false
        val digits = name.removePrefix("$stem (").removeSuffix(".$ext")
        return digits.isNotEmpty() && digits.all { it.isDigit() }
    }

    /** 候选里挑正主：精确固定名优先，否则取最近写入的一个。 */
    private fun pickBackupCandidate(
        context: Context,
        subdir: String,
        fileName: String,
    ): BackupCandidate? {
        val candidates = queryBackupCandidates(context, subdir, fileName)
        return candidates.firstOrNull { it.displayName == fileName }
            ?: candidates.firstOrNull()
    }

    /**
     * 单文件覆盖写 Download/<subdir>/<fileName>（MediaStore，API 29+，无需存储权限）。
     * 返回是否写入成功；API<29（旧版无权限写不了公共目录）或任何失败返回 false，
     * Dart 侧降级为应用私有目录单文件。命中候选（可见=自有）→ 挑正主原地覆写、
     * 其余重复删掉（历史版本留下的 (1)(2)(3) 一并收敛回单文件）；未命中走
     * IS_PENDING 插入（写完再发布），失败删掉半成品。
     */
    private fun writeToDownloads(
        context: Context,
        subdir: String,
        fileName: String,
        bytes: ByteArray,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val resolver = context.contentResolver
            val candidates = queryBackupCandidates(context, subdir, fileName)
            if (candidates.isNotEmpty()) {
                val target = candidates.firstOrNull { it.displayName == fileName } ?: candidates[0]
                // 单文件覆盖：原地截断重写
                resolver.openOutputStream(target.uri, "wt")?.use { it.write(bytes) } ?: return false
                // 兜底发布：上次写一半崩溃可能留下 IS_PENDING=1 的行，顺带救活
                try {
                    resolver.update(
                        target.uri,
                        ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                        null,
                        null,
                    )
                } catch (e: Exception) {
                    // 发布不了下次写入还会再试，不挡本次成功
                }
                // 收敛重复：只删自有行（可见=自有），外来文件根本查不到、删不动
                for (c in candidates) {
                    if (c.uri == target.uri) continue
                    try {
                        resolver.delete(c.uri, null, null)
                    } catch (e: Exception) {
                        // 删不掉就留着，不影响正主已更新
                    }
                }
                renameToCanonical(context, subdir, fileName, target)
            } else {
                val draft = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/$subdir/")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, draft) ?: return false
                // 打不开流也算失败：先把半成品删掉再返回（不能靠 catch，return 不触发它）
                val stream = resolver.openOutputStream(uri)
                if (stream == null) {
                    resolver.delete(uri, null, null)
                    return false
                }
                try {
                    stream.use { it.write(bytes) }
                    val publish = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                    resolver.update(uri, publish, null, null)
                } catch (e: Exception) {
                    resolver.delete(uri, null, null) // 写一半失败：半成品不留尸体
                    return false
                }
                // 发布时若与看不见的外来同名文件撞车，系统会把新文件改成 (N)——
                // 不用补救：下次写入靠序号名照样查到，收敛为单文件
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 正主若顶着序号名，尝试改回固定名（与备份页标注的位置文案一致）。
     * 改名失败 = 有看不见的外来同名文件顶着——系统可能把我们的行再改成别的
     * 序号，改名后复查一次，没改成要改回原名，否则下次就找不到它了。
     */
    private fun renameToCanonical(
        context: Context,
        subdir: String,
        fileName: String,
        target: BackupCandidate,
    ) {
        if (target.displayName == fileName) return
        try {
            val resolver = context.contentResolver
            resolver.update(
                target.uri,
                ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, fileName) },
                null,
                null,
            )
            val actual = queryBackupCandidates(context, subdir, fileName)
                .firstOrNull { it.uri == target.uri }?.displayName
            if (actual != null && actual != fileName) {
                resolver.update(
                    target.uri,
                    ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, target.displayName) },
                    null,
                    null,
                )
            }
        } catch (e: Exception) {
            // 改名是锦上添花：失败就顶着序号名，不影响备份内容正确
        }
    }

    /**
     * 读 Download/<subdir>/<fileName>（MediaStore，API 29+）——重装找回（票 03）。
     * 读的是正主（精确名或最近序号档）。重装后文件属主丢失，部分系统版本会
     * 拒绝读取：未命中、打不开流、读异常一律返回 null，Dart 侧与「无文件」
     * 同路径静默降级，备份页「从文件恢复」兜底。
     */
    private fun readFromDownloads(
        context: Context,
        subdir: String,
        fileName: String,
    ): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val uri = pickBackupCandidate(context, subdir, fileName)?.uri ?: return null
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 查 Download/<subdir>/<fileName> 正主的最近写入时刻（epoch 毫秒，票 02 修复：
     * 状态行启动时从文件还原）——序号档也能查到。MediaStore 的 DATE_MODIFIED 是
     * epoch 秒。未命中/异常返回 null。
     */
    private fun statFromDownloads(
        context: Context,
        subdir: String,
        fileName: String,
    ): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            pickBackupCandidate(context, subdir, fileName)?.modifiedAt?.times(1000L)
        } catch (e: Exception) {
            null
        }
    }
}
