package it.shek.dictator.app

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "dictation_sessions")
data class DictationSession(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,       // epoch millis
    val text: String,
    val wordCount: Int,
    val durationMs: Long,      // recording duration in millis
    val wpm: Int               // words per minute
)
