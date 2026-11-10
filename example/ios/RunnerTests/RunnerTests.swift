import Flutter
import XCTest

@testable import even_devices_native

/// Invalid licenses must be rejected by the Swift SDK before CoreBluetooth starts.
final class RunnerTests: XCTestCase {
  /// Exercise the real host launch, including scene creation and registration.
  func testSceneLaunchRegistersThePluginOnItsFlutterController() {
    let controllers = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .compactMap { $0.rootViewController as? FlutterViewController }
    XCTAssertEqual(controllers.count, 1)
    XCTAssertTrue(controllers.first?.hasPlugin("EvenDevicesNativePlugin") == true)
  }

  func testNativeLicenseParserRejectsPortalInputBeforeInitialization() {
    let plugin = EvenDevicesNativePlugin()
    let call = FlutterMethodCall(methodName: "initialize", arguments: [
      "namespace": "test-account", "licenseJson": "{not-json}",
    ])
    let rejected = expectation(description: "Invalid license completes with an error")
    plugin.handle(call) { result in
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "invalidLicense")
      XCTAssertFalse(error?.message?.contains("not-json") ?? false)
      rejected.fulfill()
    }
    // A rejected bundle must not leave a usable native owner behind.
    let noOwner = expectation(description: "Rejected initialization retains no owner")
    plugin.handle(FlutterMethodCall(methodName: "scan", arguments: nil)) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "notInitialized")
      noOwner.fulfill()
    }
    wait(for: [rejected, noOwner], timeout: 1)
  }
}
