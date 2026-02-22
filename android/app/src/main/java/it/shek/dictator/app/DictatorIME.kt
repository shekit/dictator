package it.shek.dictator.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.inputmethodservice.InputMethodService
import android.util.Log
import android.util.TypedValue
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.widget.ImageButton
import android.widget.TextView
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*

/**
 * Dictator Input Method Service - a minimal dictation keyboard.
 *
 * Two recording modes (configurable in main app settings):
 * - Hold-to-talk (default): press and hold mic, speak, release to stop.
 * - Tap-to-toggle: tap to start, tap again to stop.
 *
 * Two STT engines (configurable in main app settings):
 * - SpeechRecognizer (default): Android's built-in speech recognition.
 * - Whisper: On-device whisper.cpp model. Works fully offline.
 */
class DictatorIME : InputMethodService() {

    companion object {
        private const val TAG = "DictatorIME"
        const val PREFS_NAME = "dictator_prefs"
        const val KEY_TAP_MODE = "tap_mode"
        const val KEY_STT_ENGINE = "stt_engine"
        const val STT_SPEECH_RECOGNIZER = "speech_recognizer"
        const val STT_WHISPER = "whisper"
    }

    enum class State {
        IDLE,
        RECORDING,
        PROCESSING
    }

    private var isTapMode = false
    private var sttEngine = STT_SPEECH_RECOGNIZER
    private var state = State.IDLE
    // Tracks whether the user still wants to record (hasn't lifted finger / tapped stop).
    // SpeechRecognizer may auto-stop on silence, but we auto-restart if this is true.
    private var userWantsRecording = false

    private var micButton: ImageButton? = null
    private var settingsButton: ImageButton? = null
    private var backspaceButton: ImageButton? = null
    private var statusText: TextView? = null

    private var speechRecognizer: SpeechRecognizer? = null

    // Whisper engine
    private var whisperTranscriber: WhisperTranscriber? = null
    private var whisperModelLoading = false
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Backspace repeat-on-hold with acceleration
    private val backspaceHandler = Handler(Looper.getMainLooper())
    private val backspaceInitialDelay = 400L
    private val backspaceStartInterval = 200L
    private val backspaceMinInterval = 40L
    private val backspaceAccelStep = 20L // ms faster each repeat
    private var backspaceCurrentInterval = backspaceStartInterval
    private val backspaceRepeatRunnable: Runnable = object : Runnable {
        override fun run() {
            deleteWord()
            if (backspaceCurrentInterval > backspaceMinInterval) {
                backspaceCurrentInterval -= backspaceAccelStep
                if (backspaceCurrentInterval < backspaceMinInterval) {
                    backspaceCurrentInterval = backspaceMinInterval
                }
            }
            backspaceHandler.postDelayed(this, backspaceCurrentInterval)
        }
    }

    // Backspace swipe gesture: up = space, down = enter
    private enum class BackspaceGesture { NONE, SWIPE_UP, SWIPE_DOWN }
    private var backspaceTouchDownY = 0f
    private var backspaceGesture = BackspaceGesture.NONE
    private var backspaceDeletedText: String? = null // for undo on swipe
    private val swipeThresholdDp = 30f

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreateInputView(): View {
        Log.d(TAG, "onCreateInputView")
        val view = layoutInflater.inflate(R.layout.keyboard_view, null)

        micButton = view.findViewById(R.id.micButton)
        settingsButton = view.findViewById(R.id.settingsButton)
        backspaceButton = view.findViewById(R.id.backspaceButton)
        statusText = view.findViewById(R.id.statusText)

        micButton?.setOnTouchListener { _, event -> onMicTouch(event) }
        settingsButton?.setOnClickListener { openSettings() }
        backspaceButton?.setOnTouchListener { _, event -> onBackspaceTouch(event) }

        loadSettings()

        if (sttEngine == STT_SPEECH_RECOGNIZER) {
            initSpeechRecognizer()
        } else {
            loadWhisperModelAsync()
        }

        updateUI()
        return view
    }

    override fun onStartInputView(info: android.view.inputmethod.EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        val previousEngine = sttEngine
        loadSettings()

        // If engine changed, re-initialize
        if (previousEngine != sttEngine) {
            if (sttEngine == STT_SPEECH_RECOGNIZER) {
                whisperTranscriber?.release()
                whisperTranscriber = null
                initSpeechRecognizer()
            } else {
                speechRecognizer?.destroy()
                speechRecognizer = null
                loadWhisperModelAsync()
            }
        }

        updateUI()
    }

    private fun loadSettings() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isTapMode = prefs.getBoolean(KEY_TAP_MODE, false)
        sttEngine = prefs.getString(KEY_STT_ENGINE, STT_SPEECH_RECOGNIZER) ?: STT_SPEECH_RECOGNIZER
    }

    // --- SpeechRecognizer engine ---

    private fun initSpeechRecognizer() {
        speechRecognizer?.destroy()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        ) {
            speechRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this).apply {
                setRecognitionListener(recognitionListener)
            }
            Log.d(TAG, "SpeechRecognizer ready (on-device)")
        } else if (SpeechRecognizer.isRecognitionAvailable(this)) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(recognitionListener)
            }
            Log.d(TAG, "SpeechRecognizer ready (standard, prefer offline)")
        } else {
            Log.e(TAG, "Speech recognition not available on this device")
        }
    }

    private fun hasRecordPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
    }

    private fun requestRecordPermission() {
        val intent = Intent(this, PermissionActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun createRecognizerIntent(): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 4000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1000L)
        }
    }

    private val recognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "SpeechRecognizer ready for speech")
        }

        override fun onBeginningOfSpeech() {
            Log.d(TAG, "Speech detected")
        }

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            Log.d(TAG, "End of speech detected (userWantsRecording=$userWantsRecording)")
            if (!userWantsRecording && state == State.RECORDING) {
                state = State.PROCESSING
                updateUI()
            }
        }

        override fun onError(error: Int) {
            val errorMsg = when (error) {
                SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                SpeechRecognizer.ERROR_CLIENT -> "Client error"
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
                SpeechRecognizer.ERROR_NETWORK -> "Network error"
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                SpeechRecognizer.ERROR_NO_MATCH -> "No speech detected"
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                SpeechRecognizer.ERROR_SERVER -> "Server error"
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected"
                else -> "Unknown error ($error)"
            }
            Log.e(TAG, "SpeechRecognizer error: $errorMsg (userWantsRecording=$userWantsRecording)")

            val issilenceError = error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT

            if (userWantsRecording && issilenceError) {
                Log.d(TAG, "Auto-restarting SpeechRecognizer after silence")
                state = State.RECORDING
                speechRecognizer?.startListening(createRecognizerIntent())
            } else {
                state = State.IDLE
                userWantsRecording = false
                updateUI()
            }
        }

        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = matches?.firstOrNull()?.trim() ?: ""
            Log.d(TAG, "Final result: '$text' (userWantsRecording=$userWantsRecording)")

            if (text.isNotEmpty()) {
                insertText(text)
            }

            if (userWantsRecording) {
                Log.d(TAG, "Auto-restarting SpeechRecognizer (user still recording)")
                state = State.RECORDING
                speechRecognizer?.startListening(createRecognizerIntent())
            } else {
                state = State.IDLE
                updateUI()
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = matches?.firstOrNull() ?: ""
            if (text.isNotEmpty()) {
                Log.d(TAG, "Partial result: '$text'")
                val maxLen = 40
                statusText?.text = if (text.length > maxLen) {
                    "\u2026${text.takeLast(maxLen)}"
                } else {
                    text
                }
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    // --- Whisper engine ---

    private fun loadWhisperModelAsync() {
        val modelManager = ModelManager(this)
        if (!modelManager.isModelDownloaded) {
            Log.d(TAG, "Whisper model not downloaded")
            return
        }

        if (whisperTranscriber?.isModelLoaded == true) {
            Log.d(TAG, "Whisper model already loaded")
            return
        }

        if (whisperModelLoading) return
        whisperModelLoading = true

        serviceScope.launch(Dispatchers.IO) {
            val transcriber = WhisperTranscriber()
            val loaded = transcriber.loadModel(modelManager.modelFile.absolutePath)
            withContext(Dispatchers.Main) {
                whisperModelLoading = false
                if (loaded) {
                    whisperTranscriber = transcriber
                    Log.d(TAG, "Whisper model loaded")
                } else {
                    Log.e(TAG, "Failed to load Whisper model")
                }
            }
        }
    }

    private fun startWhisperRecording() {
        val modelManager = ModelManager(this)
        if (!modelManager.isModelDownloaded) {
            Log.w(TAG, "Whisper model not downloaded")
            statusText?.text = getString(R.string.model_not_downloaded)
            return
        }

        if (whisperTranscriber == null || whisperTranscriber?.isModelLoaded != true) {
            if (!whisperModelLoading) {
                loadWhisperModelAsync()
            }
            statusText?.text = getString(R.string.loading_model)
            Log.d(TAG, "Whisper model loading, try again shortly")
            return
        }

        Log.d(TAG, "Whisper recording started (mode: ${if (isTapMode) "tap" else "hold"})")
        micButton?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        userWantsRecording = true
        state = State.RECORDING
        updateUI()
        whisperTranscriber?.startRecording()
    }

    private fun stopWhisperRecording() {
        Log.d(TAG, "Whisper recording stopped")
        micButton?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        userWantsRecording = false
        state = State.PROCESSING
        updateUI()

        serviceScope.launch {
            val text = whisperTranscriber?.stopAndTranscribe()?.trim() ?: ""
            Log.d(TAG, "Whisper result: '$text'")
            if (text.isNotEmpty()) {
                insertText(text)
            }
            state = State.IDLE
            updateUI()
        }
    }

    // --- Common recording control ---

    private fun onMicTouch(event: MotionEvent): Boolean {
        if (state == State.PROCESSING) return true

        if (isTapMode) {
            if (event.action == MotionEvent.ACTION_UP) {
                if (state == State.IDLE) {
                    startRecording()
                } else if (state == State.RECORDING) {
                    stopRecording()
                }
            }
        } else {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    if (state == State.IDLE) {
                        startRecording()
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (state == State.RECORDING) {
                        stopRecording()
                    }
                }
            }
        }
        return true
    }

    private fun startRecording() {
        if (!hasRecordPermission()) {
            Log.w(TAG, "RECORD_AUDIO permission not granted, requesting...")
            requestRecordPermission()
            return
        }

        if (sttEngine == STT_WHISPER) {
            startWhisperRecording()
        } else {
            startSpeechRecognizerRecording()
        }
    }

    private fun startSpeechRecognizerRecording() {
        if (speechRecognizer == null) {
            initSpeechRecognizer()
        }

        if (speechRecognizer == null) {
            Log.e(TAG, "SpeechRecognizer not available")
            statusText?.text = getString(R.string.speech_not_available)
            return
        }

        Log.d(TAG, "Recording started (mode: ${if (isTapMode) "tap" else "hold"})")
        micButton?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        userWantsRecording = true
        state = State.RECORDING
        updateUI()
        speechRecognizer?.startListening(createRecognizerIntent())
    }

    private fun stopRecording() {
        if (sttEngine == STT_WHISPER) {
            stopWhisperRecording()
        } else {
            stopSpeechRecognizerRecording()
        }
    }

    private fun stopSpeechRecognizerRecording() {
        Log.d(TAG, "Recording stopped (mode: ${if (isTapMode) "tap" else "hold"})")
        micButton?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        userWantsRecording = false
        state = State.PROCESSING
        updateUI()
        speechRecognizer?.stopListening()
    }

    private fun insertText(text: String) {
        val ic = currentInputConnection ?: return
        // Auto-insert space if previous char isn't whitespace/empty
        val before = ic.getTextBeforeCursor(1, 0)
        if (text != " " && before != null && before.isNotEmpty() &&
            !before.last().isWhitespace()
        ) {
            ic.commitText(" $text", 1)
            Log.d(TAG, "Inserted text with auto-space: '$text'")
        } else {
            ic.commitText(text, 1)
            Log.d(TAG, "Inserted text: '$text'")
        }
    }

    private fun openSettings() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun onBackspaceTouch(event: MotionEvent): Boolean {
        val swipeThresholdPx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, swipeThresholdDp, resources.displayMetrics
        )

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                backspaceTouchDownY = event.rawY
                backspaceGesture = BackspaceGesture.NONE
                backspaceDeletedText = null
                backspaceCurrentInterval = backspaceStartInterval
                backspaceDeletedText = deleteWord()
                backspaceHandler.postDelayed(backspaceRepeatRunnable, backspaceInitialDelay)
            }
            MotionEvent.ACTION_MOVE -> {
                val dy = event.rawY - backspaceTouchDownY
                val newGesture = when {
                    dy < -swipeThresholdPx -> BackspaceGesture.SWIPE_UP
                    dy > swipeThresholdPx -> BackspaceGesture.SWIPE_DOWN
                    else -> BackspaceGesture.NONE
                }
                if (newGesture != BackspaceGesture.NONE && backspaceGesture == BackspaceGesture.NONE) {
                    backspaceHandler.removeCallbacks(backspaceRepeatRunnable)
                    undoInitialDelete()
                    backspaceGesture = newGesture
                    backspaceButton?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    Log.d(TAG, "Backspace swipe detected: $newGesture")
                }
            }
            MotionEvent.ACTION_UP -> {
                backspaceHandler.removeCallbacks(backspaceRepeatRunnable)
                when (backspaceGesture) {
                    BackspaceGesture.SWIPE_UP -> {
                        val ic = currentInputConnection
                        ic?.commitText(" ", 1)
                        Log.d(TAG, "Swipe up: inserted space")
                    }
                    BackspaceGesture.SWIPE_DOWN -> {
                        val ic = currentInputConnection
                        ic?.commitText("\n", 1)
                        Log.d(TAG, "Swipe down: inserted newline")
                    }
                    BackspaceGesture.NONE -> { /* normal backspace, already handled */ }
                }
                backspaceGesture = BackspaceGesture.NONE
                backspaceDeletedText = null
            }
            MotionEvent.ACTION_CANCEL -> {
                backspaceHandler.removeCallbacks(backspaceRepeatRunnable)
                backspaceGesture = BackspaceGesture.NONE
                backspaceDeletedText = null
            }
        }
        return true
    }

    private fun undoInitialDelete() {
        val text = backspaceDeletedText ?: return
        val ic = currentInputConnection ?: return
        ic.commitText(text, 1)
        Log.d(TAG, "Undid initial delete: '$text'")
        backspaceDeletedText = null
    }

    /** Deletes one word (or selection) and returns the deleted text for potential undo. */
    private fun deleteWord(): String? {
        val ic = currentInputConnection ?: return null

        val selected = ic.getSelectedText(0)
        if (selected != null && selected.isNotEmpty()) {
            ic.commitText("", 1)
            Log.d(TAG, "Deleted selection (${selected.length} chars)")
            return selected.toString()
        }

        val before = ic.getTextBeforeCursor(100, 0) ?: return null
        if (before.isEmpty()) return null

        val text = before.toString()
        val end = text.length

        if (text[end - 1] == ' ') {
            var i = end
            while (i > 0 && text[i - 1] == ' ') i--
            val spacesToDelete = end - i
            val deleted = text.substring(end - spacesToDelete)
            ic.deleteSurroundingText(spacesToDelete, 0)
            Log.d(TAG, "Deleted $spacesToDelete spaces")
            return deleted
        } else {
            var i = end
            while (i > 0 && text[i - 1] != ' ') i--
            val charsToDelete = end - i
            val deleted = text.substring(end - charsToDelete)
            ic.deleteSurroundingText(charsToDelete, 0)
            Log.d(TAG, "Deleted $charsToDelete chars (word)")
            return deleted
        }
    }

    private fun updateUI() {
        when (state) {
            State.IDLE -> {
                micButton?.setImageResource(R.drawable.ic_mic)
                micButton?.setBackgroundResource(R.drawable.mic_button_background)
                statusText?.text = getString(
                    if (isTapMode) R.string.tap_to_dictate else R.string.hold_to_dictate
                )
            }
            State.RECORDING -> {
                micButton?.setImageResource(R.drawable.ic_stop)
                micButton?.setBackgroundResource(R.drawable.mic_button_recording_background)
                statusText?.text = getString(R.string.recording)
            }
            State.PROCESSING -> {
                micButton?.setImageResource(R.drawable.ic_mic)
                micButton?.setBackgroundResource(R.drawable.mic_button_background)
                statusText?.text = getString(R.string.processing)
            }
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        backspaceHandler.removeCallbacks(backspaceRepeatRunnable)
        speechRecognizer?.destroy()
        speechRecognizer = null
        whisperTranscriber?.release()
        whisperTranscriber = null
        serviceScope.cancel()
        super.onDestroy()
    }
}
