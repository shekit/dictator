package it.shek.dictator.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.switchmaterial.SwitchMaterial
import com.google.android.material.tabs.TabLayout
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private val dbExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

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

        // Tabs
        val tabLayout = findViewById<TabLayout>(R.id.tabLayout)
        val homeTab = findViewById<ScrollView>(R.id.homeTab)
        val transcriptionsTab = findViewById<ScrollView>(R.id.transcriptionsTab)

        tabLayout.addTab(tabLayout.newTab().setText("Home"))
        tabLayout.addTab(tabLayout.newTab().setText("Transcriptions"))

        tabLayout.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab) {
                when (tab.position) {
                    0 -> {
                        homeTab.visibility = View.VISIBLE
                        transcriptionsTab.visibility = View.GONE
                    }
                    1 -> {
                        homeTab.visibility = View.GONE
                        transcriptionsTab.visibility = View.VISIBLE
                    }
                }
            }
            override fun onTabUnselected(tab: TabLayout.Tab) {}
            override fun onTabReselected(tab: TabLayout.Tab) {}
        })
    }

    override fun onResume() {
        super.onResume()
        updateKeyboardStatus()
        loadStats()
    }

    private fun updateKeyboardStatus() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        val enabled = imm.enabledInputMethodList.any {
            it.packageName == packageName
        }
        findViewById<LinearLayout>(R.id.setupSection).visibility =
            if (enabled) View.GONE else View.VISIBLE
    }

    private fun loadStats() {
        dbExecutor.execute {
            val dao = DictatorDatabase.getInstance(this).dictationSessionDao()

            val startOfDay = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis

            val todayWords = dao.getTodayWords(startOfDay) ?: 0
            val todayWpm = dao.getTodayAverageWpm(startOfDay)?.toInt() ?: 0
            val todayCount = dao.getTodayCount(startOfDay)

            val allWords = dao.getTotalWords() ?: 0
            val allWpm = dao.getAverageWpm()?.toInt() ?: 0
            val allCount = dao.getTotalCount()

            val sessions = dao.getAll()

            runOnUiThread {
                findViewById<TextView>(R.id.todayWords).text = todayWords.toString()
                findViewById<TextView>(R.id.todayWpm).text = todayWpm.toString()
                findViewById<TextView>(R.id.todaySessions).text = todayCount.toString()

                findViewById<TextView>(R.id.allTimeWords).text = allWords.toString()
                findViewById<TextView>(R.id.allTimeWpm).text = allWpm.toString()
                findViewById<TextView>(R.id.allTimeSessions).text = allCount.toString()

                val noTranscriptions = findViewById<TextView>(R.id.noTranscriptions)
                val container = findViewById<LinearLayout>(R.id.transcriptionsContainer)
                container.removeAllViews()

                if (sessions.isEmpty()) {
                    noTranscriptions.visibility = View.VISIBLE
                } else {
                    noTranscriptions.visibility = View.GONE
                    for (session in sessions) {
                        container.addView(createSessionCard(session))
                    }
                }
            }
        }
    }

    private fun createSessionCard(session: DictationSession): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            setBackgroundColor(0xFF2C2C2E.toInt())
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.bottomMargin = dp(8)
            layoutParams = params
        }

        val dateFormat = SimpleDateFormat("MMM d, h:mm a", Locale.getDefault())
        val durationSec = session.durationMs / 1000
        val meta = "${dateFormat.format(Date(session.timestamp))}  \u00b7  " +
                "${session.wordCount} words  \u00b7  ${session.wpm} WPM  \u00b7  ${durationSec}s"

        val metaText = TextView(this).apply {
            text = meta
            setTextColor(0xFF8E8E93.toInt())
            textSize = 12f
        }
        card.addView(metaText)

        val bodyText = TextView(this).apply {
            text = session.text
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 14f
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.topMargin = dp(6)
            layoutParams = params
        }
        card.addView(bodyText)

        return card
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun updateModeDescription(tv: TextView, isTapMode: Boolean) {
        tv.text = if (isTapMode) {
            "Tap mic to start recording, tap again to stop"
        } else {
            "Hold mic button to record, release to stop"
        }
    }
}
