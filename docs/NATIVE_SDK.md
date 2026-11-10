# Native Android and iOS integration

The Android and iOS SDKs can be used directly in native applications.
Both SDKs own license parsing, exact SN selection, enterprise authorization,
two-temple business authentication, time synchronization and Even Hub commands.
They do not require the Flutter runtime. The iOS SwiftPM release is `0.1.0-beta.12`.

## Android — Maven Central

**Publication pending:** the company Central account, namespace verification
and release signing key must be configured first. The coordinate below is the
planned public coordinate; it is not yet available from `mavenCentral()`.

```kotlin
// settings.gradle.kts: merge into your existing dependency repositories.
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
```

After the version is published, add to `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.evenrealities.devices:even-devices-native-android:0.1.0-beta.11")
}
```

For local evaluation today, add this checkout's `android/maven` directory as a
Maven repository, keeping `google()` and `mavenCentral()` for transitive dependencies.
Use its absolute path in `maven { url = uri("/path/to/flutter_enterprise_sdk/android/maven") }`.
Minimum Android version: API 21; the library uses Java/Kotlin 17 bytecode.

The host requests Bluetooth permissions before using the SDK. On Android 12+,
request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`; on earlier supported versions,
request location permission and enable the system location service for scanning.

```kotlin
import android.content.Context
import com.evenrealities.devices.EnterpriseLicenseBundle
import com.evenrealities.devices.EvenDevicesAndroidBle
import com.evenrealities.devices.G2Endpoint

fun initializeGlasses(context: Context, licenseJson: String) {
    val licenses = EnterpriseLicenseBundle.fromJsonString(licenseJson)
    val sdk = EvenDevicesAndroidBle.instance
    sdk.initialize(
        context,
        licenses,
        onEvent = { event -> /* Show discovery and transport diagnostics. */ },
        onG2AuthEvent = { event ->
            if (event.ready) {
                // Both temples passed enterprise authorization and business AUTH.
                // Enable your UI actions for event.sn and event.generation.
            }
        },
        onG2TimeSyncEvent = { event -> /* Check event.success. */ },
        onEvenHubEvent = { event -> /* Observe phase, heartbeatCount and input. */ },
    )
    sdk.scan()
}

fun connectGlasses(sn: String, left: G2Endpoint, right: G2Endpoint) {
    val sdk = EvenDevicesAndroidBle.instance
    sdk.stopScan()
    // Use both original endpoint addresses and names discovered for this SN.
    sdk.connectG2(sn, left, right)
}
```

After whole-device READY, call `sdk.openEvenHubTextPage("Hello Even Hub")`.
Native events confirm page activation and renewals; request submission does not
prove display success. Call `sdk.closeEvenHub()` when finished, then
`sdk.disconnectG2(left, right)` or `sdk.reset()` on teardown.

The Maven sources JAR is explicitly a documentation placeholder for this binary
distribution. It does not contain implementation sources. The documentation JAR
contains this guide; neither is advertised as generated API documentation.

## iOS — Swift Package Manager

In Xcode, choose **File → Add Package Dependencies**, enter
`https://github.com/even-realities/flutter_enterprise_sdk.git`, choose exact version
`0.1.0-beta.12`, and add the **EvenDevicesSDK** product to your app target.

For a Swift package consumer:

```swift
.package(
    url: "https://github.com/even-realities/flutter_enterprise_sdk.git",
    exact: "0.1.0-beta.12"
)
```

Add `.product(name: "EvenDevicesSDK", package: "flutter_enterprise_sdk")` to the
consumer target's dependencies. The package contains a versioned local binary
target, so Xcode downloads the framework with the Git tag. It does not need an
external ZIP URL or download token.

Minimum iOS version: 15.0. The XCFramework supports arm64 devices and arm64/x86_64
simulators. Add `NSBluetoothAlwaysUsageDescription` to your app's `Info.plist`.
Retain the SDK for your session; make SDK calls on the main queue.

```swift
import Foundation
import EvenDevicesSDK

func makeGlassesSDK(licenseJSON: Data) throws -> EvenDevicesG2SDK {
    let licenses = try EnterpriseLicenseBundle(jsonData: licenseJSON)
    let sdk = EvenDevicesG2SDK(
        namespace: "my-enterprise-app",
        licenseBundle: licenses,
        onEvent: { event in
            if event.phase == .ready && event.side == nil {
                // Both temples are authorized; enable device actions.
            }
            // Discovery includes serialNumber, side and endpointID.
        },
        onEvenHubEvent: { event in
            // Observe native page state, heartbeat acknowledgements and input.
        }
    )
    sdk.scan()
    return sdk
}
```

After discovering both temples for the selected SN, call
`sdk.connectG2(serialNumber: selectedSN)`. Previously stored endpoint UUIDs can
be supplied as a complete `G2EndpointPair`; they locate devices and do not bypass
authorization. After whole-device READY, use
`try sdk.openEvenHubTextPage(text: "Hello Even Hub")`; finish with
`try sdk.closeEvenHub()` and `sdk.disconnect()`.

## G2 firmware updates on iOS

Subscribe to `onOtaEvent` during initialization. Once both temples are READY,
pass the complete G2 EVENOTA firmware as `Data` and its expected version:

```swift
let operation = try sdk.startOta(firmware: firmware, targetVersion: targetVersion)
// If the user requests cancellation:
sdk.cancelOta(operationId: operation)
```

Match events to the operation ID. `transportCompleted` confirms transfer;
`succeeded` requires matching version readback from both temples after reconnection.
A physical upgrade with this release has not yet been verified.

## Authorization and scope

Pass the complete License JSON from the signing platform unchanged. The native
SDK validates every entry and selects only the exact connection SN; unlisted SNs
are rejected before connecting. Keep platform credentials and signing private
keys outside the application. A scanned device or a single successful temple
is not whole-device READY.

R1 and the full notification pipeline are outside this distribution's
current public surface. Even Hub image inputs must already be in the firmware
format; image preprocessing is not included. See [scope](SCOPE.md),
[validation evidence and remaining device checks](VALIDATION.md), and
[artifact provenance](../PROVENANCE.md). Packaging checks do not establish new
hardware acceptance.

For Even Hub page and interaction concepts, continue with the
[official Get Started / Overview](https://hub.evenrealities.com/docs/get-started/overview).
