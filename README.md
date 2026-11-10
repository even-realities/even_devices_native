# flutter_enterprise_sdk

English | [简体中文](README.zh-CN.md)

A Flutter plugin for connecting **enterprise-designated Even G2 glasses** on Android and iOS. The native Kotlin and Swift SDKs handle Bluetooth connections, license matching by serial number (SN), and device authorization.

## What's included

- Device discovery, left/right temple connection status, enterprise authorization, and time synchronization.
- Even Hub page, text, image, audio, IMU, menu, and interaction commands. Native SDKs own protocol encoding, responses, and page heartbeats.
- Bundled Android AAR and iOS XCFramework, plus a demo with separate scan, device, Even Hub, and log views.

Current scope: G2. See [supported capabilities and limits](docs/SCOPE.md).

## Install

Add the plugin to your app's `pubspec.yaml`, then run `flutter pub get`:

```yaml
dependencies:
  even_devices_native:
    git:
      url: https://github.com/even-realities/flutter_enterprise_sdk.git
      ref: main
```

Pin a reviewed commit instead of `main` for reproducible production builds.

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

## Native SDKs

Native iOS apps can install **EvenDevicesSDK** from this repository with Swift Package Manager. Select exact version `0.1.0-beta.12` for native G2 firmware updates. Android Maven Central publication is pending. See the [native integration guide](docs/NATIVE_SDK.md).

## Run the demo

From the repository root, with a phone connected:

```bash
fvm flutter pub get
cd example
fvm flutter run
```

Open Settings, paste your License JSON, and initialize. Scan and select your glasses, then use the device, Even Hub, and log views. The demo remembers the last successfully connected glasses for manual reconnection. See the [demo guide](example/README.md).

## Documentation

Start with the **[Even Hub official documentation — Get Started / Overview](https://hub.evenrealities.com/docs/get-started/overview)** for Even Hub concepts, display and interaction guides, and the app development workflow. Use this repository's examples and integration reference for the Flutter connection APIs.

[Validation status](docs/VALIDATION.md) · [Native artifact provenance](PROVENANCE.md) · [Apache 2.0 license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
