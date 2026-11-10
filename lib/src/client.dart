import 'package:flutter/services.dart';

import 'models.dart';

/// One Flutter facade for the native SDK owner in this engine.
///
/// Kotlin/Swift validates the raw license export, selects the target SN,
/// encodes 8403 and owns both connection attempts. Listen to [events] before
/// initialize/scan/connect to observe early failures. Lifecycle methods only
/// acknowledge submission; the native whole-device READY event grants use.
/// [executeEvenHubCommand] separately awaits its native command result.
class EvenDevicesNative {
  EvenDevicesNative({
    MethodChannel methodChannel = const MethodChannel(methodChannelName),
    EventChannel eventChannel = const EventChannel(eventChannelName),
  })  : _methods = methodChannel,
        _events = eventChannel;

  static const methodChannelName = 'even_devices_native/methods';
  static const eventChannelName = 'even_devices_native/events';

  /// Share one client so listeners use one native EventChannel subscription.
  static final instance = EvenDevicesNative();

  final MethodChannel _methods;
  final EventChannel _events;

  /// Mapping retains broadcast cancellation: the last listener releases the
  /// native sink without disconnecting the native SDK session.
  late final Stream<EvenDevicesEvent> events =
      _events.receiveBroadcastStream().map(EvenDevicesEvent.fromNative);

  /// Native validates the complete bundle before replacing an existing owner.
  /// Invalid JSON is deliberately not parsed or repaired by Flutter.
  Future<void> initialize({
    required String namespace,
    required String licenseJson,
  }) =>
      _methods.invokeMethod<void>('initialize', <String, Object?>{
        'namespace': namespace,
        'licenseJson': licenseJson,
      });

  /// Native validation failures propagate as PlatformException. A replacement
  /// affects subsequent authorization attempts, not an already captured proof.
  Future<void> updateLicenses(String licenseJson) =>
      _methods.invokeMethod<void>('updateLicenses', <String, Object?>{
        'licenseJson': licenseJson,
      });

  /// Android requests runtime permissions from its attached Activity. iOS uses
  /// CoreBluetooth's system prompt at initialize; this is not an OS grant.
  Future<bool> requestBluetoothPermissions() async =>
      await _methods.invokeMethod<bool>('requestBluetoothPermissions') ?? false;

  Future<void> scan() => _methods.invokeMethod<void>('scan');
  Future<void> stopScan() => _methods.invokeMethod<void>('stopScan');

  /// Android requires both scanned endpoints. iOS accepts both bound UUIDs or
  /// neither, using its own scan cache. Native validates identities and refuses
  /// an unlicensed target before submitting its new GATT connection.
  Future<void> connectG2({
    required String sn,
    G2Endpoint? left,
    G2Endpoint? right,
  }) =>
      _methods.invokeMethod<void>('connectG2', <String, Object?>{
        'sn': sn,
        'leftAddress': left?.address,
        'leftName': left?.name,
        'rightAddress': right?.address,
        'rightName': right?.name,
      });

  Future<void> disconnectG2() => _methods.invokeMethod<void>('disconnectG2');

  /// Native admits TimeSync only for its current whole-device READY owner.
  /// Completion/failure arrives separately as a timeSync event.
  Future<void> syncG2Time() => _methods.invokeMethod<void>('syncG2Time');

  /// Opens a native-owned EvenHub text page after whole-device READY.
  ///
  /// Native validates the nonempty, at most 64-byte UTF-8 text, waits for the
  /// glasses' CREATE response, then owns heartbeat renewal and input events.
  /// Completion acknowledges submission; observe `evenHub` events for results.
  Future<void> openEvenHubTextPage({required String text}) =>
      _methods.invokeMethod<void>('openEvenHubTextPage', <String, Object?>{
        'text': text,
      });

  /// Native stops renewing the captured page and confirms its shutdown result.
  /// This remains valid while CREATE or a heartbeat is awaiting its response.
  Future<void> closeEvenHub() => _methods.invokeMethod<void>('closeEvenHub');

  /// Executes a logical command using the native page owner and command queue.
  ///
  /// Pass page/container fields or whole firmware-format image bytes; never
  /// construct protobuf, fragments, IDs or heartbeat counters in Flutter.
  /// Native validates against `native/protocol/evenhub_commands.json` and owns
  /// response matching, cancellation and the page lease. Reply-only commands
  /// complete after native transport acceptance, without implying a device ACK.
  Future<Map<String, Object?>> executeEvenHubCommand(
    EvenHubCommand command, {
    Map<String, Object?> parameters = const {},
  }) async {
    final result = await _methods.invokeMapMethod<String, Object?>(
      'executeEvenHubCommand',
      <String, Object?>{
        'command': command.name,
        'parameters': parameters,
      },
    );
    // A missing native result is a bridge violation, not a successful command.
    if (result == null) {
      throw const FormatException('Missing native EvenHub command result');
    }
    return Map.unmodifiable(result);
  }

  /// Native retires pending callbacks, connections and credentials together.
  Future<void> reset() => _methods.invokeMethod<void>('reset');
}
