package it.shek.dictator.app

import android.inputmethodservice.InputMethodService
import android.util.Log
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.ImageButton
import android.widget.TextView

/**
 * Dictator Input Method Service - a minimal dictation keyboard.
 *
 * Shows a mic button (for future dictation) and a globe button to switch keyboards.
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

    private var state = State.IDLE

    private var micButton: ImageButton? = null
    private var globeButton: ImageButton? = null
    private var statusText: TextView? = null

    override fun onCreateInputView(): View {
        Log.d(TAG, "onCreateInputView")
        val view = layoutInflater.inflate(R.layout.keyboard_view, null)

        micButton = view.findViewById(R.id.micButton)
        globeButton = view.findViewById(R.id.globeButton)
        statusText = view.findViewById(R.id.statusText)

        micButton?.setOnClickListener { onMicTapped() }
        globeButton?.setOnClickListener { onGlobeTapped() }

        updateUI()
        return view
    }

    private fun onMicTapped() {
        when (state) {
            State.IDLE -> {
                // Phase 15 will add actual recording
                Log.d(TAG, "Mic tapped - would start recording (not yet implemented)")
                state = State.RECORDING
                updateUI()
            }
            State.RECORDING -> {
                Log.d(TAG, "Mic tapped - would stop recording (not yet implemented)")
                state = State.IDLE
                updateUI()
            }
            State.PROCESSING -> {
                Log.d(TAG, "Mic tapped while processing - ignored")
            }
        }
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
                statusText?.text = getString(R.string.tap_to_dictate)
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
