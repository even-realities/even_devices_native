#!/bin/sh
# Verify archived release provenance and the remote dependency contract.
set -eu
plugin_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$plugin_root"

python3 - <<'PY'
from pathlib import Path
import hashlib
import io
import json
import re
import subprocess
import tarfile
import tempfile
import zipfile

root = Path('.')
expected = {}
for line in Path('checksums.sha256').read_text().splitlines():
    digest, name = line.split('  ', 1)
    assert name not in expected, f'Duplicate manifest entry: {name}'
    expected[name] = digest
actual = {p.as_posix() for folder in ('android/maven', 'ios/Frameworks', 'licenses', 'build_records')
          for p in Path(folder).rglob('*') if p.is_file()}
actual.update(('LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md', 'Package.swift', 'PROVENANCE.md', 'spm/provenance.json'))
version = re.search(r'^version: (\S+)$', Path('pubspec.yaml').read_text(), re.M).group(1)
source = Path(f'source/native-sdk-{version}.tar.gz')
swift_zip = Path(f'spm/EvenDevicesSDK-{version}.xcframework.zip')
actual.update((source.as_posix(), swift_zip.as_posix()))
assert actual == expected.keys(), 'Artifact inventory differs from the manifest'
for name, digest in expected.items():
    path = Path(name)
    assert not path.is_symlink(), f'External artifact link: {name}'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f'Hash mismatch: {name}'

# Maven metadata/sidecars must describe the very AAR that ships inside this package.
# The adapters pin the same immutable native release through Maven Central and
# the standalone native repository. Root Package.swift remains the legacy archive
# and is independently hash-checked above, never a dependency of this adapter.
assert f'even-devices-native-android:{version}"' in Path('android/build.gradle').read_text()
gradle = Path('android/build.gradle').read_text()
assert 'mavenCentral()' in gradle
assert 'nativeSdkRepository' not in gradle and '$projectDir/maven' not in gradle
manifest = Path('ios/even_devices_native/Package.swift')
package = json.loads(subprocess.check_output(
    ['swift', 'package', '--package-path', str(manifest.parent), 'dump-package'], text=True))
remote = package['dependencies'][0]['sourceControl'][0]
assert remote['location']['remote'][0]['urlString'] == 'https://github.com/even-realities/enterprise_sdk.git'
assert remote['requirement']['exact'] == [version]
assert package['products'][0]['name'] == 'even-devices-native'
assert package['targets'][0]['dependencies'][0]['product'][:2] == ['EvenDevicesSDK', 'enterprise_sdk']
assert Path('ios/even_devices_native/Sources/even_devices_native/PrivacyInfo.xcprivacy').is_file()
assert not Path('ios/even_devices_native.podspec').exists(), 'Unexpected CocoaPods fallback'
base = Path('android/maven/com/evenrealities/devices/even-devices-native-android') / version
stem = 'even-devices-native-android-' + version
for suffix in ('aar', 'module', 'pom'):
    artifact = base / f'{stem}.{suffix}'
    for algorithm in ('md5', 'sha1', 'sha256', 'sha512'):
        sidecar = artifact.with_name(artifact.name + '.' + algorithm)
        assert sidecar.read_text().strip() == hashlib.new(algorithm, artifact.read_bytes()).hexdigest(), sidecar
with zipfile.ZipFile(base / f'{stem}.aar') as aar:
    # Audio is decoded natively on every supported Android ABI, never in Dart.
    for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
        for library in ('libeven_lc3.so', 'libeg3.so'):
            assert f'jni/{abi}/{library}' in aar.namelist(), f'Missing LC3 ABI: {abi}/{library}'
    assert Path('licenses/liblc3_LICENSE').is_file(), 'Missing bundled codec license'
    with zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as classes:
        names = set(classes.namelist())
        # Standalone AAR consumers must be able to resolve the NOTICE reference inside classes.jar.
        assert classes.read('META-INF/even-devices-NOTICE.txt') == Path('NOTICE').read_bytes()
        assert classes.read('META-INF/even-devices-LICENSE.txt') == Path('LICENSE').read_bytes()
        inventory = classes.read('META-INF/THIRD_PARTY_NOTICES.md').decode()
        for component in ('flutter_ezw_ble', 'flutter_ezw_utils', 'liblc3'):
            assert component in inventory, f'Missing attribution: {component}'
        for name in ('flutter_ezw_ble_LICENSE', 'liblc3_LICENSE'):
            assert classes.read('META-INF/licenses/' + name) == Path('licenses', name).read_bytes()
        assert classes.read('META-INF/licenses/flutter_ezw_ble_LICENSE') == Path('licenses/flutter_ezw_utils_LICENSE').read_bytes()
        assert 'com/evenrealities/devices/EvenDevicesAndroidBle.class' in names
        assert 'com/evenrealities/devices/G2EvenHubCodec.class' in names
        assert 'com/evenrealities/devices/G2EvenHubCoordinator.class' in names
        command_class = classes.read('com/evenrealities/devices/G2EvenHubCodec$Command.class')
        for command in ('createPage', 'updateImage', 'updateText', 'rebuildPage',
                        'shutdownPage', 'heartbeat', 'audioControl',
                        'menuStartupFailed', 'imuControl', 'menuSubitemResponse'):
            assert command.encode() in command_class, f'Missing native command: {command}'
        sdk_api = classes.read('com/evenrealities/devices/EvenDevicesAndroidBle.class')
        for method in (b'executeEvenHubCommand', b'startOta', b'cancelOta'):
            assert method in sdk_api, f'Missing Android SDK method: {method!r}'
        assert not any('FlutterEzwBlePlugin' in n or n.startswith('io/flutter/') for n in names), 'Legacy Flutter classes in standalone AAR'

# The Swift interface must expose the native page owner, not a Dart-only demo.
interfaces = list(Path('ios/Frameworks/EvenDevicesSDK.xcframework').glob('**/*.swiftinterface'))
assert interfaces, 'Missing native Swift interfaces'
for interface in interfaces:
    declarations = interface.read_text()
    assert 'openEvenHubTextPage' in declarations and 'closeEvenHub' in declarations, interface
    for method in ('executeEvenHubCommand', 'startOta', 'cancelOta'):
        assert f'func {method}(' in declarations, f'{method} missing from {interface}'

# Retain each fresh native packager's source digest and validation record with
# the payload; a version label alone cannot prove the new core was packaged.
for platform in ('android', 'ios'):
    record = json.loads(Path(f'build_records/{platform}.json').read_text())
    if platform == 'android':
        assert record['working_tree_dirty'] is False
        # This immutable build-time record predates publishing; registry state is checked separately.
        assert record['remote_published'] is False
        assert record['coordinate'].endswith(':' + version)
        assert len(record['android_source_sha256']) == 64
    else:
        assert record['source_dirty'] is False
        assert record['version'] == version and record['build_number'] == version.rsplit('.', 1)[-1]
        assert all(len(digest) == 64 for digest in record['source_sha256'].values())
        assert any('G2EvenHub' in path for path in record['source_sha256'])

# Check both records against a commit available to recipients even without access to GitLab.
android = json.loads(Path('build_records/android.json').read_text())
ios = json.loads(Path('build_records/ios.json').read_text())
assert android['source_commit'] == ios['source_commit']
with tarfile.open(source, 'r:gz') as archive, tempfile.TemporaryDirectory() as work:
    entries = [item for item in archive if item.isfile() and Path(item.name).name == 'native-sdk.bundle']
    assert len(entries) == 1, 'Missing native source Git bundle'
    bundle = Path(work) / 'native-sdk.bundle'
    bundle.write_bytes(archive.extractfile(entries[0]).read())
    head = subprocess.check_output(['git', 'bundle', 'list-heads', str(bundle), 'refs/heads/main'], text=True)
    assert head.split() == [ios['source_commit'], 'refs/heads/main'], 'Native source revision mismatch'

# The remote SwiftPM release must match the archived framework from the packaging run.
assert Path('spm/provenance.json').read_bytes() == Path('build_records/ios.json').read_bytes()
assert swift_zip.name == ios['zip'] and expected[swift_zip.as_posix()] == ios['zip_sha256']
assert f'path: "{swift_zip}"' in Path('Package.swift').read_text()
framework = Path('ios/Frameworks/EvenDevicesSDK.xcframework')
with zipfile.ZipFile(swift_zip) as archive:
    prefix = framework.name + '/'
    files = {p.relative_to(framework).as_posix(): p for p in framework.rglob('*') if p.is_file()}
    archived = {e.filename[len(prefix):] for e in archive.infolist() if not e.is_dir() and e.filename.startswith(prefix)}
    assert files.keys() == archived, 'SwiftPM framework file set differs from archived framework'
    for name, path in files.items():
        assert path.read_bytes() == archive.read(prefix + name), f'SwiftPM framework mismatch: {name}'

# This host must register only this adapter, never the compatibility SDK or its BLE plugin.
graph = Path('example/.flutter-plugins-dependencies')
assert graph.exists(), 'Run fvm flutter pub get in the package before verification'
plugins = json.loads(graph.read_text())['plugins']
for platform in ('android', 'ios'):
    assert [p['name'] for p in plugins[platform]] == ['even_devices_native'], f'Unexpected {platform} plugin graph'
print(f'Verified {len(expected)} artifact/license hashes, Maven sidecars and independent plugin graph.')
PY

# Validate both Apple platform slices without building or touching a device.
framework=ios/Frameworks/EvenDevicesSDK.xcframework
lipo "$framework/ios-arm64/EvenDevicesSDK.framework/EvenDevicesSDK" -verify_arch arm64
# Xcode 27 lipo rejects a combined verify_arch list; each slice is still mandatory.
lipo "$framework/ios-arm64_x86_64-simulator/EvenDevicesSDK.framework/EvenDevicesSDK" -verify_arch arm64
lipo "$framework/ios-arm64_x86_64-simulator/EvenDevicesSDK.framework/EvenDevicesSDK" -verify_arch x86_64
printf '%s\n' 'Native Flutter plugin artifacts verified.'
