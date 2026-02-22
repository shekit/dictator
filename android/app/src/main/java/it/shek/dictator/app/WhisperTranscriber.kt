package it.shek.dictator.app

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlinx.coroutines.*

/**
 * Records audio via AudioRecord and transcribes using whisper.cpp.
 * Unlike SpeechRecognizer, this handles raw audio capture and batch transcription.
 */
class WhisperTranscriber {

    companion object {
        private const val TAG = "WhisperTranscriber"
        private const val SAMPLE_RATE = 16000
    }

    private var contextPtr: Long = 0
    private var audioRecord: AudioRecord? = null
    @Volatile
    private var isRecording = false
    private val audioBuffer = mutableListOf<Float>()
    private var recordingJob: Job? = null

    val isModelLoaded: Boolean get() = contextPtr != 0L

    fun loadModel(modelPath: String): Boolean {
        if (contextPtr != 0L) return true
        contextPtr = WhisperLib.initContext(modelPath)
        Log.d(TAG, "Model load result: ${if (contextPtr != 0L) "success" else "failed"}")
        return contextPtr != 0L
    }

    fun startRecording() {
        if (isRecording) return

        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize * 2
        )

        synchronized(audioBuffer) { audioBuffer.clear() }
        isRecording = true
        audioRecord?.startRecording()

        recordingJob = CoroutineScope(Dispatchers.IO).launch {
            val buffer = ShortArray(bufferSize / 2)
            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    synchronized(audioBuffer) {
                        for (i in 0 until read) {
                            audioBuffer.add(buffer[i].toFloat() / 32768.0f)
                        }
                    }
                }
            }
        }

        Log.d(TAG, "Recording started (16kHz mono PCM)")
    }

    suspend fun stopAndTranscribe(): String {
        isRecording = false
        recordingJob?.join()

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        val samples: FloatArray
        synchronized(audioBuffer) {
            samples = audioBuffer.toFloatArray()
            audioBuffer.clear()
        }

        if (samples.size < SAMPLE_RATE / 2) { // Less than 0.5s of audio
            Log.d(TAG, "Recording too short (${samples.size} samples), skipping")
            return ""
        }

        Log.d(TAG, "Transcribing ${samples.size} samples (${samples.size / SAMPLE_RATE.toFloat()}s)")

        return withContext(Dispatchers.Default) {
            WhisperLib.transcribe(contextPtr, samples)
        }
    }

    fun release() {
        isRecording = false
        recordingJob?.cancel()
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        if (contextPtr != 0L) {
            WhisperLib.freeContext(contextPtr)
            contextPtr = 0
        }
    }
}
