# Native artifact provenance

This independent adapter pins both platforms through Maven Central and SwiftPM to standalone **0.1.0-beta.14** SDK. The native cores own the G2 OTA transaction and post-reconnect verification, along with all ten EvenHub application commands, semantic events, page leases, image/transport fragmentation, ACK correlation and cancellation. Flutter only forwards logical arguments and events.

## Native binaries and corresponding source

Both platforms use native source commit `f931d52d4716fd150f885f5168b64faabf20783a` from the self-contained Git bundle in the [beta.14 source archive](source/native-sdk-0.1.0-beta.14.tar.gz). The compressed archive SHA-256 is `1e48dc1507515a83af8aba917db78e4905c41d796b11e1ef4b1956201b7945a9`. Extract the archive and follow `BUILD.md` to clone the bundled repository and run `tool/package_native_sdk.sh 0.1.0-beta.14` with build number 14.

| Delivery | Audit record |
| --- | --- |
| Android Maven release AAR, POM and Gradle module metadata for `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14` | [Android source commit, input digest and checks](build_records/android.json) |
| Archived iOS XCFramework and SwiftPM archive with framework bundle version `0.1.0`, build `14` | [iOS source commit, file hashes, ZIP checksum and consumer link checks](build_records/ios.json) |

The original BLE revision is [company GitLab commit c2e101c9](http://192.168.2.101/even/applications/app/ezw/flutter_ezw_ble/-/commit/c2e101c9bbc18c7372d439fdbb77b33da84df76b). The utility revision is [Whiskee/flutter_ezw_utils commit 53ef9f05](https://github.com/Whiskee/flutter_ezw_utils/commit/53ef9f052653b8b7c9ffacce20ee2ad88e5ef7ed). Recipients can inspect the retained upstream files and changes locally via `UPSTREAM_FILES.tsv`, `native/UPSTREAM_SOURCES.md` and `git diff fa66b7d HEAD -- native/android/src/main/kotlin/com/fzfstudio` in the source checkout. The Android diff includes enterprise G2 admission and command ownership. Swift implements the G2 CoreBluetooth connection.

The [LC3 vendor revision](https://github.com/Whiskee/flutter_ezw_lc3/commit/c8d02472bca0d5c0e55b4c31a3d8d949c375d9ca) supplies codec binaries and headers. The source bundle includes those exact inputs and the SDK's editable Kotlin, Swift, C and JNI integration, protocol fixtures and build entry points. See [third-party notices](THIRD_PARTY_NOTICES.md) for the scope of the codec license evidence.

`checksums.sha256` covers the AAR, Maven sidecars, archived framework, active SwiftPM ZIP, native source archive, records and legal notices. Run `tool/verify_artifacts.sh` after `fvm flutter pub get` to validate the delivered files and source commit.

Native verification commands and source digests are preserved in the build records; Flutter bridge, example and consumer-build checks are recorded in [the validation report](docs/VALIDATION.md).

Android beta.14 was published to Maven Central; the SwiftPM binary is distributed under the matching beta.14 Git tag. Local archives remain available for source and checksum verification. On WK iPhone 15, the user reported 37 native heartbeat confirmations with beta.9. This is user-observed hardware feedback; continuous ACK logs were unavailable after the console connection dropped. Android hardware and close/stop behavior remain unverified. Image input is whole firmware-format bytes; PNG/BMP pixel conversion and compression tools remain outside this implementation.

Beta.9 adds only the observed enterprise heartbeat ACK Cmd12 dialect, retaining standard Cmd13 and all branch/result/identity checks. Swift logs keep the actual Cmd; local automated validation does not establish real-device acceptance.

Beta.10 fixes independently reproduced Android TimeSync framing/parser defects and hardens matching Swift semantics. It adds numeric-only iOS business transport diagnostics without changing timeout, magic width or request ownership. Subsequent beta.10 persisted iOS logs confirmed low-byte magic echoes (40085 -> 149 and 45795 -> 227); see [the TimeSync report](docs/VALIDATION.md#timesync).

Beta.11 allocates TimeSync request magic in 1–255 in both native SDKs, preserving exact full-value ACK comparison, generation ownership and existing timeouts. Swift reuses its AUTH allocator instead of adding another counter. Shared contract and three-cycle regression coverage record the firmware boundary. WK iPhone 15 repair acceptance and Android hardware remain pending.

Beta.12 adds native G2 OTA and post-reconnect version verification. The versioned AAR, XCFramework and Flutter example were built locally. Physical dual-temple update acceptance remains pending.

Beta.13 adds native STREAM/LC3 decoding to 16 kHz mono PCM16 little-endian, direction-based speaker metadata and binary audioEvent delivery. The bundled LC3 headers carry the Google LLC Apache-2.0 notice in licenses/liblc3_LICENSE. Android ships four JNI ABI slices retaining the original production decoder under an isolated SONAME. iOS links the original decoder, using its embedded LLVM IR for supported architecture rebuilds; it does not substitute a generic liblc3 source release. Demo controls and frame counters do not record audio. Glasses microphone acceptance remains pending.

Beta.14 synchronizes Android business authentication with the two-stage firmware response handled by Swift. Both release records identify the updated corresponding source.
