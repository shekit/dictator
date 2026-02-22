package it.shek.dictator.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.switchmaterial.SwitchMaterial

/**
 * Main activity for setup, onboarding, and settings.
 */
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<MaterialButton>(R.id.enableKeyboardButton).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }

        val prefs = getSharedPreferences(DictatorIME.PREFS_NAME, Context.MODE_PRIVATE)
        val tapModeSwitch = findViewById<SwitchMaterial>(R.id.tapModeSwitch)
        val description = findViewById<TextView>(R.id.recordingModeDescription)

        // Load current setting
        val isTapMode = prefs.getBoolean(DictatorIME.KEY_TAP_MODE, false)
        tapModeSwitch.isChecked = isTapMode
        updateModeDescription(description, isTapMode)

        tapModeSwitch.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean(DictatorIME.KEY_TAP_MODE, isChecked).apply()
            updateModeDescription(description, isChecked)
        }
    }

    private fun updateModeDescription(tv: TextView, isTapMode: Boolean) {
        tv.text = if (isTapMode) {
            "Tap mic to start recording, tap again to stop"
        } else {
            "Hold mic button to record, release to stop"
        }
    }
}
