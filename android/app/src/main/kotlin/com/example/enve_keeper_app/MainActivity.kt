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
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 单文件覆盖写 Download/<subdir>/<fileName>（MediaStore，API 29+，无需存储权限）。
     * 返回是否写入成功；API<29（旧版无权限写不了公共目录）或任何失败返回 false，
     * Dart 侧降级为应用私有目录单文件。29+ 的查询只返回本应用可见的
     * 文件，命中即原地覆写；未命中走 IS_PENDING 插入（写完再发布），失败删掉半成品。
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
            val relPath = "Download/$subdir/"
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            var existing: Uri? = null
            resolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                arrayOf(relPath, fileName),
                null,
            )?.use { c ->
                if (c.moveToFirst()) existing = ContentUris.withAppendedId(collection, c.getLong(0))
            }
            val target = existing
            if (target != null) {
                // 单文件覆盖：原地截断重写，不产生第二个文件
                resolver.openOutputStream(target, "wt")?.use { it.write(bytes) } ?: return false
            } else {
                val draft = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = resolver.insert(collection, draft) ?: return false
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
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
