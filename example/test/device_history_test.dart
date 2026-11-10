import 'dart:async';
import 'dart:convert';

import 'package:even_devices_native/even_devices_native.dart';
import 'package:even_devices_native_example/device_history.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(DeviceHistoryStore.channelName);

  LastConnectedDevice device() => LastConnectedDevice(
        namespace: ' account A ',
        sn: 'S200LABJ270010',
        left: const G2Endpoint(address: 'left-local-uuid', name: 'G2 L'),
        right: const G2Endpoint(address: 'right-local-uuid', name: 'G2 R'),
        connectedAt: DateTime.utc(2026, 11, 9, 12),
      );

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('record round-trips platform-local locators and preserves namespace',
      () {
    final restored =
        LastConnectedDevice.decode(device().encode(), ' account A ');
    expect(restored.namespace, ' account A ');
    expect(restored.sn, 'S200LABJ270010');
    expect(restored.left.address, 'left-local-uuid');
    expect(restored.right.name, 'G2 R');
    expect(restored.connectedAt, DateTime.utc(2026, 11, 9, 12));
    expect(() => LastConnectedDevice.decode(device().encode(), 'account A'),
        throwsFormatException);
  });

  test('corrupt identities, endpoints, schema and timestamps fail closed', () {
    final valid = jsonDecode(device().encode()) as Map<String, dynamic>;
    for (final change in <Map<String, dynamic>>[
      {'sn': '270010'},
      {'schemaVersion': 2},
      {'connectedAt': 'not-a-date'},
      {'left': null},
      {'left': valid['right']},
      {
        'right': {'address': '', 'name': 'G2 R'}
      },
    ]) {
      expect(
          () => LastConnectedDevice.decode(
              jsonEncode({...valid, ...change}), ' account A '),
          throwsFormatException);
    }
  });

  test('save, forget and load stay ordered even when a write is delayed',
      () async {
    final admitted = Completer<void>();
    final finishWrite = Completer<void>();
    final calls = <String>[];
    String? stored;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'save') {
        admitted.complete();
        await finishWrite.future;
        stored = (call.arguments as Map)['record'] as String;
      } else if (call.method == 'clear') {
        stored = null;
      } else {
        return stored;
      }
      return null;
    });
    final history = DeviceHistoryStore();
    final save = history.save(device());
    final forget = history.clear(' account A ');
    final load = history.load(' account A ');
    await admitted.future;
    expect(calls, ['save']);
    finishWrite.complete();
    await save;
    await forget;
    expect(await load, isNull);
    expect(calls, ['save', 'clear', 'load']);
  });

  test('a failed storage operation does not poison later loads', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'save') {
        throw PlatformException(code: 'historyStorageFailed');
      }
      return device().encode();
    });
    final history = DeviceHistoryStore();
    await expectLater(
        history.save(device()), throwsA(isA<PlatformException>()));
    expect((await history.load(' account A '))!.sn, device().sn);
  });
}
