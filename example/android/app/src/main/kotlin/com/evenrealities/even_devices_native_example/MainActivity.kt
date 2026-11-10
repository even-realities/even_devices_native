package com.evenrealities.even_devices_native_example

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.io.IOException
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Persists demo UI metadata; BLE ownership and license validation stay in the SDK. */
class MainActivity : FlutterActivity() {
    // ACTION_OPEN_DOCUMENT grants read access to just the user-selected firmware.
    private var firmwareChannel: MethodChannel? = null
    private var firmwareResult: MethodChannel.Result? = null
    private val firmwareRequest = 0x3E02
    private val maxFirmwareBytes = 32 * 1024 * 1024
    private var historyChannel: MethodChannel? = null
    private var historyExecutor: ExecutorService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        firmwareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "even_devices_native_example/firmware").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when {
                    call.method != "pick" -> result.notImplemented()
                    firmwareResult != null -> result.error("busy", "A document picker is active.", null)
                    else -> {
                        firmwareResult = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*" // Many document providers omit a MIME type for .bin.
                            }, firmwareRequest)
                        } catch (_: RuntimeException) {
                            firmwareResult = null
                            result.error("pickerUnavailable", "Document picker unavailable.", null)
                        }
                    }
                }
            }
        }
        val preferences = applicationContext.getSharedPreferences("device_history", Context.MODE_PRIVATE)
        val main = Handler(Looper.getMainLooper())
        // One queue preserves save/clear/load order without blocking Flutter's UI thread.
        val executor = Executors.newSingleThreadExecutor()
        historyExecutor = executor
        historyChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "even_devices_native_example/history",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method !in setOf("load", "save", "clear")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val arguments = call.arguments as? Map<*, *>
                val namespace = arguments?.get("namespace") as? String
                val record = arguments?.get("record") as? String
                if (namespace.isNullOrBlank() ||
                    (call.method == "save" &&
                        (record.isNullOrEmpty() || record.toByteArray(Charsets.UTF_8).size > 8192))
                ) {
                    result.error("invalidHistoryArguments", "Invalid history arguments", null)
                    return@setMethodCallHandler
                }
                // Keep the exact namespace, including case and surrounding spaces.
                val key = "lastG2.$namespace"
                executor.execute {
                    try {
                        val value = when (call.method) {
                            "load" -> preferences.getString(key, null)
                            "save" -> {
                                check(preferences.edit().putString(key, record).commit())
                                null
                            }
                            else -> {
                                check(preferences.edit().remove(key).commit())
                                null
                            }
                        }
                        // A successful write reply means commit completed; no payload enters logs.
                        main.post { result.success(value) }
                    } catch (_: RuntimeException) {
                        main.post { result.error("historyStorageFailed", "History storage failed", null) }
                    }
                }
            }
        }
    }

    @Deprecated("FlutterActivity forwards document picker results here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != firmwareRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = firmwareResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            firmwareResult = null
            result.success(null)
            return
        }
        // The provider may stream remote documents or omit their length. Count
        // actual bytes off-main and deliver only while this engine owns the picker.
        val executor = historyExecutor ?: return
        executor.execute {
            try {
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                    null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
                require(name != null && name.endsWith(".bin", ignoreCase = true))
                val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                    val out = ByteArrayOutputStream()
                    val chunk = ByteArray(64 * 1024)
                    while (true) {
                        val count = stream.read(chunk)
                        if (count == -1) break
                        require(out.size() + count <= maxFirmwareBytes)
                        out.write(chunk, 0, count)
                    }
                    out.toByteArray()
                } ?: throw IOException("No stream")
                require(bytes.isNotEmpty())
                runOnUiThread {
                    if (firmwareResult === result) {
                        firmwareResult = null
                        result.success(mapOf("name" to name, "bytes" to bytes))
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (firmwareResult === result) {
                        firmwareResult = null
                        result.error(if (error is IllegalArgumentException) "invalidFirmwareFile" else "fileReadFailed",
                            "Cannot load firmware.", null)
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        firmwareChannel?.setMethodCallHandler(null)
        firmwareChannel = null
        firmwareResult?.error("detached", "The document picker was detached.", null)
        firmwareResult = null
        historyChannel?.setMethodCallHandler(null)
        historyChannel = null
        // Finish admitted tiny writes, but release the queue when this engine detaches.
        historyExecutor?.shutdown()
        historyExecutor = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
