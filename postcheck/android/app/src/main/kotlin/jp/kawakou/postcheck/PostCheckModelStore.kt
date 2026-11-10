package jp.kawakou.postcheck

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** The OS fetches only a fixed public model over Wi-Fi. No inspected input is sent. */
class PostCheckModelStore private constructor(context: Context) {
    companion object {
        private const val BYTES = 2588147712L
        private const val HASH = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
        private const val SOURCE = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
        @Volatile private var instance: PostCheckModelStore? = null
        fun shared(context: Context): PostCheckModelStore = instance ?: synchronized(this) {
            instance ?: PostCheckModelStore(context.applicationContext).also { instance = it }
        }
    }

    private val app = context.applicationContext
    private val manager = app.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs = app.getSharedPreferences("PostCheckGemmaDownload", Context.MODE_PRIVATE)
    private val directory = File(app.getExternalFilesDir(null) ?: app.noBackupFilesDir, "models").apply { mkdirs() }
    private val model = File(directory, "gemma-$HASH.litertlm")
    private val incoming = File(directory, "gemma-$HASH.download")
    private val verifier = Executors.newSingleThreadExecutor()
    private var phase = "waiting"
    private var received = 0L
    private var verifying = false

    private fun ready(): Boolean = model.isFile && model.length() == BYTES &&
        prefs.getString("digest", null) == HASH && prefs.getLong("modified", -1) == model.lastModified()

    @Synchronized fun handle(method: String): Any? {
        refresh()
        when (method) {
            "start" -> start(false)
            "retry" -> start(true)
            "pause" -> pause()
            "path" -> return if (ready()) model.path else null
        }
        return mapOf("phase" to phase, "received" to received, "total" to BYTES)
    }

    private fun refresh() {
        if (ready()) { phase = "ready"; received = BYTES; return }
        if (verifying) return
        if (model.isFile) { verify(model); return }
        if (prefs.getBoolean("paused", false)) { phase = "paused"; return }
        val id = prefs.getLong("task", -1)
        if (id < 0) return
        manager.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (!cursor.moveToFirst()) {
                prefs.edit().remove("task").apply()
                phase = "failed"
                return
            }
            received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                .coerceIn(0L, BYTES)
            when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_SUCCESSFUL -> verify(incoming)
                DownloadManager.STATUS_FAILED -> phase = "failed"
                DownloadManager.STATUS_RUNNING -> phase = "downloading"
                else -> phase = "waiting"
            }
        }
    }

    private fun start(retry: Boolean) {
        if (ready() || verifying) return
        if (prefs.getBoolean("paused", false) && !retry) { phase = "paused"; return }
        if (phase == "failed" && !retry) return
        prefs.edit().putBoolean("paused", false).commit()
        val existing = prefs.getLong("task", -1)
        if (existing >= 0 && phase != "failed") return
        if (existing >= 0) manager.remove(existing)
        prefs.edit().remove("task").commit()
        if (incoming.exists() && incoming.length() == BYTES) { verify(incoming); return }
        incoming.delete()
        val request = DownloadManager.Request(Uri.parse(SOURCE))
            .setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI)
            .setAllowedOverRoaming(false)
            .setAllowedOverMetered(false)
            .setTitle("PostCheck · Gemma 4 E2B")
            .setDescription("Preparing on-device AI. Basic checks are available.")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(incoming))
        val id = manager.enqueue(request)
        if (!prefs.edit().putLong("task", id).commit()) {
            manager.remove(id)
            phase = "failed"
            return
        }
        phase = "waiting"
        received = 0
    }

    private fun pause() {
        if (ready()) return
        prefs.edit().putBoolean("paused", true).commit()
        if (verifying) return
        val id = prefs.getLong("task", -1)
        if (id >= 0) manager.remove(id)
        prefs.edit().remove("task").commit()
        incoming.delete()
        phase = "paused"
        received = 0
    }

    private fun verify(file: File) {
        if (verifying) return
        verifying = true
        phase = "verifying"
        received = BYTES
        verifier.execute {
            val valid = try {
                if (!file.isFile || file.length() != BYTES) false else {
                    val digest = MessageDigest.getInstance("SHA-256")
                    file.inputStream().use { input ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            digest.update(buffer, 0, count)
                        }
                    }
                    digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) } == HASH
                }
            } catch (_: Exception) { false }
            synchronized(this) {
                try {
                    check(valid)
                    if (file != model) {
                        model.delete()
                        check(file.renameTo(model))
                    }
                    check(prefs.edit().putString("digest", HASH).putLong("modified", model.lastModified())
                        .remove("task").commit())
                    phase = "ready"
                } catch (_: Exception) {
                    file.delete()
                    val id = prefs.getLong("task", -1)
                    if (id >= 0) manager.remove(id)
                    prefs.edit().remove("task").remove("digest").commit()
                    phase = "failed"
                    received = 0
                }
                verifying = false
            }
        }
    }
}
