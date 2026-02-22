package it.shek.dictator.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.switchmaterial.SwitchMaterial
import kotlinx.coroutines.*

class MainActivity : AppCompatActivity() {

    private lateinit var modelManager: ModelManager
    private var downloadJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        modelManager = ModelManager(this)

        // Setup button
        findViewById<MaterialButton>(R.id.enableKeyboardButton).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }

        // Recording mode toggle
        val prefs = getSharedPreferences(DictatorIME.PREFS_NAME, Context.MODE_PRIVATE)
        val tapModeSwitch = findViewById<SwitchMaterial>(R.id.tapModeSwitch)
        val description = findViewById<TextView>(R.id.recordingModeDescription)

        val isTapMode = prefs.getBoolean(DictatorIME.KEY_TAP_MODE, false)
        tapModeSwitch.isChecked = isTapMode
        updateModeDescription(description, isTapMode)

        tapModeSwitch.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean(DictatorIME.KEY_TAP_MODE, isChecked).apply()
            updateModeDescription(description, isChecked)
        }

        // STT engine selection
        val sttEngineGroup = findViewById<RadioGroup>(R.id.sttEngineGroup)
        val radioSpeechRecognizer = findViewById<RadioButton>(R.id.radioSpeechRecognizer)
        val radioWhisper = findViewById<RadioButton>(R.id.radioWhisper)
        val whisperModelSection = findViewById<LinearLayout>(R.id.whisperModelSection)

        val currentEngine = prefs.getString(DictatorIME.KEY_STT_ENGINE, DictatorIME.STT_SPEECH_RECOGNIZER)
        if (currentEngine == DictatorIME.STT_WHISPER) {
            radioWhisper.isChecked = true
            whisperModelSection.visibility = View.VISIBLE
        } else {
            radioSpeechRecognizer.isChecked = true
            whisperModelSection.visibility = View.GONE
        }

        sttEngineGroup.setOnCheckedChangeListener { _, checkedId ->
            when (checkedId) {
                R.id.radioSpeechRecognizer -> {
                    prefs.edit().putString(DictatorIME.KEY_STT_ENGINE, DictatorIME.STT_SPEECH_RECOGNIZER).apply()
                    whisperModelSection.visibility = View.GONE
                }
                R.id.radioWhisper -> {
                    prefs.edit().putString(DictatorIME.KEY_STT_ENGINE, DictatorIME.STT_WHISPER).apply()
                    whisperModelSection.visibility = View.VISIBLE
                    updateModelStatus()
                }
            }
        }

        // Model management
        val modelActionButton = findViewById<MaterialButton>(R.id.modelActionButton)
        modelActionButton.setOnClickListener { onModelActionClicked() }

        updateModelStatus()
    }

    private fun updateModeDescription(tv: TextView, isTapMode: Boolean) {
        tv.text = if (isTapMode) {
            "Tap mic to start recording, tap again to stop"
        } else {
            "Hold mic button to record, release to stop"
        }
    }

    private fun updateModelStatus() {
        val statusText = findViewById<TextView>(R.id.modelStatusText)
        val actionButton = findViewById<MaterialButton>(R.id.modelActionButton)
        val progressBar = findViewById<ProgressBar>(R.id.modelProgressBar)

        if (modelManager.isModelDownloaded) {
            val sizeMB = modelManager.getModelSizeMB()
            statusText.text = "${ModelManager.MODEL_DISPLAY_NAME} ($sizeMB MB)"
            actionButton.text = "Delete Model"
            actionButton.isEnabled = true
            progressBar.visibility = View.GONE
        } else {
            statusText.text = "Not downloaded"
            actionButton.text = "Download Model (~${ModelManager.MODEL_SIZE_MB} MB)"
            actionButton.isEnabled = true
            progressBar.visibility = View.GONE
        }
    }

    private fun onModelActionClicked() {
        if (modelManager.isModelDownloaded) {
            modelManager.deleteModel()
            updateModelStatus()
        } else {
            downloadModel()
        }
    }

    private fun downloadModel() {
        val statusText = findViewById<TextView>(R.id.modelStatusText)
        val actionButton = findViewById<MaterialButton>(R.id.modelActionButton)
        val progressBar = findViewById<ProgressBar>(R.id.modelProgressBar)

        actionButton.isEnabled = false
        actionButton.text = "Downloading\u2026"
        progressBar.visibility = View.VISIBLE
        progressBar.progress = 0

        downloadJob = CoroutineScope(Dispatchers.Main).launch {
            val success = modelManager.downloadModel { progress ->
                progressBar.progress = progress
                statusText.text = "Downloading\u2026 $progress%"
            }

            if (success) {
                statusText.text = "Download complete"
            } else {
                statusText.text = "Download failed. Check your connection."
            }
            updateModelStatus()
        }
    }

    override fun onDestroy() {
        downloadJob?.cancel()
        super.onDestroy()
    }
}
