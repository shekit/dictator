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
import java.util.concurrent.Executors

/**
 * Dictator Input Method Service - a minimal dictation keyboard.
 *
 * Two recording modes (configurable in main app settings):
 * - Hold-to-talk (default): press and hold mic, speak, release to stop.
 * - Tap-to-toggle: tap to start, tap again to stop.
 */
class DictatorIME : InputMethodService() {

    companion object {
        private const val TAG = "DictatorIME"
        const val PREFS_NAME = "dictator_prefs"
        const val KEY_TAP_MODE = "tap_mode"
    }

    enum class State {
        IDLE,
        RECORDING,
        PROCESSING
    }

    private var isTapMode = false
    private var state = State.IDLE
    // Tracks whether the user still wants to record (hasn't lifted finger / tapped stop).
    // SpeechRecognizer may auto-stop on silence, but we auto-restart if this is true.
    private var userWantsRecording = false

    private var micButton: ImageButton? = null
    private var settingsButton: ImageButton? = null
    private var backspaceButton: ImageButton? = null
    private var statusText: TextView? = null

    private var speechRecognizer: SpeechRecognizer? = null

    // Session tracking for stats
    private var recordingStartTime = 0L
    private val sessionTexts = mutableListOf<String>()
    private val dbExecutor = Executors.newSingleThreadExecutor()

    // Backspace: deferred delete with swipe gestures (up=space, down=enter)
    //
    // On touch-down nothing visible happens. The gesture resolves on:
    //   - Swipe up/down detected: insert space/enter (no delete ever fires)
    //   - Finger lift with no swipe: delete one word instantly
    //   - Hold 150ms with no swipe: start deleting + accelerating repeat
    private val backspaceHandler = Handler(Looper.getMainLooper())
    private val backspaceHoldDelay = 150L
    private val backspaceStartInterval = 200L
    private val backspaceMinInterval = 40L
    private val backspaceAccelStep = 20L
    private var backspaceCurrentInterval = backspaceStartInterval
    private var backspaceHoldFired = false

    private val backspaceFirstDeleteRunnable = Runnable {
        backspaceHoldFired = true
        backspaceCurrentInterval = backspaceStartInterval
        deleteWord()
        backspaceHandler.postDelayed(backspaceRepeatRunnable, backspaceCurrentInterval)
    }

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

    private enum class BackspaceGesture { NONE, SWIPE_UP, SWIPE_DOWN, SWIPE_RIGHT }
    private var backspaceTouchDownX = 0f
    private var backspaceTouchDownY = 0f
    private var backspaceGesture = BackspaceGesture.NONE
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
        initSpeechRecognizer()

        updateUI()
        return view
    }

    override fun onStartInputView(info: android.view.inputmethod.EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        loadSettings()
        updateUI()
    }

    private fun loadSettings() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isTapMode = prefs.getBoolean(KEY_TAP_MODE, false)
    }

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
                if (sessionTexts.isNotEmpty()) saveDictationSession()
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
                sessionTexts.add(text)
            }

            if (userWantsRecording) {
                Log.d(TAG, "Auto-restarting SpeechRecognizer (user still recording)")
                state = State.RECORDING
                speechRecognizer?.startListening(createRecognizerIntent())
            } else {
                saveDictationSession()
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

    // --- Recording control ---

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
        recordingStartTime = System.currentTimeMillis()
        sessionTexts.clear()
        userWantsRecording = true
        state = State.RECORDING
        updateUI()
        speechRecognizer?.startListening(createRecognizerIntent())
    }

    private fun stopRecording() {
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

    private fun saveDictationSession() {
        if (sessionTexts.isEmpty()) return
        val fullText = sessionTexts.joinToString(" ")
        val wordCount = fullText.split("\\s+".toRegex()).filter { it.isNotEmpty() }.size
        val durationMs = System.currentTimeMillis() - recordingStartTime
        val wpm = if (durationMs > 0) ((wordCount.toLong() * 60_000) / durationMs).toInt() else 0

        val session = DictationSession(
            timestamp = recordingStartTime,
            text = fullText,
            wordCount = wordCount,
            durationMs = durationMs,
            wpm = wpm
        )
        dbExecutor.execute {
            DictatorDatabase.getInstance(this).dictationSessionDao().insert(session)
            Log.d(TAG, "Session saved: $wordCount words, ${durationMs}ms, $wpm WPM")
        }
        sessionTexts.clear()
    }

    private fun onBackspaceTouch(event: MotionEvent): Boolean {
        val swipeThresholdPx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, swipeThresholdDp, resources.displayMetrics
        )

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                backspaceTouchDownX = event.rawX
                backspaceTouchDownY = event.rawY
                backspaceGesture = BackspaceGesture.NONE
                backspaceHoldFired = false
                // Don't delete yet — wait to see if this is a swipe or a tap
                backspaceHandler.postDelayed(backspaceFirstDeleteRunnable, backspaceHoldDelay)
            }
            MotionEvent.ACTION_MOVE -> {
                if (backspaceHoldFired) return true // already deleting, ignore swipe
                val dx = event.rawX - backspaceTouchDownX
                val dy = event.rawY - backspaceTouchDownY
                val newGesture = when {
                    dx > swipeThresholdPx -> BackspaceGesture.SWIPE_RIGHT
                    dy < -swipeThresholdPx -> BackspaceGesture.SWIPE_UP
                    dy > swipeThresholdPx -> BackspaceGesture.SWIPE_DOWN
                    else -> BackspaceGesture.NONE
                }
                if (newGesture != BackspaceGesture.NONE && backspaceGesture == BackspaceGesture.NONE) {
                    // Swipe detected — cancel pending delete, commit to swipe
                    backspaceHandler.removeCallbacks(backspaceFirstDeleteRunnable)
                    backspaceGesture = newGesture
                    backspaceButton?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    Log.d(TAG, "Backspace swipe detected: $newGesture")
                }
            }
            MotionEvent.ACTION_UP -> {
                backspaceHandler.removeCallbacks(backspaceFirstDeleteRunnable)
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
                    BackspaceGesture.SWIPE_RIGHT -> {
                        val ic = currentInputConnection
                        ic?.commitText(".", 1)
                        Log.d(TAG, "Swipe right: inserted period")
                    }
                    BackspaceGesture.NONE -> {
                        // Quick tap — delete now if hold timer hasn't fired yet
                        if (!backspaceHoldFired) {
                            deleteWord()
                        }
                    }
                }
                backspaceGesture = BackspaceGesture.NONE
            }
            MotionEvent.ACTION_CANCEL -> {
                backspaceHandler.removeCallbacks(backspaceFirstDeleteRunnable)
                backspaceHandler.removeCallbacks(backspaceRepeatRunnable)
                backspaceGesture = BackspaceGesture.NONE
            }
        }
        return true
    }

    private fun deleteWord() {
        val ic = currentInputConnection ?: return

        val selected = ic.getSelectedText(0)
        if (selected != null && selected.isNotEmpty()) {
            ic.commitText("", 1)
            Log.d(TAG, "Deleted selection (${selected.length} chars)")
            return
        }

        val before = ic.getTextBeforeCursor(100, 0) ?: return
        if (before.isEmpty()) return

        val text = before.toString()
        val end = text.length

        val lastChar = text[end - 1]
        if (lastChar == '\n') {
            // Delete exactly one newline at a time
            ic.deleteSurroundingText(1, 0)
            Log.d(TAG, "Deleted 1 newline")
        } else if (lastChar.isWhitespace()) {
            // Group consecutive non-newline whitespace (spaces, tabs)
            var i = end
            while (i > 0 && text[i - 1].isWhitespace() && text[i - 1] != '\n') i--
            val count = end - i
            ic.deleteSurroundingText(count, 0)
            Log.d(TAG, "Deleted $count whitespace chars")
        } else if (!lastChar.isLetterOrDigit()) {
            // Punctuation: delete one character at a time
            ic.deleteSurroundingText(1, 0)
            Log.d(TAG, "Deleted 1 punctuation char '$lastChar'")
        } else {
            // Word: delete back to whitespace or punctuation
            var i = end
            while (i > 0 && text[i - 1].isLetterOrDigit()) i--
            val count = end - i
            ic.deleteSurroundingText(count, 0)
            Log.d(TAG, "Deleted $count chars (word)")
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
        backspaceHandler.removeCallbacks(backspaceFirstDeleteRunnable)
        backspaceHandler.removeCallbacks(backspaceRepeatRunnable)
        speechRecognizer?.destroy()
        speechRecognizer = null
        super.onDestroy()
    }
}
