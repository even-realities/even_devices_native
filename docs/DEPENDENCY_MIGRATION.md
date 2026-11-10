# Gradle / SwiftPM dependency migration — 2026-11-10

The independent Flutter plugin `even_devices_native` pins native SDK **0.1.0-beta.14** on both platforms. Dart APIs and native protocol implementations are unchanged by this migration.

| Platform | Dependency | Runtime source |
| --- | --- | --- |
| Android | `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14` | [Maven Central](https://repo.maven.apache.org/maven2/com/evenrealities/devices/even-devices-native-android/0.1.0-beta.14/) |
| iOS | `EvenDevicesSDK`, exact `0.1.0-beta.14` | [Native SDK Git tag](https://github.com/even-realities/flutter_enterprise_sdk/tree/0.1.0-beta.14) |

The native-only SPM release tag resolves to `9dfd89047e1f1c97f5d4885c21b89e34f5f1b009`; its binary was built from native source commit `f931d52d4716fd150f885f5168b64faabf20783a`. Publishing that tag did not publish the Flutter adapter working-tree changes to `main`.

## Integration changes

- Android no longer injects `android/maven` or project dependency repositories. Hosts provide `google()` and `mavenCentral()`.
- The iOS adapter and privacy resource live in `ios/even_devices_native/Sources/even_devices_native`. Its package depends on the remote native product, separately from the root native SDK package.
- The plugin podspec was removed. Both example hosts use Flutter's generated SPM aggregate and shared scheme, without CocoaPods build phases.
- Archived AAR/XCFramework copies remain for provenance checks and are not referenced by the adapter build.
- Flutter 3.32+ is required. Enable SPM with `flutter config --enable-swift-package-manager` or use `FLUTTER_SWIFT_PACKAGE_MANAGER=true` for the build. See [setup](INTEGRATION.zh-CN.md#原生依赖管理).

## Verification

- Plugin: Flutter analysis and 20 tests passed. Example: 21 tests passed.
- Standalone and mirrored example: Android debug APK and iOS Profile device builds passed.
- Gradle dependency insight with refreshed metadata resolved beta.14 from `repo.maven.apache.org`; no local Maven repository was configured.
- Xcode resolved beta.14 through the public GitHub URL in a fresh `/tmp` SourcePackages directory without a SwiftPM mirror. A subsequent Flutter iOS Profile build passed without the mirror setting.
- The public SPM ZIP SHA-256 is `c32984425afffda456fccccb738b0c69d29080bdbe07d503154c501eac260e78`, matching the archived release exactly.
- A clean iOS build embeds only `App.framework`, `Flutter.framework`, and `EvenDevicesSDK.framework`, plus the SPM plugin privacy bundle. The old CocoaPods adapter framework is absent.
- Embedded device framework UUID `43E3383A-9102-3462-BDBC-3D0A72D693E0` matches the beta.14 archive.
- Both artifact verification scripts passed all 73 archived file checks and dependency-contract checks. Android plugin `lintDebug` passed.
- Compatibility repository: dependency resolution, Flutter analysis, all 518 tests, and `tool/verify_native_ble_sdk.sh` passed.
- This workstation now has Flutter SPM support enabled; the example also builds with the normal `fvm flutter build ios --profile --no-codesign --no-pub` command.

This change has not been installed on physical Android/iOS devices for a new connection test. Earlier beta.14 device evidence remains separate from this dependency-manager migration.
