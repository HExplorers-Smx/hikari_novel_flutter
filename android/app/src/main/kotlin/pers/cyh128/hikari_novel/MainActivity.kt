package pers.cyh128.hikari_novel

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * 原生保存图片到系统相册（避免 image_gallery_saver 在部分 Flutter/AGP/Kotlin 组合下无法编译的问题）
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "hikari/image_saver"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "hikari_${System.currentTimeMillis()}"
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("ARG_ERROR", "bytes is null/empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            saveToGallery(bytes, name)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    @Throws(IOException::class)
    private fun saveToGallery(bytes: ByteArray, name: String) {
        val resolver = applicationContext.contentResolver

        val displayName = if (name.endsWith(".jpg", true) || name.endsWith(".jpeg", true) || name.endsWith(".png", true)) {
            name
        } else {
            "$name.jpg"
        }

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")

            // Android 10+ 使用相对路径写入 Pictures/HikariNovel
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/HikariNovel")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Failed to create new MediaStore record.")

        resolver.openOutputStream(uri)?.use { out ->
            out.write(bytes)
            out.flush()
        } ?: throw IOException("Failed to open output stream.")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        }
    }
}
