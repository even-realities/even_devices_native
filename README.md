# Even Enterprise Sdk

English | [简体中文](README.zh-CN.md)

A Flutter-based SDK for building your own Android and iOS applications for **Even G2 glasses**. Native Kotlin and Swift SDKs are also available for direct integration. The native SDKs handle Bluetooth connections, device authorization, display commands, microphone audio, and firmware updates.

## Get access

The Enterprise SDK is currently in **alpha**, with access by application. To connect your application to glasses:

1. Register or sign in at the [Even Hub portal](https://hub.evenrealities.com/).
2. Open the [Enterprise tab](https://hub.evenrealities.com/hub?tab=enterprise) to apply for alpha access and find licensing and firmware details.
3. After approval, follow the onboarding instructions to obtain device licenses and Enterprise-enabled firmware.

## Choose your integration

| Application | Install | Get started |
| --- | --- | --- |
| Flutter | Add `even_devices_native` as a Git dependency. | [Flutter setup](#install-flutter) |
| Native Android | Add `mavenCentral()` and `implementation("com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14")` to your Gradle configuration. | [Kotlin integration](docs/NATIVE_SDK.md#android--maven-central) |
| Native iOS | In Xcode, add [this repository](https://github.com/even-realities/flutter_enterprise_sdk.git) through Swift Package Manager; select exact version `0.1.0-beta.14` and product `EvenDevicesSDK`. | [Swift integration](docs/NATIVE_SDK.md#ios--swift-package-manager) |

## What's included

- Device discovery, left/right temple connection status, enterprise authorization, and time synchronization.
- Even Hub page, text, image, audio, IMU, menu, and interaction commands. Native SDKs own protocol encoding, responses, and page heartbeats.
- G2 firmware updates through the native SDKs. See the [OTA integration guide](docs/NATIVE_SDK.md#g2-firmware-updates).
- Android SDK from Maven Central and iOS SDK from Swift Package Manager, plus a demo with separate scan, device, Even Hub, and log views.

Current scope: G2. See [supported capabilities and limits](docs/SCOPE.md).

## Install Flutter

Add the plugin to your app's `pubspec.yaml`, then run `flutter pub get`:

```yaml
dependencies:
  even_devices_native:
    git:
      url: https://github.com/even-realities/flutter_enterprise_sdk.git
      ref: ea53058edac83a6d7ecc6406593ab383c1f41e48
```

This pins the Flutter adapter to a reviewed commit. Both native SDK dependencies use `0.1.0-beta.14`.

Enable Swift Package Manager before building iOS (required on the validated Flutter 3.32 toolchain):

```bash
flutter config --enable-swift-package-manager
```

For a build-local setting, use `FLUTTER_SWIFT_PACKAGE_MANAGER=true flutter build ios`.
The plugin requires Flutter 3.32+ and uses SPM for iOS; it has no CocoaPods fallback.
Android hosts must include `google()` and `mavenCentral()` in their dependency repositories.
See [integration setup](docs/INTEGRATION.zh-CN.md#原生依赖管理) for existing iOS projects.

Requirements: Android 5.0+ (API 21), iOS 15+, and glasses firmware with the enterprise service enabled. The repository uses Flutter 3.32.0; see [platform setup](docs/INTEGRATION.zh-CN.md#平台要求) for build requirements and Bluetooth permissions. Add `NSBluetoothAlwaysUsageDescription` to your iOS app's `Info.plist`.

## Use the plugin

### 1. Initialize and scan

Obtain a License JSON export containing your app ID and authorized glasses SNs, and declare it as an asset in your app:

```yaml
flutter:
  assets:
    - assets/even_license.json
```

Listen for events before initialization:

```dart
import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/services.dart';

final sdk = EvenDevicesNative.instance;
final subscription = sdk.events.listen((event) {
  // Show event.sn and event.devices from discovery events in your scan UI.
  if (event.type == 'g2' &&
      event.phase == 'ready' &&
      event.side == null &&
      (event.generation ?? 0) > 0) {
    // Both temples are authorized. Enable device actions in your UI.
  }
  // Observe timeSync and evenHub events for command results and interactions.
});

if (!await sdk.requestBluetoothPermissions()) {
  throw StateError('Bluetooth permission denied');
}
await sdk.initialize(
  namespace: 'my-enterprise-app',
  licenseJson: await rootBundle.loadString('assets/even_license.json'),
);
await sdk.scan();
```

### 2. Connect the selected glasses

Collect both endpoints for the selected SN from discovery events; the two sides may arrive separately. Pass their original addresses and names:

```dart
Future<void> connectSelectedGlasses({
  required String sn,
  required G2Endpoint left,
  required G2Endpoint right,
}) async {
  await sdk.stopScan();
  await sdk.connectG2(sn: sn, left: left, right: right);
}
```

The native SDK matches the target SN against the License JSON and rejects unlicensed glasses before connecting. Keep the exported `app_id` unchanged. Store only the license proof in your app; keep signing-platform credentials and private keys outside it.

### 3. Display an Even Hub page

After receiving the whole-device `ready` event, show a short text page:

```dart
await sdk.openEvenHubTextPage(text: 'Hello Even Hub');
// evenHub / active confirms page creation. Native SDKs renew its heartbeat.
// Use evenHub / input events for interactions.

// When the user finishes:
await sdk.closeEvenHub();
await sdk.disconnectG2();
await sdk.reset();
await subscription.cancel();
```

Connection and text-page calls submit requests; their results arrive through `sdk.events`. Use `executeEvenHubCommand` for other page and device interactions; see the [command contract](docs/evenhub_commands.json) and [integration reference](docs/INTEGRATION.zh-CN.md).

## Run the demo

From the repository root, with a phone connected:

```bash
fvm flutter pub get
cd example
fvm flutter run
```

Open Settings, paste your License JSON, and initialize. Scan and select your glasses, then use the device, Even Hub, and log views. Use the device view to select a G2 firmware file and enter its target version for OTA. The demo remembers the last successfully connected glasses for manual reconnection. See the [demo guide](example/README.md).

## Documentation

Start with the **[Even Enterprise documentation](https://hub.evenrealities.com/docs/enterprise/)** (coming soon). Until it goes live, use this repository's [Flutter integration reference](docs/INTEGRATION.zh-CN.md), [native SDK guide](docs/NATIVE_SDK.md), and [example app](example/README.md).

[Validation status](docs/VALIDATION.md) · [Native artifact provenance](PROVENANCE.md) · [Apache 2.0 license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
