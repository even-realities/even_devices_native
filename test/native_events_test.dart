import 'dart:typed_data';

import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/services.dart' show StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio preserves native binary PCM and endpoint ownership', () {
    final pcm = Uint8List.fromList([0, 128, 255, 127]);
    final details = <String, Object?>{
      'audioPcm': pcm,
      'sampleRate': 16000,
      'channels': 1,
      'bitsPerSample': 16,
      'source': 'glasses',
      'speakerRole': 'unknown',
    };
    Map<String, Object?> envelope(Map<String, Object?> audio) => {
          'type': 'evenHub',
          'phase': 'input',
          'event': 'audioEvent',
          'sessionGeneration': 7,
          'attemptGeneration': 9,
          'details': audio,
        };
    // Exercise the exact platform codec: typed bytes must survive as binary.
    final encoded =
        const StandardMethodCodec().encodeSuccessEnvelope(envelope(details));
    final event = EvenDevicesEvent.fromNative(
        const StandardMethodCodec().decodeEnvelope(encoded));
    expect(event.audioPcm, orderedEquals(pcm));
    expect(() => event.audioPcm![0] = 1, throwsUnsupportedError);
    expect(event.sampleRate, 16000);
    expect(event.channels, 1);
    expect(event.bitsPerSample, 16);
    expect(event.source, 'glasses');
    expect(event.speakerRole, 'unknown');
    expect(event.direction, isNull);
    // Preserve signed wire metadata and the App classifier's result verbatim.
    for (final direction in [-32768, -1, 0, 1, 32767]) {
      for (final role in ['self', 'other', 'unknown']) {
        final encoded = const StandardMethodCodec().encodeSuccessEnvelope(
          envelope({...details, 'direction': direction, 'speakerRole': role}),
        );
        final directed = EvenDevicesEvent.fromNative(
            const StandardMethodCodec().decodeEnvelope(encoded));
        expect(directed.direction, direction);
        expect(directed.speakerRole, role);
      }
    }
    expect(
        EvenDevicesEvent.fromNative(envelope({...details, 'direction': null}))
            .direction,
        isNull);
    expect(event.sessionGeneration, 7);
    expect(event.attemptGeneration, 9);
    for (final invalid in [
      {
        'audioPcm': [0, 1]
      },
      {'audioPcm': Uint8List(0)},
      {'audioPcm': Uint8List(1)},
      {'sampleRate': 48000},
      {'channels': 2},
      {'bitsPerSample': 8},
      {'source': 1},
      {'speakerRole': null},
      {'direction': 1.5},
      {'direction': '-1'},
    ]) {
      expect(
          () => EvenDevicesEvent.fromNative(envelope({...details, ...invalid})),
          throwsFormatException);
    }
    expect(
        () => EvenDevicesEvent.fromNative(envelope({})), throwsFormatException);
  });

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

  test(
      'completed transfer preserves its identity and native verification result',
      () {
    const owner = {
      'type': 'ota',
      'sn': 'S200TEST000002',
      'generation': 4,
      'operation': 8,
    };
    final transfer = EvenDevicesEvent.fromNative(const {
      ...owner,
      'phase': 'transportCompleted',
      'progress': 1,
    });
    final failed = EvenDevicesEvent.fromNative(const {
      ...owner,
      'phase': 'failed',
      'progress': 1.0,
      'failure': 'versionMismatch',
    });
    expect(transfer.operation, 8);
    expect(transfer.generation, 4);
    expect(transfer.progress, 1.0);
    expect(transfer.success, isNull);
    expect(transfer.phase, 'transportCompleted');
    expect(failed.failure, 'versionMismatch');
    for (final invalid in [-0.1, double.nan, double.infinity, 1.1, '1']) {
      expect(() => EvenDevicesEvent.fromNative({...owner, 'progress': invalid}),
          throwsFormatException);
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
