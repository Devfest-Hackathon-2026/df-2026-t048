package jp.kawakou.postcheck

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Android side of `postcheck/screen_detector` for still photos. Same model and
 * thresholds as the iOS detector (EfficientDet-Lite0, laptop / cell phone / tv,
 * score >= 0.35), run on device with MediaPipe Tasks. MediaPipe is used instead
 * of the TFLite Task Library because the latter's native libraries are not
 * 16 KB page aligned. Live camera frames ("frame") arrive as sensor-oriented
 * NV21 and are rotated upright with the given clockwise rotation; boxes are
 * returned in the upright frame. iOS additionally refines still-photo boxes
 * with Vision rectangles; Android returns the detector boxes.
 */
class PostCheckDeviceDetector(private val context: Context) : MethodChannel.MethodCallHandler {
    private val queue = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    // EXPERIMENT (2026-11-09, not for distribution): optional custom whiteboard
    // model from ml/object_detection, used only when the Git-ignored asset
    // assets/screen_detector/whiteboard_experiment.tflite exists at build time.
    // label null = name each detection by its COCO category (see appLabel).
    private data class DetectorEntry(val detector: ObjectDetector, val label: String?)

    private fun appLabel(category: String?): String = when (category) {
        "wine glass" -> "wine_glass"
        "book" -> "book"
        "picture_frame", "poster" -> category
        else -> "screen-device"
    }
    private var detectors: List<DetectorEntry>? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val work: () -> List<Map<String, Any>> = when (call.method) {
            "file" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("invalid_image", "Invalid image", null)
                    return
                }
                val task: () -> List<Map<String, Any>> = { detect(path) }
                task
            }
            "frame" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val stride = call.argument<Int>("bytesPerRow") ?: width
                val rotation = call.argument<Int>("rotation") ?: 0
                if (bytes == null || width <= 0 || height <= 0 || width > 8192 || height > 8192 ||
                    stride < width || bytes.size < stride * height * 3 / 2
                ) {
                    result.error("invalid_image", "Invalid image", null)
                    return
                }
                val task: () -> List<Map<String, Any>> = { detectFrame(bytes, width, height, stride, rotation) }
                task
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        queue.execute {
            val boxes = try {
                work()
            } catch (_: Exception) {
                null
            } catch (_: LinkageError) {
                // SDK/JNI static initialization failures must not crash the app.
                // Keep the error generic: do not log paths or inspected content.
                null
            }
            main.post {
                if (boxes == null) {
                    // Errors are not forwarded verbatim; they may contain file paths.
                    result.error("detector_unavailable", "Device detector unavailable", null)
                } else {
                    result.success(boxes)
                }
            }
        }
    }

    private fun detect(path: String): List<Map<String, Any>> {
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        val bitmap = BitmapFactory.decodeFile(path, options)
            ?: throw IllegalArgumentException("Invalid image")
        return detectBitmap(bitmap)
    }

    /** NV21 camera frame -> upright ARGB bitmap -> detectors. Nothing is stored. */
    private fun detectFrame(
        bytes: ByteArray, width: Int, height: Int, stride: Int, rotation: Int,
    ): List<Map<String, Any>> {
        val jpeg = ByteArrayOutputStream()
        YuvImage(bytes, ImageFormat.NV21, width, height, intArrayOf(stride, stride))
            .compressToJpeg(Rect(0, 0, width, height), 90, jpeg)
        val raw = BitmapFactory.decodeByteArray(jpeg.toByteArray(), 0, jpeg.size())
            ?: throw IllegalArgumentException("Invalid image")
        val upright = if (rotation % 360 == 0) raw else {
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true).also {
                if (it !== raw) raw.recycle()
            }
        }
        return detectBitmap(upright)
    }

    private fun detectBitmap(bitmap: Bitmap): List<Map<String, Any>> {
        try {
            val image = BitmapImageBuilder(bitmap).build()
            return detectors().flatMap { entry ->
                entry.detector.detect(image).detections().map { detection ->
                    val box = detection.boundingBox()
                    mapOf(
                        "box" to listOf(
                            box.left.toDouble(),
                            box.top.toDouble(),
                            box.width().toDouble(),
                            box.height().toDouble(),
                        ),
                        "label" to (entry.label
                            ?: appLabel(detection.categories().firstOrNull()?.categoryName())),
                    )
                }
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun detectors(): List<DetectorEntry> {
        detectors?.let { return it }
        val configs = listOf(
            Triple<String, List<String>, String?>(
                "assets/screen_detector/efficientdet_lite0.tflite",
                listOf("laptop", "cell phone", "tv", "wine glass", "book"), null),
            Triple("assets/screen_detector/whiteboard_experiment.tflite", listOf("whiteboard"), "whiteboard"),
            // EXPERIMENT (2026-11-10): picture frame / poster model; skipped if missing.
            Triple("assets/screen_detector/docs_experiment.tflite", listOf("picture_frame", "poster"), null),
        )
        val loaded = configs.mapNotNull { (asset, labels, label) ->
            try {
                val options = ObjectDetector.ObjectDetectorOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(model(asset)).build())
                    .setRunningMode(RunningMode.IMAGE)
                    .setScoreThreshold(0.35f)
                    .setMaxResults(10)
                    .setCategoryAllowlist(labels)
                    .build()
                DetectorEntry(ObjectDetector.createFromOptions(context, options), label)
            } catch (_: Exception) {
                null  // asset missing or model not loadable: skip this detector
            }
        }
        if (loaded.isEmpty()) throw IllegalStateException("No detector model")
        return loaded.also { detectors = it }
    }

    /** Reads a Flutter asset (about 4.5 MB) into a direct buffer. */
    private fun model(asset: String): ByteBuffer {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        val bytes = context.assets.open(key).use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply {
            put(bytes)
            rewind()
        }
    }

    fun close() {
        queue.execute {
            detectors?.forEach { it.detector.close() }
            detectors = null
        }
        queue.shutdown()
    }
}
