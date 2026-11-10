import 'dart:async';

import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel(EvenDevicesNative.methodChannelName);
  const events = MethodChannel(EvenDevicesNative.eventChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late EvenDevicesNative sdk;
  late List<MethodCall> calls;

  setUp(() {
    sdk = EvenDevicesNative();
    calls = [];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return call.method == 'requestBluetoothPermissions' ? true : null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('raw portal input reaches native unchanged, including malformed JSON',
      () async {
    // Intentionally not valid JSON: Flutter must not validate or repair it.
    const raw = '  {"app_id":" Exact App ","licenses":[not-json]}\n';
    await sdk.initialize(namespace: 'account-a', licenseJson: raw);
    await sdk.updateLicenses(raw);
    expect(calls[0].arguments, {'namespace': 'account-a', 'licenseJson': raw});
    expect(calls[1].arguments, {'licenseJson': raw});
    expect(calls.map((call) => call.method), ['initialize', 'updateLicenses']);
  });

  test('native alone rejects an SN missing from its license snapshot',
      () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      throw PlatformException(code: 'invalidArguments', message: 'No proof');
    });
    await expectLater(
      sdk.connectG2(
        sn: 'UNLICENSED_SN',
        left: const G2Endpoint(address: 'AA:BB:CC:DD:EE:01', name: 'left'),
        right: const G2Endpoint(address: 'AA:BB:CC:DD:EE:02', name: 'right'),
      ),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'invalidArguments')),
    );
    expect(calls.single.arguments, {
      'sn': 'UNLICENSED_SN',
      'leftAddress': 'AA:BB:CC:DD:EE:01',
      'leftName': 'left',
      'rightAddress': 'AA:BB:CC:DD:EE:02',
      'rightName': 'right',
    });
  });

  test('iOS SN-only request does not acquire Dart endpoint or proof state',
      () async {
    await sdk.connectG2(sn: 'S200TEST000002');
    expect(calls.single.arguments, {
      'sn': 'S200TEST000002',
      'leftAddress': null,
      'leftName': null,
      'rightAddress': null,
      'rightName': null,
    });
  });

  test('lifecycle and time sync requests only cross the channel', () async {
    expect(await sdk.requestBluetoothPermissions(), isTrue);
    await sdk.scan();
    await sdk.stopScan();
    await sdk.disconnectG2();
    await sdk.syncG2Time();
    await sdk.reset();
    expect(calls.map((call) => call.method), [
      'requestBluetoothPermissions',
      'scan',
      'stopScan',
      'disconnectG2',
      'syncG2Time',
      'reset',
    ]);
  });

  test('OTA forwards the original image and cancels the native operation',
      () async {
    const nativeId = 0x100000003;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return call.method == 'startOta' ? nativeId : null;
    });
    final image = Uint8List.fromList([0, 1, 128, 255]);
    final operation =
        await sdk.startOta(firmware: image, targetVersion: '2.4.1.2');
    expect(operation, nativeId);
    await sdk.cancelOta(operationId: operation);
    expect(calls.map((call) => call.method), ['startOta', 'cancelOta']);
    expect(
        calls.first.arguments, {'firmware': image, 'targetVersion': '2.4.1.2'});
    expect(calls.last.arguments, {'operationId': nativeId});
  });

  test('OTA admission failure propagates and an absent operation ID fails',
      () async {
    final image = Uint8List(1);
    messenger.setMockMethodCallHandler(methods, (_) async {
      throw PlatformException(code: 'busy');
    });
    await expectLater(
        sdk.startOta(firmware: image, targetVersion: '2.4.1.2'),
        throwsA(
            isA<PlatformException>().having((e) => e.code, 'code', 'busy')));
    for (final invalidId in [null, 0, -1]) {
      messenger.setMockMethodCallHandler(methods, (_) async => invalidId);
      await expectLater(sdk.startOta(firmware: image, targetVersion: '2.4.1.2'),
          throwsFormatException);
    }
  });

  test('a missing native permission result cannot become a grant', () async {
    messenger.setMockMethodCallHandler(methods, (_) async => null);
    expect(await sdk.requestBluetoothPermissions(), isFalse);
  });

  test('EvenHub text reaches native unchanged and close only submits a request',
      () async {
    // Native owns UTF-8 limits, CREATE acknowledgement, heartbeats and cleanup.
    // Empty or long input must reach the native validator rather than being
    // silently transformed into a different glasses page by the Dart adapter.
    for (final text in ['  Hello\n眼镜  ', '', List.filled(65, '字').join()]) {
      await sdk.openEvenHubTextPage(text: text);
      expect(calls.last.method, 'openEvenHubTextPage');
      expect(calls.last.arguments, {'text': text});
    }
    await sdk.closeEvenHub();
    expect(calls.last.method, 'closeEvenHub');
    expect(calls.last.arguments, isNull);
    expect(calls.length, 4);
  });

  test('native EvenHub rejection propagates without a Dart retry or heartbeat',
      () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      throw PlatformException(code: 'notReady');
    });
    await expectLater(
        sdk.openEvenHubTextPage(text: 'Hello'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'notReady')));
    expect(calls.map((call) => call.method), ['openEvenHubTextPage']);
  });

  test('native errors are propagated without a Dart retry', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      throw PlatformException(code: 'invalidLicense');
    });
    await expectLater(
      sdk.updateLicenses('raw'),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'invalidLicense')),
    );
    expect(calls.length, 1);
  });

  test('all logical EvenHub commands delegate parameters and native results',
      () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return {'status': 'completed', 'command': call.arguments['command']};
    });
    final bytes = Uint8List.fromList([0, 127, 255]);
    final parameters = <String, Object?>{
      'content': '  字幕\n',
      'data': bytes,
      'enabled': true,
      'textObjects': [
        {'containerId': 1, 'containerName': 'native-text'}
      ],
    };
    // Even invalid per-command parameters pass through: only native decides
    // admission, so a native host receives exactly the same validation rules.
    for (final command in EvenHubCommand.values) {
      final result =
          await sdk.executeEvenHubCommand(command, parameters: parameters);
      expect(result, {'status': 'completed', 'command': command.name});
      expect(calls.last.method, 'executeEvenHubCommand');
      expect(calls.last.arguments,
          {'command': command.name, 'parameters': parameters});
    }
    expect(calls.length, 10);
  });

  test('EvenHub command future waits for native and rejects a missing result',
      () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(methods, (_) => pending.future);
    var completed = false;
    final command = sdk.executeEvenHubCommand(EvenHubCommand.heartbeat)
      ..then<void>((_) => completed = true, onError: (_) {});
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    pending.complete(null);
    await expectLater(command, throwsFormatException);
  });

  test('multiple listeners share one sink and last cancel releases it',
      () async {
    final controls = <String>[];
    messenger.setMockMethodCallHandler(events, (call) async {
      controls.add(call.method);
      return null;
    });
    final first = <EvenDevicesEvent>[];
    final second = <EvenDevicesEvent>[];
    final a = sdk.events.listen(first.add);
    final b = sdk.events.listen(second.add);
    await Future<void>.delayed(Duration.zero);
    expect(controls, ['listen']);
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      EvenDevicesNative.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'type': 'g2',
        'namespace': 'account-a',
        'sn': 'S200TEST000002',
        'phase': 'ready',
        'generation': 4,
      }),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
    expect(first.single.generation, 4);
    expect(second.single.sn, 'S200TEST000002');
    expect(first.single.sessionGeneration, isNull);
    await a.cancel();
    expect(controls, ['listen']);
    await b.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(controls, ['listen', 'cancel']);
    expect(calls, isEmpty); // Subscription changes never call reset/disconnect.
  });
}
