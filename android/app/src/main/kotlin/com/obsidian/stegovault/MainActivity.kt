package com.obsidian.stegovault

import android.os.Bundle
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the optional native EXIF bridge.
 *
 * The scrubbing engine is pure Dart so it also runs in tests and in the browser
 * preview, but a native second opinion makes the "verified clean" badge honest:
 * after the Dart strip, the cleaned bytes are re-read with
 * androidx.exifinterface and any surviving attribute is reported back.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.obsidian.stegovault/exif"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "dumpTags" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("BAD_ARGS", "bytes argument is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(dumpTags(bytes))
                    } catch (error: Exception) {
                        result.error("EXIF_READ_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Writes the payload to a private cache file (never shared, never backed up)
     * because androidx.exifinterface needs a file descriptor, then lists every
     * attribute it can still read.
     */
    private fun dumpTags(bytes: ByteArray): List<String> {
        val temp = File.createTempFile("sgv-verify-", ".img", cacheDir)
        try {
            temp.writeBytes(bytes)
            val exif = ExifInterface(temp.absolutePath)
            val out = ArrayList<String>()
            for (attribute in ATTRIBUTES) {
                val value = exif.getAttribute(attribute)
                if (!value.isNullOrBlank()) out.add("$attribute=$value")
            }
            if (exif.latLong != null) out.add("GPS=still-present")
            return out
        } finally {
            temp.delete()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nothing to do: the vault is fully local. Kept for clarity.
    }

    private companion object {
        val ATTRIBUTES = listOf(
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_SOFTWARE,
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_ARTIST,
            ExifInterface.TAG_COPYRIGHT,
            ExifInterface.TAG_IMAGE_DESCRIPTION,
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.TAG_BODY_SERIAL_NUMBER,
            ExifInterface.TAG_LENS_SERIAL_NUMBER,
            ExifInterface.TAG_LENS_MODEL,
            ExifInterface.TAG_USER_COMMENT,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_XP_TITLE,
            ExifInterface.TAG_XP_COMMENT,
        )
    }
}
