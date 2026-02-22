package it.shek.dictator.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.widget.ImageButton
import android.widget.TextView

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

    private var micButton: ImageButton? = null
    private var settingsButton: ImageButton? = null
    private var backspaceButton: ImageButton? = null
    private var statusText: TextView? = null

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
        backspaceButton?.setOnClickListener { deleteWord() }

        loadSettings()
        updateUI()
        return view
    }

    override fun onStartInputView(info: android.view.inputmethod.EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        // Reload settings each time the keyboard appears, in case user changed them
        loadSettings()
        updateUI()
    }

    private fun loadSettings() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isTapMode = prefs.getBoolean(KEY_TAP_MODE, false)
    }

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
        Log.d(TAG, "Recording started (mode: ${if (isTapMode) "tap" else "hold"})")
        state = State.RECORDING
        updateUI()
    }

    private fun stopRecording() {
        Log.d(TAG, "Recording stopped (mode: ${if (isTapMode) "tap" else "hold"})")
        state = State.IDLE
        updateUI()
    }

    private fun openSettings() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun deleteWord() {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(100, 0) ?: return
        if (before.isEmpty()) return

        val text = before.toString()
        val end = text.length

        // If trailing spaces exist, delete just the spaces
        if (text[end - 1] == ' ') {
            var i = end
            while (i > 0 && text[i - 1] == ' ') i--
            val spacesToDelete = end - i
            ic.deleteSurroundingText(spacesToDelete, 0)
            Log.d(TAG, "Deleted $spacesToDelete spaces")
        } else {
            // No trailing spaces - delete the word back to the previous space
            var i = end
            while (i > 0 && text[i - 1] != ' ') i--
            val charsToDelete = end - i
            ic.deleteSurroundingText(charsToDelete, 0)
            Log.d(TAG, "Deleted $charsToDelete chars (word)")
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
                statusText?.text = getString(R.string.processing)
            }
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }
}
