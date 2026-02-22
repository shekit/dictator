package it.shek.dictator.app

import android.annotation.SuppressLint
import android.inputmethodservice.InputMethodService
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.ImageButton
import android.widget.TextView

/**
 * Dictator Input Method Service - a minimal dictation keyboard.
 *
 * Two recording modes:
 * - Hold-to-talk (default): press and hold mic, speak, release to stop.
 * - Tap-to-toggle: tap to start, tap again to stop.
 *
 * Toggle between modes with the lock button next to the mic.
 */
class DictatorIME : InputMethodService() {

    companion object {
        private const val TAG = "DictatorIME"
    }

    enum class State {
        IDLE,
        RECORDING,
        PROCESSING
    }

    /** false = hold-to-talk (default), true = tap-to-toggle */
    private var isTapMode = false

    private var state = State.IDLE

    private var micButton: ImageButton? = null
    private var globeButton: ImageButton? = null
    private var modeToggle: ImageButton? = null
    private var statusText: TextView? = null

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreateInputView(): View {
        Log.d(TAG, "onCreateInputView")
        val view = layoutInflater.inflate(R.layout.keyboard_view, null)

        micButton = view.findViewById(R.id.micButton)
        globeButton = view.findViewById(R.id.globeButton)
        modeToggle = view.findViewById(R.id.modeToggle)
        statusText = view.findViewById(R.id.statusText)

        micButton?.setOnTouchListener { _, event -> onMicTouch(event) }
        globeButton?.setOnClickListener { onGlobeTapped() }
        modeToggle?.setOnClickListener { onModeToggleTapped() }

        updateUI()
        return view
    }

    private fun onMicTouch(event: MotionEvent): Boolean {
        if (state == State.PROCESSING) return true

        if (isTapMode) {
            // Tap-to-toggle: only act on ACTION_UP (completed tap)
            if (event.action == MotionEvent.ACTION_UP) {
                if (state == State.IDLE) {
                    startRecording()
                } else if (state == State.RECORDING) {
                    stopRecording()
                }
            }
        } else {
            // Hold-to-talk: press starts, release stops
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
        // Phase 15 will add actual recording
        Log.d(TAG, "Recording started (mode: ${if (isTapMode) "tap" else "hold"})")
        state = State.RECORDING
        updateUI()
    }

    private fun stopRecording() {
        Log.d(TAG, "Recording stopped (mode: ${if (isTapMode) "tap" else "hold"})")
        state = State.IDLE
        updateUI()
    }

    private fun onModeToggleTapped() {
        isTapMode = !isTapMode
        Log.d(TAG, "Mode toggled: ${if (isTapMode) "tap-to-toggle" else "hold-to-talk"}")
        if (state == State.RECORDING) {
            stopRecording()
        }
        updateUI()
    }

    private fun onGlobeTapped() {
        Log.d(TAG, "Globe tapped - switching keyboard")
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showInputMethodPicker()
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

        modeToggle?.setImageResource(
            if (isTapMode) R.drawable.ic_lock_open else R.drawable.ic_lock
        )
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }
}
