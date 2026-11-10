import Flutter
import Foundation
import UIKit
import EvenDevicesSDK

/// Adapts Flutter arguments and events; the standalone Swift SDK owns BLE and license decisions.
public final class EvenDevicesNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    // Flutter engines share one process. A second engine cannot silently replace the BLE owner.
    private static weak var activeOwner: EvenDevicesNativePlugin?
    private var sdk: EvenDevicesG2SDK?
    private var methods: FlutterMethodChannel?
    private var events: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var detached = false
    // Captured per initialization rather than inferred from the latest discovery event.
    private var currentNamespace = ""

    // A replaced SDK cannot deliver events or a command completion into its successor namespace.
    private var generation: UInt64 = 0
    private var connectionRevision: UInt64 = 0
    private var readyOwner: (sn: String, session: UInt64)?

    /// Preserve native PCM as typed binary; raw Foundation Data is not a
    /// StandardMessageCodec value and must never be expanded into JSON numbers.
    private static func channelDetails(_ details: [String: Any]) -> [String: Any] {
        details.mapValues { value in
            if let bytes = value as? Data { return FlutterStandardTypedData(bytes: bytes) }
            return value
        }
    }

    /// Uses Flutter's main-thread channel queue to match the native CoreBluetooth contract.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = EvenDevicesNativePlugin()
        let methods = FlutterMethodChannel(name: "even_devices_native/methods",
                                           binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(name: "even_devices_native/events",
                                         binaryMessenger: registrar.messenger())
        instance.methods = methods
        instance.events = events
        registrar.addMethodCallDelegate(instance, channel: methods)
        events.setStreamHandler(instance)
        // Publishing is required for Flutter to call detachFromEngine during engine teardown.
        registrar.publish(instance)
    }

    /// Tears down only this engine's SDK; an unused engine never retires another owner.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.detachFromEngine(for: registrar) }
            return
        }
        detached = true
        retireSDK()
        methods?.setMethodCallHandler(nil)
        events?.setStreamHandler(nil)
        methods = nil
        events = nil
        eventSink = nil
    }

    deinit {
        // SDK methods require main. This fallback also covers teardown without a detach callback.
        let retiring = sdk
        if Thread.isMainThread {
            retiring?.stopScan()
            retiring?.disconnect()
        } else {
            DispatchQueue.main.async {
                retiring?.stopScan()
                retiring?.disconnect()
            }
        }
    }

    /// Structural bridge checks precede native calls; license contents are parsed only by the SDK.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    result(FlutterError(code: "detached", message: "The Flutter engine is detached.", details: nil))
                    return
                }
                self.handle(call, result: result)
            }
            return
        }
        guard !detached else {
            result(FlutterError(code: "detached", message: "The Flutter engine is detached.", details: nil))
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        do {
            switch call.method {
            case "initialize":
                guard let namespace = args["namespace"] as? String,
                      !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BridgeError.invalidArguments
                }
                // A malformed update must leave the existing native owner and its proofs intact.
                let licenses = try licenseBundle(args["licenseJson"])
                guard Self.activeOwner == nil || Self.activeOwner === self else {
                    throw BridgeError.busy
                }
                retireSDK()
                let epoch = generation
                Self.activeOwner = self
                currentNamespace = namespace
                sdk = EvenDevicesG2SDK(namespace: namespace, licenseBundle: licenses,
                    autoReconnect: false,
                    onEvent: { [weak self] event in self?.handle(event, epoch: epoch) },
                    onBusinessEvent: { [weak self] event in
                        self?.emit(epoch: epoch, payload: [
                            "type": "business", "namespace": namespace, "sn": event.serialNumber,
                            "side": event.side.rawValue, "endpointId": event.endpointID.uuidString,
                            "generation": event.sessionGeneration,
                            "sessionGeneration": event.sessionGeneration,
                            "attemptGeneration": event.attemptGeneration,
                            "service": String(describing: event.service),
                            "payload": FlutterStandardTypedData(bytes: event.payload)
                        ])
                    }, onEvenHubEvent: { [weak self] event in
                        self?.emit(epoch: epoch, payload: [
                            "type": "evenHub", "namespace": event.namespace, "sn": event.serialNumber,
                            "side": event.side, "endpointId": event.endpointID.uuidString,
                            "generation": event.sessionGeneration,
                            "sessionGeneration": event.sessionGeneration,
                            "attemptGeneration": event.attemptGeneration, "operation": event.operation,
                            "phase": event.phase, "event": event.event as Any? ?? NSNull(),
                            "failure": event.failure as Any? ?? NSNull(),
                            "heartbeatCount": event.heartbeatCount, "details": Self.channelDetails(event.details)
                        ])
                    }, onOtaEvent: { [weak self] event in
                        // Native owns reconnection and version readback across this operation.
                        self?.emit(epoch: epoch, payload: [
                            "type": "ota", "namespace": namespace, "sn": event.sn,
                            "generation": event.generation, "endpointId": event.endpoint as Any? ?? NSNull(),
                            "operation": event.operation, "phase": event.phase, "progress": event.progress,
                            "sessionGeneration": event.session as Any? ?? NSNull(),
                            "attemptGeneration": event.attempt as Any? ?? NSNull(),
                            "leftVersion": event.leftVersion as Any? ?? NSNull(),
                            "rightVersion": event.rightVersion as Any? ?? NSNull(),
                            "failure": event.failure as Any? ?? NSNull()
                        ])
                    })
            case "reset":
                retireSDK()
            case "requestBluetoothPermissions":
                // iOS presents its own Bluetooth prompt when CoreBluetooth is initialized.
                // This result acknowledges the platform request path, not a grant from the user.
                result(true)
                return
            case "updateLicenses", "scan", "stopScan", "connectG2", "disconnectG2", "syncG2Time",
                 "openEvenHubTextPage", "closeEvenHub", "executeEvenHubCommand", "startOta", "cancelOta":
                guard let sdk = sdk else { throw BridgeError.notInitialized }
                switch call.method {
                case "updateLicenses":
                    sdk.updateLicenses(try licenseBundle(args["licenseJson"]))
                case "scan": sdk.scan()
                case "stopScan": sdk.stopScan()
                case "connectG2":
                    guard let sn = args["sn"] as? String, !sn.isEmpty else {
                        throw BridgeError.invalidArguments
                    }
                    let endpoints = try endpointPair(args)
                    // Native .busy/proofNotFound rejection must not revoke the current READY owner.
                    sdk.connectG2(serialNumber: sn, endpointIDs: endpoints)
                case "disconnectG2":
                    invalidateReadyOwner()
                    sdk.disconnect()
                case "syncG2Time": try syncTime(sdk)
                case "startOta":
                    guard let firmware = args["firmware"] as? FlutterStandardTypedData,
                          firmware.type == .uInt8, let version = args["targetVersion"] as? String else {
                        throw BridgeError.invalidArguments
                    }
                    result(try sdk.startOta(firmware: firmware.data, targetVersion: version))
                    return
                case "cancelOta":
                    guard let operation = args["operationId"] as? NSNumber,
                          ["i", "q"].contains(String(cString: operation.objCType)),
                          operation.int64Value > 0 else { throw BridgeError.invalidArguments }
                    sdk.cancelOta(operationId: operation.int64Value)
                case "openEvenHubTextPage":
                    guard let text = args["text"] as? String else { throw BridgeError.invalidArguments }
                    try sdk.openEvenHubTextPage(text: text)
                case "closeEvenHub": try sdk.closeEvenHub()
                case "executeEvenHubCommand":
                    guard let command = args["command"] as? String,
                          var parameters = args["parameters"] as? [String: Any] else { throw BridgeError.invalidArguments }
                    // Flutter submits a whole firmware-format image, never
                    // protobuf or fragment metadata. Native owns all chunking.
                    if let bytes = parameters["data"] as? FlutterStandardTypedData { parameters["data"] = bytes.data }
                    sdk.executeEvenHubCommand(commandName: command, parameters: parameters) { response in
                        switch response {
                        case .success(let value): result(value)
                        case .failure(let error):
                            result(FlutterError(code: error.rawValue, message: "The native EvenHub command failed.", details: nil))
                        }
                    }
                    return
                default: break
                }
            default:
                result(FlutterMethodNotImplemented)
                return
            }
            result(nil)
        } catch let error as BridgeError {
            // Static messages cannot echo a supplied license JSON or any signature bytes.
            result(FlutterError(code: error.rawValue, message: error.message, details: nil))
        } catch let error as G2OtaError {
            result(FlutterError(code: error.rawValue, message: "The native SDK rejected this OTA request.", details: nil))
        } catch let error as G2EvenHubError {
            // Safe codes convey admission without echoing the submitted text
            // or claiming that the glasses have acknowledged a page yet.
            result(FlutterError(code: error.rawValue, message: "The native EvenHub request was rejected.", details: nil))
        } catch {
            result(FlutterError(code: "nativeError", message: "The native SDK rejected the request.", details: nil))
        }
    }

    /// The native model validates every entry before any proof may be selected or sent.
    private func licenseBundle(_ value: Any?) throws -> EnterpriseLicenseBundle {
        guard let json = value as? String else { throw BridgeError.invalidArguments }
        do { return try EnterpriseLicenseBundle(jsonData: Data(json.utf8)) }
        catch { throw BridgeError.invalidLicense }
    }

    /// UUID hints are an exact pair or absent; a partial binding cannot change native discovery.
    private func endpointPair(_ args: [String: Any]) throws -> G2EndpointPair? {
        let left = args["leftAddress"]
        let right = args["rightAddress"]
        if (left == nil || left is NSNull) && (right == nil || right is NSNull) { return nil }
        guard let leftText = left as? String, let rightText = right as? String,
              let leftID = UUID(uuidString: leftText), let rightID = UUID(uuidString: rightText),
              let pair = G2EndpointPair(left: leftID, right: rightID) else {
            throw BridgeError.invalidArguments
        }
        return pair
    }

    /// READY is granted by a whole-device SDK event, never by endpoint transport readiness.
    private func handle(_ event: G2Event, epoch: UInt64) {
        guard generation == epoch, !detached else { return }
        if event.phase == .ready && event.side == nil {
            readyOwner = (event.serialNumber, event.sessionGeneration)
        } else if event.phase == .connecting ||
                    (event.phase != .discovered && event.phase != .ready && event.failure != .busy &&
                     event.serialNumber == readyOwner?.sn && event.sessionGeneration == readyOwner?.session) {
            invalidateReadyOwner()
        }
        emit(epoch: epoch, payload: [
            "type": "g2", "namespace": event.namespace, "sn": event.serialNumber,
            "side": event.side?.rawValue as Any? ?? NSNull(),
            "endpointId": event.endpointID?.uuidString as Any? ?? NSNull(),
            "generation": event.sessionGeneration,
            "sessionGeneration": event.sessionGeneration,
            "attemptGeneration": event.attemptGeneration as Any? ?? NSNull(),
            "phase": event.phase.rawValue,
            "failure": event.failure?.rawValue as Any? ?? NSNull()
        ])
        if event.phase == .discovered, let side = event.side, let endpoint = event.endpointID {
            // Discovery is incremental on iOS. The host displays candidates; native owns pair admission.
            emit(epoch: epoch, payload: [
                "type": "discovery", "namespace": event.namespace, "sn": event.serialNumber,
                "devices": [["address": endpoint.uuidString, "name": "", "side": side.rawValue]]
            ])
        }
    }

    /// A late completion is discarded after disconnect, replacement, or a different native session.
    private func syncTime(_ sdk: EvenDevicesG2SDK) throws {
        guard let owner = readyOwner else { throw BridgeError.notReady }
        let epoch = generation
        let revision = connectionRevision
        sdk.syncTime { [weak self] outcome in
            guard let self = self, self.generation == epoch,
                  self.connectionRevision == revision,
                  self.readyOwner?.sn == owner.sn,
                  self.readyOwner?.session == owner.session else { return }
            let success: Bool
            let failure: Any
            switch outcome {
            case .success: success = true; failure = NSNull()
            case .failure(let error): success = false; failure = String(describing: error)
            }
            self.emit(epoch: epoch, payload: [
                "type": "timeSync", "namespace": self.currentNamespace,
                "sn": owner.sn, "side": "right", "generation": owner.session,
                "sessionGeneration": owner.session, "success": success, "failure": failure
            ])
        }
    }

    /// Epoch changes before native teardown, whose callbacks can arrive synchronously.
    private func retireSDK() {
        generation &+= 1
        invalidateReadyOwner()
        let retiring = sdk
        sdk = nil
        if Self.activeOwner === self { Self.activeOwner = nil }
        retiring?.stopScan()
        retiring?.disconnect()
        currentNamespace = ""
    }

    /// Invalidate command attribution without changing native ownership for rejected requests.
    private func invalidateReadyOwner() {
        connectionRevision &+= 1
        readyOwner = nil
    }

    /// SDK callbacks already run on main; epoch is checked again at the Flutter boundary.
    private func emit(epoch: UInt64, payload: [String: Any]) {
        guard generation == epoch, !detached else { return }
        eventSink?(payload)
    }

    /// A Flutter listener only observes the SDK; canceling it never disconnects an active pair.
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    /// Stable bridge error codes preserve native detail boundaries without exposing credentials.
    private enum BridgeError: String, Error {
        case invalidArguments, invalidLicense, notInitialized, notReady, busy

        var message: String {
            switch self {
            case .invalidArguments: return "Invalid native SDK arguments."
            case .invalidLicense: return "The native SDK rejected the license bundle."
            case .notInitialized: return "Initialize the native SDK first."
            case .notReady: return "Both G2 endpoints must be ready."
            case .busy: return "Another Flutter engine owns the native SDK."
            }
        }
    }
}
