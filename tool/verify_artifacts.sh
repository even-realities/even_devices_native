#!/bin/sh
# Verify the self-contained distribution and the example's resolved plugin graph.
set -eu
plugin_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$plugin_root"

python3 - <<'PY'
from pathlib import Path
import hashlib
import io
import json
import zipfile

root = Path('.')
expected = {}
for line in Path('checksums.sha256').read_text().splitlines():
    digest, name = line.split('  ', 1)
    assert name not in expected, f'Duplicate manifest entry: {name}'
    expected[name] = digest
actual = {p.as_posix() for folder in ('android/maven', 'ios/Frameworks', 'licenses', 'build_records')
          for p in Path(folder).rglob('*') if p.is_file()}
actual.update(('LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md'))
assert actual == expected.keys(), 'Artifact inventory differs from the manifest'
for name, digest in expected.items():
    path = Path(name)
    assert not path.is_symlink(), f'External artifact link: {name}'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f'Hash mismatch: {name}'

# Maven metadata/sidecars must describe the very AAR that ships inside this package.
version = '0.1.0-beta.11'
base = Path('android/maven/com/evenrealities/devices/even-devices-native-android') / version
stem = 'even-devices-native-android-' + version
for suffix in ('aar', 'module', 'pom'):
    artifact = base / f'{stem}.{suffix}'
    for algorithm in ('md5', 'sha1', 'sha256', 'sha512'):
        sidecar = artifact.with_name(artifact.name + '.' + algorithm)
        assert sidecar.read_text().strip() == hashlib.new(algorithm, artifact.read_bytes()).hexdigest(), sidecar
with zipfile.ZipFile(base / f'{stem}.aar') as aar:
    with zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as classes:
        names = set(classes.namelist())
        assert 'com/evenrealities/devices/EvenDevicesAndroidBle.class' in names
        assert 'com/evenrealities/devices/G2EvenHubCodec.class' in names
        assert 'com/evenrealities/devices/G2EvenHubCoordinator.class' in names
        command_class = classes.read('com/evenrealities/devices/G2EvenHubCodec$Command.class')
        for command in ('createPage', 'updateImage', 'updateText', 'rebuildPage',
                        'shutdownPage', 'heartbeat', 'audioControl',
                        'menuStartupFailed', 'imuControl', 'menuSubitemResponse'):
            assert command.encode() in command_class, f'Missing native command: {command}'
        assert b'executeEvenHubCommand' in classes.read('com/evenrealities/devices/EvenDevicesAndroidBle.class')
        assert not any('FlutterEzwBlePlugin' in n or n.startswith('io/flutter/') for n in names), 'Legacy Flutter classes in standalone AAR'

# The Swift interface must expose the native page owner, not a Dart-only demo.
interfaces = list(Path('ios/Frameworks/EvenDevicesSDK.xcframework').glob('**/*.swiftinterface'))
assert interfaces, 'Missing native Swift interfaces'
for interface in interfaces:
    declarations = interface.read_text()
    assert 'openEvenHubTextPage' in declarations and 'closeEvenHub' in declarations, interface
    assert 'executeEvenHubCommand' in declarations, interface

# Retain each fresh native packager's source digest and validation record with
# the payload; a version label alone cannot prove the new core was packaged.
for platform in ('android', 'ios'):
    record = json.loads(Path(f'build_records/{platform}.json').read_text())
    if platform == 'android':
        assert record['remote_published'] is False
        assert record['coordinate'].endswith(':' + version)
        assert len(record['android_source_sha256']) == 64
    else:
        assert record['version'] == version and record['build_number'] == '11'
        assert all(len(digest) == 64 for digest in record['source_sha256'].values())
        assert any('G2EvenHub' in path for path in record['source_sha256'])

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
