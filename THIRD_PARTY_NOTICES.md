# Third-party notices

SDK and Flutter adapter code owned by Hong Kong Even Realities Limited is licensed under Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

- Android contains the G2 subset of `flutter_ezw_ble` (`com.fzfstudio.ezw_ble`) and Kotlin utilities from `flutter_ezw_utils` (`com.fzfstudio.ezw_utils`). Both carry MIT and Copyright (c) 2025 Whiskee. The AAR carries their identical MIT text and copyright notice at `classes.jar/META-INF/licenses/flutter_ezw_ble_LICENSE`. Open `classes.jar/META-INF/THIRD_PARTY_NOTICES.md` for the component mapping. See the [BLE license](licenses/flutter_ezw_ble_LICENSE) and [utility license](licenses/flutter_ezw_utils_LICENSE).
- Android Maven metadata pins Gson 2.11.0 (Apache-2.0), Kotlin stdlib 2.1.10 (Apache-2.0) and kotlinx-coroutines-android 1.10.2 (Apache-2.0); Gradle resolves their published transitive artifacts.
- iOS EvenDevicesSDK.xcframework contains its own LICENSE, NOTICE and THIRD_PARTY_NOTICES.md. Its G2 implementation does not link a Flutter runtime.
- Both platforms include precompiled LC3 inputs from `flutter_ezw_lc3@c8d02472bca0d5c0e55b4c31a3d8d949c375d9ca`. The shipped LC3 headers identify Google LLC and Apache-2.0. The [codec license](licenses/liblc3_LICENSE) accompanies the SDK. The source bundle retains the headers, input binaries and build records. The vendor package's root LICENSE contains a placeholder, and the original implementation source revision and rights for the precompiled objects still require confirmation.
- Flutter is supplied by the host under its own BSD-style license; no Flutter runtime is embedded in the standalone native SDK artifacts.

The SDK source and build provenance are recorded in PROVENANCE.md. Third-party licenses remain applicable to their respective components.
