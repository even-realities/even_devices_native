import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incremental discovery preserves native SN and endpoint side', () {
    final event = EvenDevicesEvent.fromNative(const {
      'type': 'discovery',
      'sn': 'S200TEST000002',
      'devices': [
        {'side': 'right', 'address': 'native-uuid', 'name': ''},
      ],
    });
    expect(event.sn, 'S200TEST000002');
    expect(event.devices.single.side, 'right');
    expect(event.devices.single.address, 'native-uuid');
    expect(() => event.devices.clear(), throwsUnsupportedError);
  });

  test('unknown phases remain unknown and unavailable identities remain null',
      () {
    final event = EvenDevicesEvent.fromNative(const {
      'type': 'futureType',
      'phase': 'futurePhase',
      'futureField': {'value': 1},
    });
    expect(event.phase, 'futurePhase');
    expect(event.sessionGeneration, isNull);
    expect(event.attemptGeneration, isNull);
    expect(event.details['futureField'], {'value': 1});
    expect(() => event.details.clear(), throwsUnsupportedError);
  });

  test('invalid native envelope or generation never becomes a valid event', () {
    for (final payload in [
      null,
      'ready',
      <String, Object?>{},
      {'type': ''},
      {'type': 'g2', 42: 'bad key'},
      {'type': 'g2', 'sn': 42},
      {'type': 'g2', 'generation': 1.5},
      {'type': 'g2', 'sessionGeneration': -1},
      {'type': 'g2', 'attemptGeneration': '1'},
      {'type': 'timeSync', 'success': 'true'},
    ]) {
      expect(() => EvenDevicesEvent.fromNative(payload), throwsFormatException);
    }
  });

  test('unknown discovery side cannot be used as a left or right endpoint', () {
    expect(
      () => EvenDevicesEvent.fromNative(const {
        'type': 'discovery',
        'devices': [
          {'side': 'futureSide', 'address': 'device'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('EvenHub preserves native input, lease result and endpoint ownership',
      () {
    final event = EvenDevicesEvent.fromNative(const {
      'type': 'evenHub',
      'phase': 'input',
      'event': 'click',
      'heartbeatCount': 0,
      'operation': 11,
      'sn': 'S200TEST000002',
      'side': 'right',
      'endpointId': 'native-uuid',
      'sessionGeneration': 7,
      'attemptGeneration': 9,
    });
    expect(event.event, 'click');
    expect(event.heartbeatCount, 0);
    expect(event.operation, 11);
    expect(event.sessionGeneration, 7);
    expect(event.attemptGeneration, 9);
    for (final field in [
      {'event': 0},
      {'heartbeatCount': -1},
      {'heartbeatCount': '1'}
    ]) {
      expect(() => EvenDevicesEvent.fromNative({'type': 'evenHub', ...field}),
          throwsFormatException);
    }
  });
}
