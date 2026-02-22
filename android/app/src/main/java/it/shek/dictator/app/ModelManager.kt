package it.shek.dictator.app

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.io.*
import java.net.HttpURLConnection
import java.net.URL

/**
 * Manages Whisper model download, storage, and lifecycle.
 * Models are stored in the app's internal files directory.
 */
class ModelManager(private val context: Context) {

    companion object {
        private const val TAG = "ModelManager"
        private const val MODEL_DIR = "whisper"
        private const val MODEL_FILENAME = "ggml-tiny.en.bin"
        private const val MODEL_URL =
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"
        const val MODEL_DISPLAY_NAME = "Whisper Tiny (English)"
        const val MODEL_SIZE_MB = 75
    }

    private val modelDir: File get() = File(context.filesDir, MODEL_DIR)
    val modelFile: File get() = File(modelDir, MODEL_FILENAME)
    val isModelDownloaded: Boolean get() = modelFile.exists() && modelFile.length() > 1_000_000

    fun getModelSizeMB(): Long {
        return if (modelFile.exists()) modelFile.length() / (1024 * 1024) else 0
    }

    suspend fun downloadModel(onProgress: (Int) -> Unit): Boolean = withContext(Dispatchers.IO) {
        try {
            modelDir.mkdirs()
            val tempFile = File(modelDir, "$MODEL_FILENAME.tmp")

            val url = URL(MODEL_URL)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", "Dictator-Android/1.0")

            if (connection.responseCode != 200) {
                Log.e(TAG, "Download failed: HTTP ${connection.responseCode}")
                return@withContext false
            }

            val totalSize = connection.contentLength.toLong()
            Log.d(TAG, "Downloading model: $totalSize bytes")

            var downloaded = 0L
            val buffer = ByteArray(8192)

            connection.inputStream.use { input ->
                FileOutputStream(tempFile).use { output ->
                    while (true) {
                        val bytesRead = input.read(buffer)
                        if (bytesRead == -1) break
                        output.write(buffer, 0, bytesRead)
                        downloaded += bytesRead
                        if (totalSize > 0) {
                            val progress = ((downloaded * 100) / totalSize).toInt()
                            withContext(Dispatchers.Main) {
                                onProgress(progress)
                            }
                        }
                    }
                }
            }

            // Atomic rename: only replace target after full download
            if (modelFile.exists()) modelFile.delete()
            val success = tempFile.renameTo(modelFile)
            Log.d(TAG, "Model downloaded: ${modelFile.absolutePath} (${getModelSizeMB()} MB)")
            success
        } catch (e: Exception) {
            Log.e(TAG, "Failed to download model", e)
            // Clean up partial download
            File(modelDir, "$MODEL_FILENAME.tmp").delete()
            false
        }
    }

    fun deleteModel(): Boolean {
        val deleted = modelFile.delete()
        Log.d(TAG, "Model deleted: $deleted")
        return deleted
    }
}
