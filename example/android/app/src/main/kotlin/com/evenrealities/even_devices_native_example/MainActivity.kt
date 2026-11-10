package com.evenrealities.even_devices_native_example

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Persists demo UI metadata; BLE ownership and license validation stay in the SDK. */
class MainActivity : FlutterActivity() {
    private var historyChannel: MethodChannel? = null
    private var historyExecutor: ExecutorService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        historyChannel?.setMethodCallHandler(null)
        historyChannel = null
        // Finish admitted tiny writes, but release the queue when this engine detaches.
        historyExecutor?.shutdown()
        historyExecutor = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
