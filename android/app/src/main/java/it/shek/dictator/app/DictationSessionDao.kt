package it.shek.dictator.app

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface DictationSessionDao {
    @Insert
    fun insert(session: DictationSession)

    @Query("SELECT * FROM dictation_sessions ORDER BY timestamp DESC")
    fun getAll(): List<DictationSession>

    @Query("SELECT * FROM dictation_sessions WHERE timestamp >= :startOfDay ORDER BY timestamp DESC")
    fun getToday(startOfDay: Long): List<DictationSession>

    @Query("SELECT COUNT(*) FROM dictation_sessions")
    fun getTotalCount(): Int

    @Query("SELECT SUM(wordCount) FROM dictation_sessions")
    fun getTotalWords(): Int?

    @Query("SELECT AVG(wpm) FROM dictation_sessions WHERE wpm > 0")
    fun getAverageWpm(): Double?

    @Query("SELECT SUM(wordCount) FROM dictation_sessions WHERE timestamp >= :startOfDay")
    fun getTodayWords(startOfDay: Long): Int?

    @Query("SELECT AVG(wpm) FROM dictation_sessions WHERE timestamp >= :startOfDay AND wpm > 0")
    fun getTodayAverageWpm(startOfDay: Long): Double?

    @Query("SELECT COUNT(*) FROM dictation_sessions WHERE timestamp >= :startOfDay")
    fun getTodayCount(startOfDay: Long): Int
}
