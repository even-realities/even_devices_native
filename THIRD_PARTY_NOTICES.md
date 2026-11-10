# Third-party notices

The Flutter adapter and Even-owned SDK code use Apache-2.0; see LICENSE and NOTICE.

- Android standalone SDK incorporates the audited flutter_ezw_ble G2 BLE subset (MIT). See [license](licenses/flutter_ezw_ble_LICENSE) and META-INF/licenses inside its AAR.
- Android Maven metadata pins Gson 2.11.0 (Apache-2.0), Kotlin stdlib 2.1.10 (Apache-2.0) and kotlinx-coroutines-android 1.10.2 (Apache-2.0); Gradle resolves their published transitive artifacts.
- iOS EvenDevicesSDK.xcframework contains its own LICENSE, NOTICE and THIRD_PARTY_NOTICES.md. Its G2 implementation does not link a Flutter runtime.
- Flutter is supplied by the host under its own BSD-style license; no Flutter runtime is embedded in the standalone native SDK artifacts.

The SDK source and build provenance are recorded in PROVENANCE.md. Third-party licenses remain applicable to their respective components.
