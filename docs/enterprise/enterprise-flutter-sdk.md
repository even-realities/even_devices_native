# Enterprise Flutter SDK integration guide

API baseline: native SDK **0.1.0-beta.14**, Flutter adapter API commit **ea53058edac83a6d7ecc6406593ab383c1f41e48**. Repository integration updated: 2026-11-11; the API is unchanged.

## 1. What this SDK provides

`even_devices_native` is a Flutter plugin for connecting an enterprise application to its authorized **G2 glasses**. Kotlin and Swift own Bluetooth, exact-SN license selection, enterprise authorization, two-leg connection state, business authentication, time synchronization, Even Hub commands and heartbeat, microphone LC3 decoding/PCM processing, and G2 OTA. Dart converts arguments, binary buffers, and event envelopes; it does not implement these protocols.

This package is distinct from the JavaScript/npm Even Hub SDK. Use [Even Hub: Get Started / Overview](https://hub.evenrealities.com/docs/get-started/overview) for the Even Hub concepts and interaction guidance. Install this Flutter plugin as described here; the website's npm installation and web-plugin deployment workflow do not install the enterprise native SDK.

Other platform guides: [Android Kotlin](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-android-sdk.md), [iOS Swift](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-ios-sdk.md).

| Included | Boundary in beta.14 |
| --- | --- |
| G2 scanning and left/right pair management | A scan observation or one ready leg is not whole-device READY |
| Enterprise license parsing, SN lookup and authorization | App stores proofs, never a signing private key or portal credentials |
| Time synchronization | Completion is reported by `timeSync` events |
| Ten logical Even Hub commands, page lease and native heartbeat | Host supplies content, not wire packets/session IDs |
| Glasses microphone input | Native LC3 → processed PCM16; no public standalone LC3 decoder/encoder API |
| Dual-leg G2 OTA and post-reconnect version verification | Transfer completion alone does not establish installation success |

R1/DFU, consumer G2 protocols, a general notification API, a public arbitrary-command transport, and PNG/BMP-to-firmware image conversion are not exposed by this plugin. Automatic background restoration/reconnection and remembered-device persistence are not a Flutter API in this release; the host owns its UI/persistence policy.

## 2. Installation and host setup

Requirements: Flutter **3.32.0+**, Android API **21+** and JDK 17, or iOS **15+** with Xcode and Swift Package Manager support. Physical glasses must run firmware exposing the enterprise service. Confirm the firmware with your firmware team; no minimum firmware version is specified here.

Add to the host `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  even_devices_native:
    git:
      url: https://github.com/even-realities/flutter_enterprise_sdk.git
      ref: main

flutter:
  assets:
    - assets/enterprise-licenses.json
```

For production, replace `main` with a reviewed Flutter adapter commit. The adapter pins Android Maven Central `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14` and iOS SPM product `EvenDevicesSDK` at exact tag `0.1.0-beta.14` from [enterprise_sdk](https://github.com/even-realities/enterprise_sdk). Native SDK tags are not Flutter plugin release references. Existing beta.14 SPM tags in the Flutter repository remain available for earlier consumers.

```bash
flutter config --enable-swift-package-manager
flutter pub get
flutter run
```

Use `fvm flutter` instead when your project pins Flutter with FVM. Android dependency repositories must include `google()` and `mavenCentral()`. Do not add a second local AAR or another BLE SDK owner.

Android: the plugin declares the BLE permissions and provides `requestBluetoothPermissions()` for a foreground Activity. On Android 12+ this requests Bluetooth scan/connect permissions; older Android versions use the location permission path. Bluetooth must be enabled; older Android scanning can also depend on system location being enabled. Check permission results before scanning.

iOS: set the host deployment target to 15.0+ and add a meaningful `NSBluetoothAlwaysUsageDescription` string in `Runner/Info.plist`. CoreBluetooth presents the Bluetooth privacy prompt. `requestBluetoothPermissions()` returning `true` on iOS acknowledges the platform path, **not** that the user granted access. This plugin uses SPM; do not add an old CocoaPods adapter or duplicate `EvenDevicesSDK` framework. Microphone data comes from the glasses, so this feature does not request the phone microphone.

## 3. License bundle and exact-SN authorization

Obtain proofs from the enterprise signing portal for your registered `app_id` and each complete glasses SN. Bundle the portal JSON as an application asset or load it from your own protected distribution channel. The SDK does not contact the portal.

Preferred portal format (placeholders below must be replaced with actual issued values):

```json
{
  "format": "enterprise-sdk-license-v1",
  "app_id": "your-registered-app-id",
  "licenses": [
    {"sn": "S0000000000001", "signature": "<portal-issued standard Base64 signature>"}
  ]
}
```

The example SN is fictional. This JSON illustrates structure and is not an executable license.

- `app_id`: 1–64 UTF-8 bytes; case and spaces are preserved. It must equal the value used when signing. A package name is only an app ID when registered/signed as that exact string.
- SN: exactly **14 ASCII bytes**, matched exactly against the connected glasses' advertised SN. Never match a suffix, device display name, or the first license entry.
- Signature: canonical standard Base64, including padding, decoding to **64 bytes** (88 characters ending in `==`). URL-safe Base64 and whitespace are rejected.
- Root keys are exactly `format`, `app_id`, `licenses`; each entry contains exactly `sn`, `signature`. Duplicate JSON keys, duplicate SNs, unknown keys, or any invalid entry reject the entire bundle.
- The older `schema_version: 1`, `app_id`, `proofs` object format is also accepted. Do not mix formats.

Pass **raw JSON** to `initialize`/`updateLicenses`. Kotlin/Swift parse and validate all entries, select the exact SN proof and reject missing proofs before starting a new GATT connection. An invalid update leaves the previous valid bundle intact. Updates apply to subsequent authorization attempts; they do not rewrite an in-flight attempt. Format validation is not cryptographic authorization: the glasses' firmware decides the proof result.

```mermaid
sequenceDiagram
    participant App as Flutter host
    participant Native as Kotlin / Swift SDK
    participant L as G2 left
    participant R as G2 right
    App->>Native: initialize(namespace, raw license JSON)
    Native->>Native: Validate entire bundle
    App->>Native: scan / connectG2(SN, scanned locators)
    Native->>Native: Exact SN lookup; reject if absent
    Native->>L: Encrypted link, 8450, 8403 proof
    L-->>Native: Enterprise authorization result
    Native->>L: Subscribe 8402; business AUTH on 8401
    Native->>R: Encrypted link, 8450, 8403 proof
    R-->>Native: Enterprise authorization result
    Native->>R: Subscribe 8402; business AUTH on 8401
    Native-->>App: g2 ready, side absent, current generation
```

Enterprise service `8450` contains business RX `8401`, business TX `8402`, and AUTH `8403`. Business AUTH here means the post-authorization business-layer handshake on **8401**, not the old shared-key write on 5403. The enterprise path does not fall back to 5450/5401/5402/5403.

## 4. Minimal host controller

Listen before initialization. Maintain discovery observations by **SN and side** because iOS reports sides incrementally. Preserve Android's original scanned address and name. The following controller demonstrates the flow without assuming that a method completion is READY.

```dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:even_devices_native/even_devices_native.dart';

/// UI state only; connection, proof selection and heartbeat remain native.
class EnterpriseDemoController {
  final sdk = EvenDevicesNative.instance;
  final candidates = <String, Map<String, G2DiscoveredEndpoint>>{};
  StreamSubscription<EvenDevicesEvent>? subscription;
  String? readySn;
  int? readyGeneration;
  int pcmByteCount = 0;
  String? lastFailure;

  Future<void> initialize() async {
    subscription ??= sdk.events.listen(onEvent, onError: (Object error) {
      lastFailure = error.toString();
    });
    final json = await rootBundle.loadString('assets/enterprise-licenses.json');
    await sdk.initialize(namespace: 'enterprise-demo', licenseJson: json);
    if (!await sdk.requestBluetoothPermissions()) {
      throw StateError('Bluetooth permission was denied');
    }
    await sdk.scan();
  }

  void onEvent(EvenDevicesEvent event) {
    if (event.type == 'discovery' && event.sn != null) {
      final pair = candidates.putIfAbsent(event.sn!, () => {});
      for (final endpoint in event.devices) {
        pair[endpoint.side] = endpoint;
      }
    }
    if (event.type == 'g2') {
      if (event.phase == 'ready' && event.side == null &&
          (event.generation ?? 0) > 0) {
        readySn = event.sn;
        readyGeneration = event.generation;
      } else if (event.phase == 'connecting' ||
          (event.sn == readySn && event.generation == readyGeneration &&
           event.phase != 'discovered' && event.phase != 'ready' &&
           event.failure != 'busy')) {
        readySn = null;
        readyGeneration = null;
      }
    }
    if (event.type == 'evenHub' && event.event == 'audioEvent') {
      pcmByteCount += event.audioPcm!.length;
      // Feed event.audioPcm to a bounded worker/file sink, not a full-byte UI log.
    }
    if (event.failure != null) lastFailure = event.failure;
    // Render timeSync.success, EvenHub phase/heartbeatCount, and OTA by operation.
  }

  Future<void> connect(String fullSn) async {
    final pair = candidates[fullSn];
    if (pair?['left'] == null || pair?['right'] == null) {
      throw StateError('Scan both sides of the selected SN first');
    }
    await sdk.stopScan();
    await sdk.connectG2(sn: fullSn, left: pair!['left'], right: pair['right']);
    // Wait for a whole-device g2/ready event before enabling controls.
  }

  void requireReady() {
    if (readySn == null) throw StateError('Both legs must be READY');
  }

  Future<void> displayText() async {
    requireReady();
    await sdk.openEvenHubTextPage(text: 'Hello enterprise');
    // Wait for evenHub/active; native starts confirmed page heartbeats.
  }

  Future<void> synchronizeTime() async {
    requireReady();
    // Call after the EvenHub page has closed and no OTA is in progress.
    await sdk.syncG2Time();
    // Submission only. Observe the timeSync event's success/failure.
  }

  Future<int> upgrade(Uint8List completeFirmware, String targetVersion) async {
    requireReady();
    return sdk.startOta(firmware: completeFirmware, targetVersion: targetVersion);
  }

  Future<void> dispose() async {
    // Explicitly tear down native ownership; canceling a listener does not do it.
    await sdk.reset();
    await subscription?.cancel();
    subscription = null;
    readySn = null;
    readyGeneration = null;
    candidates.clear();
  }
}
```

Handle `PlatformException` at UI action boundaries and show its code plus a safe explanation. Do not include license JSON/signatures in error logs. Persist the last selected SN/locators in the host if desired; after a new process session, scan again before connecting, especially on iOS where the native peripheral cache must be populated. An old saved UUID alone is not a fresh scan observation.

## 5. Complete Flutter API

All methods belong to `EvenDevicesNative`; use `EvenDevicesNative.instance`. The constructor's optional MethodChannel/EventChannel parameters are intended for embedding/testing, not an additional independent BLE owner.

| API | Meaning / completion contract |
| --- | --- |
| `events: Stream<EvenDevicesEvent>` | Broadcast native event stream; subscribe before initialization; no state replay |
| `initialize(namespace:, licenseJson:) → Future<void>` | Create native owner using raw JSON; namespace is a nonblank host/account scope |
| `updateLicenses(String) → Future<void>` | Atomically validate/replace future-attempt proofs in native |
| `requestBluetoothPermissions() → Future<bool>` | Android foreground runtime permission helper; iOS caveat above |
| `scan()`, `stopScan() → Future<void>` | Start/stop native scan; observations arrive as events |
| `connectG2(sn:, left?, right?) → Future<void>` | Submit connection for exact SN; wait for READY event |
| `disconnectG2() → Future<void>` | Disconnect current glasses, retire pending session work |
| `syncG2Time() → Future<void>` | Submit native time sync; await `timeSync` event for outcome |
| `openEvenHubTextPage(text:) → Future<void>` | Convenience page; nonempty text ≤64 UTF-8 bytes; observe `active` |
| `closeEvenHub() → Future<void>` | Request shutdown including during page creation; observe `closed`/failure |
| `executeEvenHubCommand(command, parameters:) → Future<Map<String,Object?>>` | Execute one of the ten logical commands below |
| `startOta(firmware: Uint8List, targetVersion: String) → Future<int>` | Submit complete firmware, return positive operation ID, not installation success |
| `cancelOta(operationId:) → Future<void>` | Cancel only the matching native OTA operation |
| `reset() → Future<void>` | Tear down this engine's native SDK; use before account/namespace changes |

`G2Endpoint(address:, name: '')` is a locator, never a proof. `G2DiscoveredEndpoint` additionally has `side` (`left`/`right`). Android connection requires both original scan locators. iOS permits both UUID locators or neither (resolve from the current native scan cache), but never a single supplied side. Explicit paired observations work across platforms as in the controller.

## 6. Even Hub commands and payloads

All commands run in native, including ACK matching, fragmentation, timeout/cancellation, image retry, and heartbeat. Call `executeEvenHubCommand(EvenHubCommand.<name>, parameters: {...})`. Most require a READY pair and current page lease; `createPage` creates the lease. Commands are logical requests, not protobuf/wire command IDs.

| Enum value | Parameters | Outcome |
| --- | --- | --- |
| `createPage` | `widgetId` nonzero uint32, default 11417; inline `listObjects`, `textObjects`, `imageObjects`, optional `menu` | ACK acquires sole page lease, starts native heartbeat |
| `updateImage` | Existing image `containerId`, matching `containerName`, `data: Uint8List` (1–1,048,576 bytes), `compressMode` 0–2 default 0 | Native chunks complete firmware-format image and matches fragment ACKs |
| `updateText` | Existing text `containerId`/`containerName`; `content` 0–1999 UTF-8 bytes; `contentOffset` uint32 default 0; `contentLength` defaults to UTF-8 byte count; optional `textColor` 0–4 | Waits for native/device outcome |
| `rebuildPage` | Inline page fields as for create, without `widgetId` | Replace container/menu identities after ACK; retain page session |
| `shutdownPage` | `exitMode` 0 or 1, default 0 | 0 closes after ACK; 1 requests exit prompt and may return `awaitingExit: true` while page/heartbeat remain active |
| `heartbeat` | Empty map | Native normally schedules this automatically; host should not add a timer |
| `audioControl` | Required `enabled: bool` | Enable/disable microphone delivery on active page; wait for ACK |
| `menuStartupFailed` | Required `errorCode` uint32; `errorString` 0–199 UTF-8 bytes, default empty | READY required; may run without a page; one-way queue admission only |
| `imuControl` | Required `enabled: bool`; `reportFrequency` integer 100–1000, default 100 | Firmware report-frequency parameter; do not substitute arbitrary rate units |
| `menuSubitemResponse` | Current `parentItemId`, `subItemId`; `status` uint32 default 0 | One-way answer to actual menu switch; answer within firmware's 10-second deadline |

The completion map includes native operation/command and applicable page identity/heartbeat state. Inspect `acknowledged` versus `submitted`: one-way menu responses return `acknowledged: false, submitted: true`, not a device acknowledgement. `menuStartupFailed` does not create a page or return `pageSessionId`. A command failure throws `PlatformException`; a `resultCode` must not be interpreted uniformly as zero-success across commands. Native already interprets command-specific result codes.

### Page schema

Page fields are **inline**, not nested in a `page` key. Omitted arrays default to empty. Maximum lists/text/images: 4/8/4; total containers must be 1–12. Container IDs must be unique across all arrays; at most one container may capture events.

| Shape | Fields |
| --- | --- |
| Common container | Required `containerId` nonzero uint32, `containerName` 1–15 UTF-8 bytes, `width` 1–576, `height` 1–288; `xPosition` 0–576 default 0, `yPosition` 0–288 default 0; optional `zOrderIndex` uint32 |
| Text/list border fields | `borderWidth` 0–5, `borderColor` 0–15, `borderRadius` 0–10, `paddingLength` 0–32, defaults 0; `isEventCapture` bool default false |
| Text container | Common + border; `content` 0–999 UTF-8 bytes default empty; optional `textColor` 0–4 |
| List container | Common + border; required `itemContainer`: `itemNames` 1–20 strings of 0–63 UTF-8 bytes, `itemWidth` 0–576 default 0, `isItemSelectBorderEnabled` bool default false |
| Image container | Common, but `width` 20–288 and `height` 20–144; no text/list border fields |
| Menu | `items`: 1–10 menu items with unique IDs |
| Menu item | Required `itemId` nonzero uint32, `itemName` 1–31 UTF-8 bytes; `position` 0–10 default 0; `subItems` defaults empty, max 5; `checkedIndex` 0…subItems.length default 0 |
| Menu subitem | Required `itemId` nonzero uint32, `itemName` 1–31 UTF-8 bytes; IDs unique within each subitem list |

Every container must fit the canvas: `xPosition + width <= 576` and `yPosition + height <= 288`. Unknown keys, embedded NUL, invalid UTF-8/byte lengths and non-integer numeric values are rejected. Do not send native-owned `sessionId`, `containerTotalNum`, `mapSessionId`, `mapTotalSize`, `mapFragmentIndex`, `mapFragmentPacketSize`, `count`, `magic` or `syncId`. Logical payload limit is 32,768 bytes (image data uses its separate limit). Native command/fragment timeouts are 3 seconds. Scheduled heartbeats run 5 seconds **after a confirmed ACK**, not on a Flutter timer.

The following functions demonstrate explicit page creation and update. Call `createPage` only when there is no active page; do not combine it with `openEvenHubTextPage` for the same lease.

```dart
/// Native owns the session identity and only activates the page after its ACK.
Future<Map<String, Object?>> createEnterprisePage(EvenDevicesNative sdk) {
  return sdk.executeEvenHubCommand(EvenHubCommand.createPage, parameters: {
    'widgetId': 11417,
    'textObjects': [
      {
        'containerId': 1,
        'containerName': 'status',
        'xPosition': 0,
        'yPosition': 0,
        'width': 576,
        'height': 100,
        'content': 'Connected',
        'isEventCapture': true,
      },
    ],
  });
}

Future<Map<String, Object?>> updateEnterpriseText(EvenDevicesNative sdk) {
  return sdk.executeEvenHubCommand(EvenHubCommand.updateText, parameters: {
    'containerId': 1,
    'containerName': 'status',
    'content': 'Enterprise ready',
  });
}

Future<Map<String, Object?>> setGlassesAudio(
    EvenDevicesNative sdk, bool enabled) {
  return sdk.executeEvenHubCommand(EvenHubCommand.audioControl,
      parameters: {'enabled': enabled});
}
```

For `updateImage`, pass complete, already firmware-encoded image bytes corresponding to `compressMode`. A PNG/JPEG/BMP file is not automatically converted. Native owns map IDs, fragmentation and retries; Dart does not build fragments.

## 7. Events, microphone PCM and UI logging

`EvenDevicesEvent` retains unknown event types/phases for forward compatibility. Do not treat an unrecognized event as success. Useful fields:

| Group | Fields |
| --- | --- |
| Identity | `type`, `namespace`, `sn`, `side`, `endpointId` |
| Lifecycle | `generation`, `sessionGeneration`, `attemptGeneration`, `phase`, `failure`; missing optional generations remain null |
| Discovery | `devices: List<G2DiscoveredEndpoint>`; merge incremental observations by SN/side |
| Time sync | `type == 'timeSync'`, `success`, `failure` |
| Even Hub | `type == 'evenHub'`, `operation`, `event`, `heartbeatCount`; page lifecycle uses `active`/`closed` and failure phases |
| Audio | `audioPcm`, `sampleRate`, `channels`, `bitsPerSample`, `source`, `speakerRole`, optional signed `direction` |
| OTA | `operation`, `progress` 0…1, `phase`, `leftVersion`, `rightVersion`, `failure` |
| Raw envelope | `details: Map<String,Object?>` contains the **entire native envelope**, not just nested event details |

`transport` and `business` envelopes are diagnostic evidence, not whole-device READY. Only a `g2` event with `phase == 'ready'`, absent `side`, and current positive generation enables whole-device actions. Native fences stale callbacks; the UI should also scope asynchronous results to its selected device/session and OTA operation.

Even Hub `event` names include `click`, `scrollUp`, `scrollDown`, `doubleClick`, `foregroundEnter`, `foregroundExit`, `abnormalExit`, `exit`, `longPress`, `longPressRelease`, `audioEvent`, `imuData`, `privateEvent`, `timeoutPageEnter`, `timeoutPageExit`, `menuStartup`, `menuItemClick`, and `menuSubitemSwitch`. Additional decoded values are in `event.details['details']`:

- Device input (for example `click`): `kind` list/text/system. Containers include `containerId`/`containerName`; list input includes selected item name/index; system input includes source and exit reason, and optional widget/page identity.
- `imuData`: finite numeric `x`, `y`, `z`.
- `privateEvent`: container identity, `eventId`, `eventData`.
- Menu events: `widgetId`, `itemId`, or `parentItemId`/`subItemId`/`subItemIndex`, respectively. Use `menuSubitemResponse` to answer an actual switch event.

Enable audio only after page activation. Firmware must also expose STREAM notifications `6450/6402`; page display alone does not establish audio capability. Native subscribes the microphone stream and waits for the audio-control ACK. `audioEvent` supplies **signed PCM16 little-endian, 16,000 Hz, mono** as a read-only `Uint8List`; Flutter never receives LC3 as PCM. Native decodes 40-byte LC3 frames to 160 samples (320 PCM bytes) and processes tagged microphone blocks with its native PCM pipeline. Tagged speaker processing can emit an initial silence block while retaining the preceding block for the next packet; consumers should not assume every first block contains speech.

`source` identifies provenance (glasses); `speakerRole` and optional `direction` are native metadata, not proof of speaker identity. Disable, page closure, disconnect and reset revoke audio delivery. There is no public standalone LC3 decode/encode or arbitrary PCM-processing method. Route PCM to a bounded audio/file worker; wrap it yourself if a WAV container or player is required. Keep UI logs to byte counts and a short hex preview, without recording license material.

## 8. OTA lifecycle

1. Obtain the complete G2 firmware container and its exact expected version. The SDK does not download firmware from a release server.
2. Ensure **both legs READY**, close the Even Hub page and observe closure, and avoid concurrent time sync/page operations.
3. `await startOta(...)` returns a positive operation ID. Retain it; correlate all `ota` events and cancellation with that ID.
4. Show `progress` as transfer progress only. `transportCompleted` is **not installed success**.
5. Native reconnects/re-authorizes and reads both installed versions against `targetVersion`. Only terminal `succeeded` establishes verified success. Failure, cancellation, mismatch, or missing readback must not display an installed-success message.
6. Call `cancelOta(operationId: id)` to cancel that operation. A stale ID must not cancel its successor.

No R1/Nordic DFU is exposed. Firmware/device OTA acceptance is separate from an API build or unit test; this guide does not claim a new physical OTA test was performed.

## 9. Errors and integration checks

Bridge errors are `PlatformException`. Typical iOS bridge codes include `invalidArguments`, `invalidLicense`, `notInitialized`, `notReady`, `busy`, `detached`, and `nativeError`; Android also uses engine/permission-specific codes such as `sdkInUse`, `engineDetached`, and `permissionDenied`. Native Even Hub failure codes are forwarded. Connection/authorization errors may arrive as **events** even when `connectG2` completed normally. Preserve the received code; do not assume the two adapters rename every bridge error identically.

| Symptom | Check |
| --- | --- |
| Scan returns no observations | Foreground permission grant, Bluetooth state, older Android location state, glasses advertising, current scan subscription |
| `deviceNotSeen` on iOS | Scan in this native session; collect both sides; use current scanned UUIDs/cache, not only persisted hints |
| `proofNotFound` | Exact full advertised 14-byte SN exists in the current native bundle |
| Enterprise service unavailable | Correct enterprise firmware exposing 8450; no old-service fallback |
| One leg authorized but UI not READY | Inspect both enterprise and business AUTH stages; whole-device READY requires both legs |
| Page disappears / heartbeat fails | Inspect native EvenHub failure and confirmed `heartbeatCount`; do not introduce a Dart heartbeat timer |
| Time sync timeout or busy | Confirm READY, close active Even Hub page, finish/cancel OTA, inspect `timeSync` outcome |
| OTA reaches 100% | Wait for reconnect and matching two-leg version readback before reporting success |
| Account/engine changes | Reset current owner before replacing namespace; one native BLE owner per process |

Test both platforms with exact licensed devices: missing-SN denial, two-leg READY, reconnect reauthorization, page survival beyond 15 seconds, click/menu events, audio enable/disable, time sync and OTA readback/cancel. Record device/OS/firmware/SDK versions. Automated checks cannot substitute for these device tests.

## 10. References and baseline

- [Repository and Flutter example](https://github.com/even-realities/flutter_enterprise_sdk)
- [Public Dart client at the documented adapter commit](https://github.com/even-realities/flutter_enterprise_sdk/blob/ea53058edac83a6d7ecc6406593ab383c1f41e48/lib/src/client.dart)
- [Public event models](https://github.com/even-realities/flutter_enterprise_sdk/blob/ea53058edac83a6d7ecc6406593ab383c1f41e48/lib/src/models.dart)
- [Shared logical Even Hub command contract](https://github.com/even-realities/enterprise_sdk/blob/0.1.0-beta.14/native/protocol/evenhub_commands.json)
- [Android Kotlin guide](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-android-sdk.md) / [iOS Swift guide](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-ios-sdk.md)
- [Even Hub official documentation: Get Started / Overview](https://hub.evenrealities.com/docs/get-started/overview)

Native source build baseline: `f931d52d4716fd150f885f5168b64faabf20783a`. Native package version: `0.1.0-beta.14`. Installation examples and API signatures were checked against the current adapter and shipped native artifacts; physical integration remains the host team's device acceptance step.
