# Native artifact provenance

This independent adapter pins both platforms to the locally rebuilt standalone **0.1.0-beta.11** SDK. The native cores own all ten EvenHub application commands, semantic events, page leases, image/transport fragmentation, ACK correlation and cancellation. Flutter only forwards logical arguments and events.

- Android: `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.11`, including POM, Gradle metadata and hash sidecars. The standalone AAR contains no Flutter plugin/runtime. Native source digest: `d8201c04ae6ddebb6a6c1c0839dfde0c01a56f3a6f8775640ffff4cf0cbc3ced`. Build and validation record: [android.json](build_records/android.json).
- iOS: complete `EvenDevicesSDK.xcframework`, bundle version 0.1.0, build 11, arm64 device and arm64/x86_64 simulator. The archive SHA-256 is `8371b4005fb44bd49c7bc2905918eade73e68021df505cfbf332e3d254940199`. Individual native source digests, toolchain and consumer-link checks: [ios.json](build_records/ios.json).
- Both artifacts were built from base commit `ad90051d51a2a022de901e9cc2933a64bbed7429` plus the current uncommitted native EvenHub changes. The records explicitly retain dirty-source status; this is not a clean tagged release.
- The compatibility plugin's beta.5 binaries are separate and were not replaced by this build. The independent adapter uses the ordinary standalone Android coordinate, not the isolated compatibility variant.
- Upstream audited G2 BLE reference remains `flutter_ezw_ble@c2e101c9bbc18c7372d439fdbb77b33da84df76b`, utility reference `53ef9f052653b8b7c9ffacce20ee2ad88e5ef7ed`. Android adds the native logical-command queue lease/admission patch; Swift owns its CoreBluetooth implementation. Both restore legacy empty heartbeat requests and accept optional non-echoed ACK counters and declared-length transport padding.

`checksums.sha256` covers every packaged Maven/XCFramework file, build record and license notice. Run `tool/verify_artifacts.sh` after `fvm flutter pub get`. Native upgrades must rebuild both platforms, preserve build records and refresh the complete inventory.

Local validation: Android 92 unit tests plus release lint/AAR/Maven checks; Swift 60 tests plus device and both simulator consumer links. Flutter bridge and example tests are recorded in [the validation report](docs/VALIDATION.md#evenhub).

No remote Maven/SPM publication was performed. On WK iPhone 15, the user reported 37 native heartbeat confirmations with beta.9. This is user-observed hardware feedback; continuous ACK logs were unavailable after the console connection dropped. Android hardware and close/stop behavior remain unverified. Image input is whole firmware-format bytes; PNG/BMP pixel conversion and compression tools remain outside this implementation.

Beta.9 adds only the observed enterprise heartbeat ACK Cmd12 dialect, retaining standard Cmd13 and all branch/result/identity checks. Swift logs keep the actual Cmd; local automated validation does not establish real-device acceptance.

Beta.10 fixes independently reproduced Android TimeSync framing/parser defects and hardens matching Swift semantics. It adds numeric-only iOS business transport diagnostics without changing timeout, magic width or request ownership. Subsequent beta.10 persisted iOS logs confirmed low-byte magic echoes (40085 -> 149 and 45795 -> 227); see [the TimeSync report](docs/VALIDATION.md#timesync).

Beta.11 allocates TimeSync request magic in 1–255 in both native SDKs, preserving exact full-value ACK comparison, generation ownership and existing timeouts. Swift reuses its AUTH allocator instead of adding another counter. Shared contract and three-cycle regression coverage record the firmware boundary. WK iPhone 15 repair acceptance and Android hardware remain pending. Source identities above describe beta.11; historical beta.9 heartbeat feedback is unchanged.
