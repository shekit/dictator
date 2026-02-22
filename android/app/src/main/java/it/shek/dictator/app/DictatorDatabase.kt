package it.shek.dictator.app

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [DictationSession::class], version = 1, exportSchema = false)
abstract class DictatorDatabase : RoomDatabase() {
    abstract fun dictationSessionDao(): DictationSessionDao

    companion object {
        @Volatile
        private var instance: DictatorDatabase? = null

        fun getInstance(context: Context): DictatorDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    DictatorDatabase::class.java,
                    "dictator.db"
                ).build().also { instance = it }
            }
        }
    }
}
