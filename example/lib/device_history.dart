import 'dart:convert';

import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/services.dart';

/// Local UI metadata from a confirmed whole-pair READY, never an authorization
/// cache. Reconnecting still asks the native SDK to validate SN and licenses.
class LastConnectedDevice {
  LastConnectedDevice({
    required this.namespace,
    required this.sn,
    required this.left,
    required this.right,
    required this.connectedAt,
  }) {
    if (namespace.trim().isEmpty ||
        !RegExp(r'^[\x21-\x7e]{14}$').hasMatch(sn) ||
        !_validEndpoint(left) ||
        !_validEndpoint(right) ||
        left.address == right.address) {
      throw const FormatException('Invalid device history');
    }
  }

  final String namespace;
  final String sn;
  final G2Endpoint left;
  final G2Endpoint right;
  final DateTime connectedAt;

  /// Reject corrupt or cross-namespace records without exposing stored input
  /// in diagnostics. Only the allowlisted metadata is ever written back.
  factory LastConnectedDevice.decode(String record, String namespace) {
    final json = jsonDecode(record);
    if (json is! Map<String, dynamic> ||
        json['schemaVersion'] != 1 ||
        json['namespace'] != namespace ||
        json['sn'] is! String ||
        json['connectedAt'] is! String) {
      throw const FormatException('Invalid device history');
    }
    final at = DateTime.tryParse(json['connectedAt'] as String);
    if (at == null) throw const FormatException('Invalid device history');
    return LastConnectedDevice(
      namespace: namespace,
      sn: json['sn'] as String,
      left: _decodeEndpoint(json['left']),
      right: _decodeEndpoint(json['right']),
      connectedAt: at.toUtc(),
    );
  }

  String encode() => jsonEncode({
        'schemaVersion': 1,
        'namespace': namespace,
        'sn': sn,
        'connectedAt': connectedAt.toUtc().toIso8601String(),
        'left': {'address': left.address, 'name': left.name},
        'right': {'address': right.address, 'name': right.name},
      });

  static G2Endpoint _decodeEndpoint(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['address'] is! String ||
        json['name'] is! String) {
      throw const FormatException('Invalid device history');
    }
    return G2Endpoint(
        address: json['address'] as String, name: json['name'] as String);
  }

  // Locators are platform-local MACs/UUIDs; never derive one from an SN. Stored
  // names are display-only and cannot replace native identity checks.
  static bool _validEndpoint(G2Endpoint endpoint) =>
      endpoint.address.trim().isNotEmpty &&
      endpoint.address.length <= 128 &&
      !endpoint.address.contains(RegExp(r'[\x00-\x20\x7f]')) &&
      utf8.encode(endpoint.name).length <= 256;
}

/// Demo-only preference channel; the SDK and Flutter plugin own no UI history.
/// Serial ordering prevents a delayed save from resurrecting a forgotten item.
class DeviceHistoryStore {
  static const channelName = 'even_devices_native_example/history';
  static const _channel = MethodChannel(channelName);
  Future<void> _pending = Future<void>.value();

  Future<LastConnectedDevice?> load(String namespace) => _ordered(() async {
        final record = await _channel
            .invokeMethod<String>('load', {'namespace': namespace});
        return record == null
            ? null
            : LastConnectedDevice.decode(record, namespace);
      });

  Future<void> save(LastConnectedDevice device) => _ordered(() async {
        await _channel.invokeMethod<void>('save', {
          'namespace': device.namespace,
          'record': device.encode(),
        });
      });

  Future<void> clear(String namespace) => _ordered(() async {
        await _channel.invokeMethod<void>('clear', {'namespace': namespace});
      });

  Future<T> _ordered<T>(Future<T> Function() action) {
    final operation = _pending.then((_) => action());
    // A failed preference operation must not poison subsequent loads/clears.
    _pending =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}
