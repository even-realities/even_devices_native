# Native Android and iOS integration

The Android and iOS SDKs can be used directly in native applications.
Their source, shared protocol, native examples and publishing scripts are managed
in the dedicated [enterprise_sdk repository](https://github.com/even-realities/enterprise_sdk).
Both SDKs own license parsing, exact SN selection, enterprise authorization,
two-temple business authentication, time synchronization and Even Hub commands.
They do not require the Flutter runtime. Both published native dependencies are pinned to beta.14. The Flutter plugin uses Maven Central on Android and SwiftPM on iOS.

## Android — Maven Central

**Published:** `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14` is available from Maven Central.

```kotlin
// settings.gradle.kts: merge into your existing dependency repositories.
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
```

Add to `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14")
}
```

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

The Maven sources JAR contains Android implementation sources from the original native build commit. Historical beta.14 build inputs remain documented in [artifact provenance](../PROVENANCE.md). Future native builds and publishing use [enterprise_sdk](https://github.com/even-realities/enterprise_sdk); the Maven coordinate is unchanged. Full native API guides: [Android](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-android-sdk.md) and [iOS](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-ios-sdk.md).

## iOS — Swift Package Manager

In Xcode, choose **File → Add Package Dependencies**, enter
`https://github.com/even-realities/enterprise_sdk.git`, choose exact version
`0.1.0-beta.14`, and add the **EvenDevicesSDK** product to your app target.

For a Swift package consumer:

```swift
.package(
    url: "https://github.com/even-realities/enterprise_sdk.git",
    exact: "0.1.0-beta.14"
)
```

Add `.product(name: "EvenDevicesSDK", package: "enterprise_sdk")` to the
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

## Even Hub microphone audio

After both temples reach READY and the Even Hub page is active, enable the glasses microphone. At least one current endpoint must support notifications on the STREAM service (6450 / 6402). Wait for the command result. Audio delivery begins after the firmware acknowledges enable.

| Host | Enable on the current page | Read in the SDK’s `onEvenHubEvent` callback |
|---|---|---|
| Kotlin | `sdk.executeEvenHubCommand("audioControl", mapOf("enabled" to true)) { result -> /* handle result */ }` | For `event.event == "audioEvent"`, read `event.details["audioPcm"] as? ByteArray`. |
| Swift | `sdk.executeEvenHubCommand(commandName: "audioControl", parameters: ["enabled": true]) { result in /* handle result */ }` | For `event.event == "audioEvent"`, read `event.details["audioPcm"] as? Data`. |
| Flutter | `await sdk.executeEvenHubCommand(EvenHubCommand.audioControl, parameters: {"enabled": true});` | Listen to `sdk.events`; `event.audioPcm` carries the native bytes as a `Uint8List` on `audioEvent`. |

The native SDK decodes each 40-byte LC3 frame into 160 mono samples at 16 kHz and applies the Even Hub host’s default automatic gain control. Output uses signed little-endian PCM16. A tagged five-frame packet produces 1,600 bytes. For tagged packets, the host-compatible speaker smoother emits a normalized silence block on the first packet, then the preceding block on each subsequent packet. Events carry `source = glasses`, `speakerRole` (`self`, `other`, or `unknown`), and the current signed `direction` when provided by firmware. Untagged packets carry `unknown` and omit direction.

Send `audioControl` with `enabled: false` to stop delivery. Closing the page or disconnecting also clears the stream and its decoder history. This API covers the glasses microphone and the default PCM path. The beta.14 release includes native PCM delivery.

## G2 firmware updates

For OTA, use the beta.14 Maven Central coordinate above or pin the iOS Swift package to `0.1.0-beta.14`. Subscribe to `onOtaEvent` during SDK initialization. After both temples reach READY, provide the complete G2 EVENOTA firmware bytes and the target firmware version from the release.

```kotlin
val operation = sdk.startOta(firmware, targetVersion) // ByteArray, String
// If the user cancels this operation:
sdk.cancelOta(operation)
```

```swift
let operation = try sdk.startOta(firmware: firmware, targetVersion: targetVersion) // Data, String
// If the user cancels this operation:
sdk.cancelOta(operationId: operation)
```

Match events to the returned operation ID. `transportCompleted` indicates that both transfers finished. The SDK checks both installed versions after reconnection before emitting `succeeded`. A mismatch or missing readback leaves the installation unverified.

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
