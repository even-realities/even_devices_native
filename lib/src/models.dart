import 'package:flutter/foundation.dart';

/// Logical commands supported by both native SDKs. Names are channel methods,
/// never firmware command IDs; native alone validates and encodes the payload.
enum EvenHubCommand {
  createPage,
  updateImage,
  updateText,
  rebuildPage,
  shutdownPage,
  heartbeat,
  audioControl,
  menuStartupFailed,
  imuControl,
  menuSubitemResponse,
}

/// A physical endpoint locator, never an authorization credential.
@immutable
class G2Endpoint {
  const G2Endpoint({required this.address, this.name = ''});
  final String address;
  final String name;
}

/// A discovery observation. iOS emits incremental sides; Android can include
/// both sides in one event. Discovery does not imply authorization or READY.
@immutable
class G2DiscoveredEndpoint extends G2Endpoint {
  const G2DiscoveredEndpoint({
    required super.address,
    required this.side,
    super.name,
  });
  final String side;

  /// Unknown sides cannot silently become a known endpoint in the host UI.
  factory G2DiscoveredEndpoint.fromNative(Object? value) {
    if (value is! Map ||
        value['address'] is! String ||
        (value['address'] as String).isEmpty ||
        (value['side'] != 'left' && value['side'] != 'right') ||
        (value['name'] != null && value['name'] is! String)) {
      throw const FormatException('Invalid native G2 discovery endpoint');
    }
    return G2DiscoveredEndpoint(
      address: value['address'] as String,
      name: value['name'] as String? ?? '',
      side: value['side'] as String,
    );
  }
}

/// A channel envelope, not a connection state machine. Kotlin/Swift owns
/// callback fencing; this model checks channel types and preserves identity.
@immutable
class EvenDevicesEvent {
  const EvenDevicesEvent._({
    required this.type,
    required this.details,
    this.namespace,
    this.sn,
    this.side,
    this.endpointId,
    this.generation,
    this.sessionGeneration,
    this.attemptGeneration,
    this.phase,
    this.failure,
    this.success,
    this.operation,
    this.event,
    this.heartbeatCount,
    this.devices = const [],
  });

  final String type;
  final String? namespace;
  final String? sn;
  final String? side;
  final String? endpointId;

  /// Android pair generation; missing endpoint generations remain null.
  final int? generation;
  final int? sessionGeneration;
  final int? attemptGeneration;
  final String? phase;
  final String? failure;
  final bool? success;
  final int? operation;

  /// Native-decoded EvenHub input, never inferred from a raw transport payload.
  final String? event;

  /// Number of page-lease acknowledgements confirmed by the native owner.
  final int? heartbeatCount;
  final List<G2DiscoveredEndpoint> devices;

  /// Preserve unknown categories/phases for forward compatibility.
  final Map<String, Object?> details;

  factory EvenDevicesEvent.fromNative(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value['type'] is! String ||
        (value['type'] as String).isEmpty) {
      throw const FormatException('Invalid native SDK event');
    }
    final fields = Map<String, Object?>.from(value);
    String? string(String key) {
      final field = fields[key];
      if (field != null && field is! String) {
        throw const FormatException('Invalid native SDK event string');
      }
      return field as String?;
    }

    int? integer(String key) {
      final field = fields[key];
      if (field != null && (field is! int || field < 0)) {
        throw const FormatException('Invalid native SDK event generation');
      }
      return field as int?;
    }

    final success = fields['success'];
    final devices = fields['devices'];
    if ((success != null && success is! bool) ||
        (devices != null && devices is! List)) {
      throw const FormatException('Invalid native SDK event values');
    }
    return EvenDevicesEvent._(
      type: fields['type']! as String,
      namespace: string('namespace'),
      sn: string('sn'),
      side: string('side'),
      endpointId: string('endpointId'),
      generation: integer('generation'),
      sessionGeneration: integer('sessionGeneration'),
      attemptGeneration: integer('attemptGeneration'),
      phase: string('phase'),
      failure: string('failure'),
      success: success as bool?,
      operation: integer('operation'),
      event: string('event'),
      heartbeatCount: integer('heartbeatCount'),
      devices: List.unmodifiable(
        (devices as List? ?? const []).map(G2DiscoveredEndpoint.fromNative),
      ),
      details: Map.unmodifiable(fields),
    );
  }
}
