package jp.kawakou.postcheck

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val modelQueue = Executors.newSingleThreadExecutor()

    // Separate from modelQueue so a save never waits behind model verification.
    private val io = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var deviceDetector: PostCheckDeviceDetector? = null

    // Android 8–9 only: the save waiting for the storage permission dialog.
    private var pendingSave: Pair<ByteArray, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val store = PostCheckModelStore.shared(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "postcheck/model")
            .setMethodCallHandler { call, result ->
                if (call.method !in setOf("status", "start", "retry", "pause", "path")) {
                    result.notImplemented()
                } else {
                    modelQueue.execute {
                        val value = try { store.handle(call.method) } catch (_: Exception) {
                            if (call.method == "path") null else mapOf("phase" to "failed")
                        }
                        mainHandler.post { result.success(value) }
                    }
                }
            }
        val detector = PostCheckDeviceDetector(applicationContext).also { deviceDetector = it }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "postcheck/screen_detector")
            .setMethodCallHandler(detector)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "postcheck/privacy")
            .setMethodCallHandler(::onPrivacyCall)
    }

    private fun onPrivacyCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "savePhoto" -> {
                val png = call.arguments as? ByteArray
                if (png == null) {
                    result.error("invalid_image", "Invalid image", null)
                    return
                }
                if (needsStoragePermission()) {
                    if (pendingSave != null) {
                        result.error("photo_save", "Another save is waiting for permission", null)
                        return
                    }
                    pendingSave = png to result
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_STORAGE)
                    return
                }
                save(png, result)
            }
            "openSettings" -> {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)),
                )
                result.success(null)
            }
            // The remaining channel methods are iOS-only; Dart already falls back when they are missing.
            else -> result.notImplemented()
        }
    }

    // Android 10+ writes through MediaStore without a permission; older versions need WRITE_EXTERNAL_STORAGE.
    private fun needsStoragePermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        // Plugins (camera, location, image picker) receive their results through super.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_STORAGE) return
        val (png, result) = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            save(png, result)
        } else {
            // Same error code as iOS so Dart shows the permission message and settings button.
            result.error("photo_permission", "Photo access denied", null)
        }
    }

    private fun save(png: ByteArray, result: MethodChannel.Result) {
        io.execute {
            val saved = runCatching { writeToGallery(png) }.isSuccess
            mainHandler.post {
                if (saved) result.success(null) else result.error("photo_save", "Photo save failed", null)
            }
        }
    }

    private fun writeToGallery(png: ByteArray) {
        val name = "PostCheck_${SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())}.png"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            // IS_PENDING hides the entry from the gallery until the bytes are fully written.
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/PostCheck")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
                ?: error("MediaStore insert failed")
            try {
                resolver.openOutputStream(uri)?.use { it.write(png) } ?: error("No output stream")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                // Do not leave an empty or partial image in the gallery.
                resolver.delete(uri, null, null)
                throw e
            }
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "PostCheck")
            if (!dir.isDirectory && !dir.mkdirs()) error("Cannot create directory")
            val file = File(dir, name)
            file.writeBytes(png)
            MediaScannerConnection.scanFile(this, arrayOf(file.path), arrayOf("image/png"), null)
        }
    }

    override fun onDestroy() {
        modelQueue.shutdown()
        io.shutdown()
        deviceDetector?.close()
        deviceDetector = null
        super.onDestroy()
    }

    private companion object {
        const val REQUEST_STORAGE = 4201
    }
}
