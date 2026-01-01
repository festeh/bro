package com.github.festeh.bro.storage

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.UUID

data class SegmentMetadata(
    val id: String,
    val timestamp: Long,
    val durationMs: Long,
    val waveform: List<Double>
)

class SegmentDatabase(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    companion object {
        private const val DATABASE_NAME = "segments.db"
        private const val DATABASE_VERSION = 3  // Fresh start, no migration

        private const val TABLE_SEGMENTS = "segments"
        private const val COL_ID = "id"
        private const val COL_TIMESTAMP = "timestamp"
        private const val COL_DURATION_MS = "duration_ms"
        private const val COL_WAVEFORM = "waveform"
        private const val COL_AUDIO = "audio"  // Raw Opus frames
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE $TABLE_SEGMENTS (
                $COL_ID TEXT PRIMARY KEY,
                $COL_TIMESTAMP INTEGER NOT NULL,
                $COL_DURATION_MS INTEGER NOT NULL,
                $COL_WAVEFORM BLOB,
                $COL_AUDIO BLOB NOT NULL
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // No migration - just recreate
        db.execSQL("DROP TABLE IF EXISTS $TABLE_SEGMENTS")
        onCreate(db)
    }

    fun insert(
        id: UUID,
        timestamp: Long,
        durationMs: Long,
        waveform: DoubleArray,
        audio: ByteArray
    ): Boolean {
        val db = writableDatabase
        val values = ContentValues().apply {
            put(COL_ID, id.toString())
            put(COL_TIMESTAMP, timestamp)
            put(COL_DURATION_MS, durationMs)
            put(COL_WAVEFORM, waveformToBytes(waveform))
            put(COL_AUDIO, audio)
        }
        val result = db.insertWithOnConflict(
            TABLE_SEGMENTS,
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE
        )
        return result != -1L
    }

    fun exists(id: UUID): Boolean {
        val db = readableDatabase
        val cursor = db.query(
            TABLE_SEGMENTS,
            arrayOf(COL_ID),
            "$COL_ID = ?",
            arrayOf(id.toString()),
            null, null, null
        )
        val exists = cursor.count > 0
        cursor.close()
        return exists
    }

    fun getAll(): List<SegmentMetadata> {
        val db = readableDatabase
        val cursor = db.query(
            TABLE_SEGMENTS,
            arrayOf(COL_ID, COL_TIMESTAMP, COL_DURATION_MS, COL_WAVEFORM),
            null, null, null, null,
            "$COL_TIMESTAMP DESC"
        )

        val segments = mutableListOf<SegmentMetadata>()
        while (cursor.moveToNext()) {
            val id = cursor.getString(cursor.getColumnIndexOrThrow(COL_ID))
            val timestamp = cursor.getLong(cursor.getColumnIndexOrThrow(COL_TIMESTAMP))
            val durationMs = cursor.getLong(cursor.getColumnIndexOrThrow(COL_DURATION_MS))
            val waveformBytes = cursor.getBlob(cursor.getColumnIndexOrThrow(COL_WAVEFORM))
            val waveform = bytesToWaveform(waveformBytes)

            segments.add(SegmentMetadata(id, timestamp, durationMs, waveform))
        }
        cursor.close()
        return segments
    }

    fun getAudio(id: UUID): ByteArray? {
        val db = readableDatabase
        val cursor = db.query(
            TABLE_SEGMENTS,
            arrayOf(COL_AUDIO),
            "$COL_ID = ?",
            arrayOf(id.toString()),
            null, null, null
        )

        val audio = if (cursor.moveToFirst()) {
            cursor.getBlob(cursor.getColumnIndexOrThrow(COL_AUDIO))
        } else {
            null
        }
        cursor.close()
        return audio
    }

    fun delete(id: UUID): Boolean {
        val db = writableDatabase
        val deleted = db.delete(
            TABLE_SEGMENTS,
            "$COL_ID = ?",
            arrayOf(id.toString())
        )
        return deleted > 0
    }

    fun clearAll(): Int {
        val db = writableDatabase
        return db.delete(TABLE_SEGMENTS, null, null)
    }

    private fun waveformToBytes(waveform: DoubleArray): ByteArray {
        val buffer = java.nio.ByteBuffer.allocate(waveform.size * 8)
        waveform.forEach { buffer.putDouble(it) }
        return buffer.array()
    }

    private fun bytesToWaveform(bytes: ByteArray?): List<Double> {
        if (bytes == null || bytes.isEmpty()) return emptyList()
        val buffer = java.nio.ByteBuffer.wrap(bytes)
        val waveform = mutableListOf<Double>()
        while (buffer.remaining() >= 8) {
            waveform.add(buffer.double)
        }
        return waveform
    }
}
