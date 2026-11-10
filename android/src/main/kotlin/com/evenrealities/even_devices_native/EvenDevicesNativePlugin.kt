package com.evenrealities.even_devices_native

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.evenrealities.devices.EnterpriseLicenseBundle
import com.evenrealities.devices.EvenDevicesAndroidBle
import com.evenrealities.devices.G2Endpoint
import com.evenrealities.devices.G2EvenHubException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

/** Adapts Flutter messages to the standalone G2 SDK without owning a BLE state machine. */
class EvenDevicesNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private val sdk = EvenDevicesAndroidBle.instance
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterPlugin.FlutterPluginBinding? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var activity: ActivityPluginBinding? = null
    private var pendingPermissions: MethodChannel.Result? = null
    private val permissionRequestCode = nextPermissionRequest.getAndIncrement()
    private var namespace: String? = null
    private var pair: Pair<G2Endpoint, G2Endpoint>? = null
    private var pairSn: String? = null
    // Native callbacks can originate off-main; posted results must retain their original owner.
    @Volatile private var epoch = 0L
    @Volatile private var connectionRevision = 0L
    @Volatile private var subscriptionRevision = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine = binding
        methods = MethodChannel(binding.binaryMessenger, "even_devices_native/methods")
            .also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "even_devices_native/events")
            .also { it.setStreamHandler(this) }
    }

    /** An unused engine must never reset the SDK owned by a different engine. */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        retireOwnedSdk()
        finishPermissions(false)
        detachActivity()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        sink = null
        subscriptionRevision++
        engine = null
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        subscriptionRevision++
        sink = eventSink
    }

    /** Stream cancellation releases only the subscriber, retaining the native BLE session. */
    override fun onCancel(arguments: Any?) {
        subscriptionRevision++
        sink = null
    }

    /** Validate complete input before crossing into native BLE or replacing an existing owner. */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> initialize(call, result)
                "requestBluetoothPermissions" -> requestPermissions(result)
                "reset" -> { retireOwnedSdk(); result.success(null) }
                "updateLicenses" -> {
                    requireOwner()
                    sdk.updateLicenses(licenses(call))
                    result.success(null)
                }
                "scan" -> {
                    requireOwner()
                    // Native can reject scanner admission without throwing (for example,
                    // Bluetooth off). Preserve that result instead of acknowledging success.
                    val submission = sdk.scan()
                    if (submission["started"] == true) result.success(null) else {
                        result.error("scanNotStarted", "The native SDK did not start scanning.", normalize(submission))
                    }
                }
                "stopScan" -> { requireOwner(); sdk.stopScan(); result.success(null) }
                "connectG2" -> connect(call, result)
                "disconnectG2" -> {
                    requireOwner()
                    connectionRevision++
                    pair?.let { sdk.disconnectG2(it.first, it.second) }
                    pair = null
                    pairSn = null
                    result.success(null)
                }
                "syncG2Time" -> {
                    requireOwner()
                    val right = pair?.second ?: throw BridgeFailure("notConnected", "No G2 pair is selected.")
                    sdk.syncG2Time(right.address)
                    // Native completion reports its operation ID through the timeSync event.
                    result.success(null)
                }
                "openEvenHubTextPage" -> {
                    requireOwner()
                    // Text byte limits, READY admission, packet creation and the lease are native.
                    sdk.openEvenHubTextPage(call.argument<String>("text")
                        ?: throw BridgeFailure("invalidArguments", "A text argument is required."))
                    result.success(null)
                }
                "closeEvenHub" -> { requireOwner(); sdk.closeEvenHub(); result.success(null) }
                "executeEvenHubCommand" -> {
                    requireOwner()
                    val command = call.argument<String>("command")
                        ?: throw BridgeFailure("invalidArguments", "An EvenHub command name is required.")
                    val parameters = call.argument<Map<String, Any?>>("parameters")
                        ?: throw BridgeFailure("invalidArguments", "Logical parameters are required.")
                    // Completion is native ACK/timeout/cancellation; the bridge has no protocol state.
                    sdk.executeEvenHubCommand(command, parameters) { outcome ->
                        outcome.fold(onSuccess = { result.success(it) }, onFailure = { error ->
                            result.error((error as? G2EvenHubException)?.code ?: "nativeSdkError",
                                "The native SDK could not complete this EvenHub command.", null)
                        })
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // JSON exceptions can quote license input. Return fixed messages, never raw exception text.
            val code = when (error) {
                is BridgeFailure -> error.code
                is G2EvenHubException -> error.code
                is SecurityException -> "permissionDenied"
                is IllegalArgumentException -> "invalidArguments"
                else -> "nativeSdkError"
            }
            val message = when (error) {
                is BridgeFailure -> error.safeMessage
                is G2EvenHubException -> "The native SDK rejected this EvenHub request."
                is SecurityException -> "Bluetooth runtime permission is required."
                is IllegalArgumentException -> "The native SDK rejected the supplied arguments."
                else -> "The native SDK could not complete this operation."
            }
            result.error(code, message, null)
        }
    }

    /** The native parser validates every proof before an old SDK session is retired. */
    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val requestedNamespace = required(call, "namespace")
        val bundle = licenses(call)
        val context = engine?.applicationContext
            ?: throw BridgeFailure("engineDetached", "The Flutter engine is detached.")
        synchronized(ownerLock) {
            if (activeOwner != null && activeOwner !== this) {
                throw BridgeFailure("sdkInUse", "Another Flutter engine owns the native SDK.")
            }
            retireOwnedSdk()
            activeOwner = this
            namespace = requestedNamespace
        }
        val ownerEpoch = epoch
        try {
            sdk.initialize(context, bundle,
                onEvent = { event ->
                    val value = normalize(event.value)
                    emit(ownerEpoch, requestedNamespace, mapOf(
                        "type" to "transport", "category" to event.type.name, "value" to value,
                    ))
                    if (event.type.name == "SCAN_RESULT") {
                        discovery(value)?.let { emit(ownerEpoch, requestedNamespace, it) }
                    }
                },
                onG2AuthEvent = { event ->
                    emit(ownerEpoch, requestedNamespace, mapOf(
                        "type" to "g2", "sn" to event.sn,
                        "generation" to event.generation, "sessionGeneration" to null,
                        "attemptGeneration" to null, "endpointId" to event.failedEndpoint,
                        "side" to sideForAddress(event.failedEndpoint),
                        "phase" to if (event.ready) "ready" else "failed",
                        "failure" to if (event.ready) null else "authenticationFailed",
                    ), connectionRevision)
                },
                onG2TimeSyncEvent = { event ->
                    emit(ownerEpoch, requestedNamespace, mapOf(
                        "type" to "timeSync", "sn" to pairSn, "endpointId" to event.endpoint,
                        "generation" to event.generation, "sessionGeneration" to null,
                        "attemptGeneration" to null, "side" to sideForAddress(event.endpoint),
                        "operation" to event.operation, "success" to event.success,
                        "failure" to if (event.success) null else "timeSyncFailed",
                    ), connectionRevision)
                },
                onG2ConnectionEvent = { event ->
                    emit(ownerEpoch, requestedNamespace, mapOf(
                        "type" to "g2", "sn" to event.sn, "generation" to event.generation,
                        "sessionGeneration" to event.session, "attemptGeneration" to event.attempt,
                        "endpointId" to event.endpoint, "side" to sideForAddress(event.endpoint),
                        "phase" to event.phase, "failure" to event.failure,
                    ), connectionRevision)
                },
                onEvenHubEvent = { event ->
                    val owner = event.owner
                    emit(ownerEpoch, requestedNamespace, mapOf(
                        "type" to "evenHub", "sn" to owner.sn, "generation" to owner.generation,
                        "sessionGeneration" to owner.session, "attemptGeneration" to owner.attempt,
                        "endpointId" to owner.endpoint, "side" to sideForAddress(owner.endpoint), "operation" to event.operation,
                        "phase" to event.phase, "failure" to event.failure,
                        "event" to event.event, "heartbeatCount" to event.heartbeatCount,
                        "details" to event.details,
                    ), connectionRevision)
                })
            result.success(null)
        } catch (error: Exception) {
            retireOwnedSdk()
            throw error
        }
    }

    /** Mirror native preflight ordering: rejected B must leave the existing A pair usable. */
    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        requireOwner()
        val requestedSn = required(call, "sn")
        val left = G2Endpoint(required(call, "leftAddress"), required(call, "leftName"))
        val right = G2Endpoint(required(call, "rightAddress"), required(call, "rightName"))
        sdk.connectG2(requestedSn, left, right)
        connectionRevision++
        pair = left to right
        pairSn = requestedSn
        result.success(null)
    }

    /** The SDK uses process-global event listeners, so independent engines cannot share its owner. */
    private fun requireOwner() {
        synchronized(ownerLock) {
            if (activeOwner !== this || namespace == null) {
                throw BridgeFailure("notInitialized", "Initialize this Flutter engine first.")
            }
        }
    }

    /** Invalidate callbacks before teardown, which can itself emit native transport events. */
    private fun retireOwnedSdk() {
        epoch++
        connectionRevision++
        synchronized(ownerLock) {
            if (activeOwner === this) {
                try { sdk.reset() } finally { activeOwner = null }
            }
        }
        namespace = null
        pair = null
        pairSn = null
    }

    /** Freeze namespace and subscription before delivering SDK callbacks on Flutter's main thread. */
    private fun emit(ownerEpoch: Long, ownerNamespace: String, event: Map<String, Any?>,
                     revision: Long? = null) {
        val payload = event + ("namespace" to ownerNamespace)
        val subscriber = subscriptionRevision
        main.post {
            if (engine != null && activeOwner === this && epoch == ownerEpoch &&
                subscriptionRevision == subscriber &&
                (revision == null || connectionRevision == revision)) {
                sink?.success(payload)
            }
        }
    }

    /** Normalize scan display data only; license lookup and GATT admission stay inside the SDK. */
    private fun discovery(value: Any?): Map<String, Any?>? {
        val raw = value as? Map<*, *> ?: return null
        if (raw["isPureScanResult"] == true) return null
        val serial = raw["sn"] as? String ?: return null
        if (serial.isEmpty()) return null
        val devices = (raw["devices"] as? List<*>)?.mapNotNull { item ->
            val device = item as? Map<*, *> ?: return@mapNotNull null
            if (device["belongConfig"] != "g2_glasses" || device["sn"] != serial) return@mapNotNull null
            val address = device["uuid"] as? String ?: return@mapNotNull null
            val name = device["name"] as? String ?: return@mapNotNull null
            val side = when {
                name.contains("_L_", ignoreCase = true) -> "left"
                name.contains("_R_", ignoreCase = true) -> "right"
                else -> return@mapNotNull null
            }
            mapOf("address" to address, "name" to name, "side" to side)
        } ?: return null
        return if (devices.isEmpty()) null else mapOf(
            "type" to "discovery", "sn" to serial, "devices" to devices,
        )
    }

    /** EventChannel requires codec-supported primitive, list, map or byte-array values. */
    private fun normalize(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is String -> try {
            when {
                value.startsWith("{") -> normalize(JSONObject(value))
                value.startsWith("[") -> normalize(JSONArray(value))
                else -> value
            }
        } catch (_: Exception) { value }
        is JSONObject -> value.keys().asSequence().associateWith { normalize(value.opt(it)) }
        is JSONArray -> (0 until value.length()).map { normalize(value.opt(it)) }
        is Map<*, *> -> value.entries.associate { it.key.toString() to normalize(it.value) }
        is Iterable<*> -> value.map { normalize(it) }
        is Number, is Boolean, is ByteArray -> value
        else -> value.toString()
    }

    private fun licenses(call: MethodCall): EnterpriseLicenseBundle {
        val json = required(call, "licenseJson")
        return try { EnterpriseLicenseBundle.fromJsonString(json) } catch (_: Exception) {
            throw BridgeFailure("invalidLicense", "The native SDK rejected the license JSON.")
        }
    }

    private fun required(call: MethodCall, name: String): String =
        call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw BridgeFailure("invalidArguments", "A required argument is missing.")

    private fun sideForAddress(address: String?): String? = when {
        address == null -> null
        address.equals(pair?.first?.address, ignoreCase = true) -> "left"
        address.equals(pair?.second?.address, ignoreCase = true) -> "right"
        else -> null
    }

    /** Permission prompts use the attached Activity without taking native SDK ownership. */
    private fun requestPermissions(result: MethodChannel.Result) {
        if (pendingPermissions != null) {
            throw BridgeFailure("permissionRequestInProgress", "A Bluetooth permission request is already pending.")
        }
        val context = engine?.applicationContext
            ?: throw BridgeFailure("engineDetached", "The Flutter engine is detached.")
        if (Build.VERSION.SDK_INT < 23) { result.success(true); return }
        val required = if (Build.VERSION.SDK_INT >= 31) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        val missing = required.filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { result.success(true); return }
        val host = activity?.activity
            ?: throw BridgeFailure("activityUnavailable", "Attach an Activity before requesting permissions.")
        pendingPermissions = result
        try { host.requestPermissions(missing.toTypedArray(), permissionRequestCode) } catch (error: Exception) {
            pendingPermissions = null
            throw error
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>,
                                             grantResults: IntArray): Boolean {
        if (requestCode != permissionRequestCode || pendingPermissions == null) return false
        finishPermissions(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        return true
    }

    private fun finishPermissions(granted: Boolean) {
        val result = pendingPermissions
        pendingPermissions = null
        result?.success(granted)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { detachActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }

    override fun onDetachedFromActivity() {
        detachActivity()
        finishPermissions(false)
    }

    /** Rotation retains the pending result but releases the old Activity reference. */
    private fun detachActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
    }

    private class BridgeFailure(val code: String, val safeMessage: String) : Exception()

    companion object {
        private val ownerLock = Any()
        private var activeOwner: EvenDevicesNativePlugin? = null
        private val nextPermissionRequest = AtomicInteger(28000)
    }
}
