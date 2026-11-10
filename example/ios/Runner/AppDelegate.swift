import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UIKit creates the Flutter controller with its scene, after this callback.
    // Register plugins in SceneDelegate so channels bind to that controller.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Owns the example's single window without requiring Flutter 3.38 scene APIs.
/// iOS 27 rejects the old app-only lifecycle before Dart can start.
@objc class SceneDelegate: UIResponder, UIWindowSceneDelegate, UIDocumentPickerDelegate {
  var window: UIWindow?
  // Demo metadata shares the controller's messenger; it never creates a BLE owner.
  private var historyChannel: FlutterMethodChannel?
  private var firmwareChannel: FlutterMethodChannel?
  private var pickerResult: FlutterResult?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Main.storyboard creates the controller and its implicit Flutter engine.
    // Publish the same window for FlutterAppDelegate's registry lookups; never
    // create a second engine, which would duplicate native SDK ownership.
    guard let controller = window?.rootViewController as? FlutterViewController,
          let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      preconditionFailure("The example scene requires its Flutter storyboard")
    }
    appDelegate.window = window
    GeneratedPluginRegistrant.register(with: controller)
    let firmware = FlutterMethodChannel(name: "even_devices_native_example/firmware",
                                        binaryMessenger: controller.binaryMessenger)
    firmwareChannel = firmware
    firmware.setMethodCallHandler { [weak self, weak controller] call, reply in
      guard call.method == "pick" else { reply(FlutterMethodNotImplemented); return }
      guard let self = self, let controller = controller, self.pickerResult == nil,
            controller.presentedViewController == nil else {
        reply(FlutterError(code: "busy", message: "Document picker unavailable.", details: nil)); return
      }
      self.pickerResult = reply
      // An imported copy lets us read the document without retaining an external access grant.
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
      picker.delegate = self
      controller.present(picker, animated: true)
    }
    let defaults = UserDefaults.standard
    let channel = FlutterMethodChannel(
      name: "even_devices_native_example/history",
      binaryMessenger: controller.binaryMessenger
    )
    historyChannel = channel
    // Method handlers run on the main thread, preserving save/clear/load order.
    // Store only the opaque, bounded UI record supplied by Dart, never a license.
    channel.setMethodCallHandler { call, result in
      guard ["load", "save", "clear"].contains(call.method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let namespace = arguments["namespace"] as? String,
            !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        result(FlutterError(
          code: "invalidHistoryArguments", message: "Invalid history arguments", details: nil
        ))
        return
      }
      // Namespace spelling is part of the account boundary; do not normalize it.
      let key = "even_devices_native_example.lastG2.\(namespace)"
      switch call.method {
      case "load":
        guard let stored = defaults.object(forKey: key) else {
          result(nil)
          return
        }
        guard let record = stored as? String else {
          result(FlutterError(
            code: "historyStorageFailed", message: "History storage failed", details: nil
          ))
          return
        }
        result(record)
      case "save":
        guard let record = arguments["record"] as? String,
              !record.isEmpty, record.utf8.count <= 8192 else {
          result(FlutterError(
            code: "invalidHistoryArguments", message: "Invalid history arguments", details: nil
          ))
          return
        }
        defaults.set(record, forKey: key)
        result(nil)
      default:
        defaults.removeObject(forKey: key)
        result(nil)
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let reply = pickerResult
    pickerResult = nil
    reply?(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first, pickerResult != nil else {
      documentPickerWasCancelled(controller)
      return
    }
    // Keep file IO off the UI queue; size is bounded before materializing Flutter bytes.
    DispatchQueue.global(qos: .userInitiated).async {
      let response: Any
      do {
        let maxBytes = 32 * 1024 * 1024
        let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if url.pathExtension.lowercased() == "bin", properties.isRegularFile == true,
           let size = properties.fileSize, (1...maxBytes).contains(size) {
          let handle = try FileHandle(forReadingFrom: url)
          defer { try? handle.close() }
          guard let bytes = try handle.read(upToCount: size + 1), bytes.count == size else {
            throw CocoaError(.fileReadCorruptFile)
          }
          response = ["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: bytes)]
        } else {
          response = FlutterError(code: "invalidFirmwareFile", message: "Invalid firmware file.", details: nil)
        }
      } catch {
        response = FlutterError(code: "fileReadFailed", message: "Cannot read firmware.", details: nil)
      }
      DispatchQueue.main.async {
        let reply = self.pickerResult
        self.pickerResult = nil
        reply?(response)
      }
    }
  }

  deinit {
    firmwareChannel?.setMethodCallHandler(nil)
    historyChannel?.setMethodCallHandler(nil)
  }
}
