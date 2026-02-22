package it.shek.dictator.app

object WhisperLib {
    init {
        System.loadLibrary("whisper-jni")
    }

    external fun initContext(modelPath: String): Long
    external fun transcribe(contextPtr: Long, audioData: FloatArray): String
    external fun freeContext(contextPtr: Long)
}
