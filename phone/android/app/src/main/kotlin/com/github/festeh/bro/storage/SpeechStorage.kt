package com.github.festeh.bro.storage

import android.content.Context
import android.util.Log
import java.io.File
import java.util.UUID

/**
 * Manages storage of speech segments received from the watch.
 */
class SpeechStorage(private val context: Context) {

    companion object {
        private const val TAG = "SpeechStorage"
        private const val SPEECH_DIR = "speech"
    }

    private val speechDir: File by lazy {
        File(context.filesDir, SPEECH_DIR).also { it.mkdirs() }
    }

    /**
     * Save an Opus-encoded speech segment to storage.
     *
     * @param id The segment UUID
     * @param opusData The Opus-encoded audio data
     * @param startTime Original start time (epoch ms)
     * @param endTime Original end time (epoch ms)
     * @return The saved file, or null if save failed
     */
    fun save(
        id: UUID,
        opusData: ByteArray,
        startTime: Long,
        endTime: Long
    ): File? {
        return try {
            // Filename: {timestamp}_{uuid}.opus
            val filename = "${startTime}_${id}.opus"
            val file = File(speechDir, filename)

            // Atomic write: write to temp file first, then rename
            val tempFile = File(speechDir, "$filename.tmp")
            tempFile.writeBytes(opusData)
            tempFile.renameTo(file)

            Log.d(TAG, "Saved segment $id: ${file.absolutePath} (${opusData.size} bytes)")
            file
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save segment $id", e)
            null
        }
    }

    /**
     * List all saved speech files, sorted by timestamp (oldest first).
     */
    fun listAll(): List<File> {
        return speechDir.listFiles { file -> file.extension == "opus" }
            ?.sortedBy { it.name }
            ?: emptyList()
    }

    /**
     * Delete a speech file.
     */
    fun delete(file: File): Boolean {
        return file.delete().also { success ->
            if (success) {
                Log.d(TAG, "Deleted ${file.name}")
            } else {
                Log.e(TAG, "Failed to delete ${file.name}")
            }
        }
    }

    /**
     * Get total storage used by speech files in bytes.
     */
    fun getStorageUsed(): Long {
        return speechDir.listFiles()?.sumOf { it.length() } ?: 0L
    }
}
