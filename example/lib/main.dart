import 'dart:async';
import 'dart:convert';

import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_history.dart';
import 'ota_panel.dart';

void main() => runApp(const NativeSdkExample());

/// A manual host: tabs only observe one SDK owner and never initiate BLE work.
class NativeSdkExample extends StatelessWidget {
  const NativeSdkExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Even G2 Native SDK',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'sans-serif',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245849)),
          scaffoldBackgroundColor: const Color(0xfff4f6f5),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xfff4f6f5),
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        home: const _Dashboard(),
      );
}

enum _MicrophoneState { off, starting, on, stopping, stopFailed }

class _Dashboard extends StatefulWidget {
  const _Dashboard();

  @override
  State<_Dashboard> createState() => _DashboardState();
}

/// This is a display projection of native events, not a connection state machine.
/// The SDK owns authorization, retries, page leases, and all hardware timers.
class _DashboardState extends State<_Dashboard> {
  final _sdk = EvenDevicesNative.instance;
  final _history = DeviceHistoryStore();
  final _namespace = TextEditingController(text: 'native-demo');
  final _license = TextEditingController(
    text: const String.fromEnvironment('EVEN_ENTERPRISE_LICENSE_JSON'),
  );
  final _hubText = TextEditingController(
    text: 'Hello EvenHub!\nNative SDK demo\nTap the glasses',
  );
  final _search = TextEditingController();
  final _found = <String, _Candidate>{};
  final _logs = <_LogEntry>[];
  StreamSubscription<EvenDevicesEvent>? _subscription;
  _PairView? _pair;
  _PairView? _requestPreviousPair;
  LastConnectedDevice? _lastDevice;
  // Preference completions from a previous account cannot replace this view.
  String _historyNamespace = 'native-demo';
  int _historyRevision = 0;
  bool _historyBusy = false;
  String? _historyFailure;
  List<_LogEntry>? _pausedLogs;
  int _tab = 0;
  bool _initialized = false;
  bool _busy = false;
  bool _scanRequested = false;
  bool _connectionRequested = false;
  bool _hubRequested = false;
  String? _activeNamespace;
  // A new SDK owner invalidates pending picker results and OTA projections.
  Object _otaOwner = Object();
  String? _scanFailure;
  String? _notice;
  String _hubPhase = 'idle';
  String? _hubFailure;
  String? _hubInput;
  int _heartbeatCount = 0;
  // Keep only the latest frame prefix in memory. Never send it to logs or storage.
  final _audioPreview = Uint8List(32);
  int _previewLength = 0;
  int _latestFrameBytes = 0;
  _MicrophoneState _microphone = _MicrophoneState.off;
  int _audioFrames = 0;
  int _audioBytes = 0;
  Timer? _audioRefresh;

  String _logCategory = '全部';
  String _logLevel = '全部';

  // Readiness requires a native identity fence, never an unscoped phase label.
  bool get _ready => (_pair?.ready ?? false) && (_pair?.generation ?? 0) > 0;
  bool get _hasConnection => _ready || _connectionRequested;
  bool get _hubLive =>
      _hubRequested ||
      const {'opening', 'active', 'heartbeat', 'input', 'closing'}
          .contains(_hubPhase);

  @override
  void initState() {
    super.initState();
    // Subscribe before initialization so immediate native rejections are visible.
    _subscription = _sdk.events.listen(_onEvent, onError: (Object error) {
      if (mounted) {
        setState(() => _record('错误', '错误', '事件流异常：${_errorCode(error)}'));
      }
    });
    _record('操作', '信息', '示例已启动，等待手动初始化');
    unawaited(_loadHistory(_namespace.text));
  }

  /// Only recognized scalar metadata enters the log. Raw native maps, business
  /// bytes, license text, exception messages, and signatures are never copied.
  void _onEvent(EvenDevicesEvent event) {
    if (!mounted) return;
    // PCM never enters the diagnostic log or a per-frame widget rebuild.
    if (event.type == 'evenHub' && event.event == 'audioEvent') {
      if (event.namespace == _activeNamespace &&
          event.sn == _pair?.sn &&
          event.generation == _pair?.generation &&
          _ready &&
          (_microphone == _MicrophoneState.on ||
              _microphone == _MicrophoneState.starting) &&
          event.audioPcm != null) {
        final pcm = event.audioPcm!;
        _latestFrameBytes = pcm.length;
        _previewLength = pcm.length.clamp(0, _audioPreview.length);
        _audioPreview.setRange(0, _previewLength, pcm);
        _audioFrames++;
        _audioBytes += pcm.length;
        _audioRefresh ??= Timer(const Duration(milliseconds: 500), () {
          _audioRefresh = null;
          if (mounted) setState(() {});
        });
      }
      return;
    }
    setState(() {
      // Another account's events cannot publish a device or a page into this
      // dashboard. The native owner supplies namespace on initialized events.
      final currentNamespace =
          _activeNamespace != null && event.namespace == _activeNamespace;
      if (currentNamespace && event.type == 'discovery' && event.sn != null) {
        final candidate = _found.putIfAbsent(event.sn!, _Candidate.new);
        for (final endpoint in event.devices) {
          candidate.endpoints[endpoint.side] = endpoint;
        }
        candidate.lastSeen = DateTime.now();
      } else if (currentNamespace && event.type == 'g2') {
        _applyConnectionEvent(event);
      } else if (currentNamespace &&
          event.type == 'evenHub' &&
          event.sn == _pair?.sn &&
          (event.generation ?? 0) > 0 &&
          event.generation == _pair?.generation &&
          _ready) {
        // Native owns operation/session fencing. Busy is admission rejection,
        // and therefore cannot invalidate an already active page projection.
        if (event.failure != 'busy') {
          _hubPhase = event.phase ?? _hubPhase;
          if (const {'opening', 'closing', 'closed', 'failed'}
              .contains(event.phase)) {
            _resetAudioProjection();
          }
          _hubFailure = event.failure;
          _hubRequested = false;
          final count = event.heartbeatCount;
          if (count != null) _heartbeatCount = count;
          final input = event.event;
          if (input != null && _inputNames.containsKey(input)) {
            _hubInput = _inputNames[input];
          }
        } else {
          // Admission rejection completes a local submission; it does not
          // replace an already active page or strand the controls as pending.
          _hubRequested = false;
        }
      } else if (currentNamespace && event.type == 'transport') {
        // Discovery is not scan admission. Treat these explicit native failures
        // as diagnostics rather than inferring a live scanner from candidates.
        final category = event.details['category'];
        if (category == 'BLUETOOTH_OFF' ||
            category == 'BLUETOOTH_UNAVAILABLE') {
          _scanFailure = '蓝牙不可用';
          _scanRequested = false;
        }
      }
      final category = switch (event.type) {
        'discovery' => '扫描',
        'g2' || 'timeSync' => '连接',
        'evenHub' => 'EvenHub',
        'ota' => 'OTA',
        'transport' || 'business' => '传输',
        _ => '其他',
      };
      _record(
          category, event.failure == null ? '信息' : '错误', _eventSummary(event));
    });
  }

  /// Whole-pair READY alone enables commands. Endpoint readiness remains a
  /// per-leg detail, and a failed unrelated/busy request retains the old owner.
  void _applyConnectionEvent(EvenDevicesEvent event) {
    if (event.phase == 'discovered') return;
    // Missing/zero generation remains a log diagnostic and cannot authorize
    // buttons, even if an older visible pair already has a positive fence.
    if (event.phase == 'ready' && (event.generation ?? 0) <= 0) return;
    if (event.failure == 'busy') {
      // Async native admission can reject after the method was acknowledged.
      // Release only our local request placeholder, preserving the old owner.
      if (_pair?.phase == 'requesting' && _pair?.sn == event.sn) {
        _pair = _requestPreviousPair;
        _connectionRequested = false;
      }
      return;
    }
    if (event.sn == null || event.sn!.isEmpty) {
      if (event.failure != null) {
        _notice = _failureName(event.failure);
        if (event.failure == 'bluetoothUnavailable') {
          _scanFailure = _notice;
          _scanRequested = false;
        }
      }
      return;
    }
    final existing = _pair;
    // Only an explicit connect submission changes the selected target. Even
    // after failure, an unsolicited callback cannot select another device.
    if (existing != null && existing.sn != event.sn) {
      return;
    }
    if (existing != null &&
        existing.sn == event.sn &&
        existing.generation != null &&
        event.generation != null &&
        event.generation! < existing.generation!) {
      return;
    }
    final replacementGeneration = existing?.generation != null &&
        event.generation != null &&
        event.generation! > existing!.generation!;
    if (replacementGeneration) {
      _hubRequested = false;
      _hubPhase = 'idle';
      _resetAudioProjection();
    }
    final pair = existing?.sn == event.sn && !replacementGeneration
        ? existing!
        : (_pair = _PairView(event.sn!, _found[event.sn]?.endpoints ?? {}));
    if (event.side == 'left' || event.side == 'right') {
      final leg = pair.legs[event.side]!;
      if (leg.session != null &&
          event.sessionGeneration != null &&
          event.sessionGeneration! < leg.session!) {
        return;
      }
      if (leg.attempt != null &&
          event.attemptGeneration != null &&
          event.attemptGeneration! < leg.attempt!) {
        return;
      }
      leg.phase = event.phase ?? leg.phase;
      leg.endpointId = event.endpointId ?? leg.endpointId;
      leg.session = event.sessionGeneration ?? leg.session;
      leg.attempt = event.attemptGeneration ?? leg.attempt;
      leg.failure = event.failure;
    }
    // No pair display field may change until endpoint freshness is checked.
    // An old attempt can carry a valid pair generation but stale diagnostics.
    pair.generation = event.generation ?? pair.generation;
    pair.failure = event.failure;
    if (event.phase == 'ready' && event.side == null) {
      pair.ready = true;
      pair.phase = 'ready';
      _connectionRequested = false;
      // Scanning, method admission and a single leg's READY never save history.
      // Deduplicate this native owner, including after the user forgets it.
      if (!pair.historyRecorded) {
        pair.historyRecorded = true;
        _rememberDevice(pair);
      }
    } else if (const {'failed', 'disconnected', 'connecting', 'retrying'}
        .contains(event.phase)) {
      pair.ready = false;
      pair.phase = event.phase!;
      if (event.phase == 'failed' || event.phase == 'disconnected') {
        _connectionRequested = false;
        // A local display revocation never sends page work after a lost link.
        _hubRequested = false;
        _hubPhase = 'closed';
        _resetAudioProjection();
      }
    } else if (!pair.ready && event.phase != null) {
      pair.phase = event.phase!;
    }
  }

  /// Serializes button submissions only; a returned Future is not a device ACK.
  Future<bool> _run(String label, Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return false;
      setState(() => _record('操作', '信息', '$label：请求已提交'));
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = '$label：${_errorCode(error)}';
          _record('错误', '错误', _notice!);
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _initialize() async {
    final namespace = _namespace.text;
    if (!await _sdk.requestBluetoothPermissions()) {
      throw PlatformException(code: 'permissionDenied');
    }
    await _sdk.initialize(
      namespace: namespace,
      licenseJson: _license.text,
    );
    if (!mounted) return;
    _initialized = true;
    _otaOwner = Object();
    _activeNamespace = namespace;
    _pair = null;
    _found.clear();
    _scanRequested = false;
    _connectionRequested = false;
    _hubRequested = false;
    _hubPhase = 'idle';
    _resetAudioProjection();
    _heartbeatCount = 0;
    _notice = null;
    await _loadHistory(namespace);
  }

  /// Restores metadata only. Neither loading preferences nor changing tabs
  /// initializes Bluetooth, publishes READY, or automatically connects.
  Future<void> _loadHistory(String namespace) async {
    final revision = ++_historyRevision;
    setState(() {
      _historyNamespace = namespace;
      _lastDevice = null;
      _historyFailure = null;
      _historyBusy = true;
    });
    try {
      final device = await _history.load(namespace);
      if (!mounted || revision != _historyRevision) return;
      setState(() => _lastDevice = device);
    } catch (_) {
      if (!mounted || revision != _historyRevision) return;
      setState(() {
        _historyFailure = '连接记录不可用，可重新扫描连接。';
        _record('操作', '错误', '读取上次连接记录失败');
      });
    } finally {
      if (mounted && revision == _historyRevision) {
        setState(() => _historyBusy = false);
      }
    }
  }

  /// Called inside the native event projection. Keep only this ready pair's
  /// actual endpoint locators; signatures, payloads and page text are excluded.
  void _rememberDevice(_PairView pair) {
    final namespace = _activeNamespace;
    if (namespace == null) return;
    try {
      G2Endpoint endpoint(String side) {
        final leg = pair.legs[side]!;
        return G2Endpoint(
          address: leg.endpointId ?? leg.endpoint?.address ?? '',
          name: leg.endpoint?.name ?? '',
        );
      }

      final device = LastConnectedDevice(
        namespace: namespace,
        sn: pair.sn,
        left: endpoint('left'),
        right: endpoint('right'),
        connectedAt: DateTime.now().toUtc(),
      );
      unawaited(_saveHistory(device));
    } on FormatException {
      _historyFailure = '缺少有效双腿端点，本次连接未保存。';
      _record('操作', '错误', '上次连接记录缺少有效端点');
    }
  }

  Future<void> _saveHistory(LastConnectedDevice device) async {
    final revision = ++_historyRevision;
    _historyNamespace = device.namespace;
    _historyBusy = true;
    _historyFailure = null;
    try {
      await _history.save(device);
      if (!mounted || revision != _historyRevision) return;
      setState(() {
        _lastDevice = device;
        _record('操作', '信息', '已保存上次成功连接设备');
      });
    } catch (_) {
      if (!mounted || revision != _historyRevision) return;
      setState(() {
        _historyFailure = '连接记录保存失败，不影响当前连接。';
        _record('操作', '错误', '保存上次连接记录失败');
      });
    } finally {
      if (mounted && revision == _historyRevision) {
        setState(() => _historyBusy = false);
      }
    }
  }

  /// Forgetting affects only Demo preferences, not the active native owner or
  /// its licenses. Serialize with saves so an older write cannot restore it.
  Future<void> _forgetDevice() async {
    if (_historyBusy || _lastDevice == null) return;
    final namespace = _historyNamespace;
    final revision = ++_historyRevision;
    setState(() => _historyBusy = true);
    try {
      await _history.clear(namespace);
      if (!mounted || revision != _historyRevision) return;
      setState(() {
        _lastDevice = null;
        _historyFailure = null;
        _record('操作', '信息', '已清除上次连接记录');
      });
    } catch (_) {
      if (!mounted || revision != _historyRevision) return;
      setState(() => _historyFailure = '连接记录清除失败，请重试。');
    } finally {
      if (mounted && revision == _historyRevision) {
        setState(() => _historyBusy = false);
      }
    }
  }

  /// Prefer fresh locators for the same SN; otherwise submit the saved pair to
  /// the existing native connect path, which still checks proof and identity.
  Future<void> _connectLastDevice() async {
    final device = _lastDevice;
    if (device == null ||
        !_initialized ||
        _busy ||
        _hasConnection ||
        _activeNamespace != device.namespace) {
      return;
    }
    final found = _found[device.sn];
    final candidate = found?.endpoints.length == 2
        ? found!
        : (_Candidate()
          ..endpoints.addAll({'left': device.left, 'right': device.right}));
    await _connect(device.sn, candidate);
  }

  Future<void> _scan() async {
    final accepted = await _run('开始扫描', _sdk.scan);
    if (!mounted) return;
    setState(() {
      _scanRequested = accepted;
      _scanFailure = accepted ? null : '扫描未启动，请检查蓝牙与权限';
    });
  }

  Future<void> _connect(String sn, _Candidate candidate) async {
    final previous = _pair;
    setState(() {
      _requestPreviousPair = previous;
      _pair = _PairView(sn, candidate.endpoints);
      _connectionRequested = true;
      _tab = 1;
      _notice = null;
    });
    final accepted = await _run(
        '连接眼镜',
        () => _sdk.connectG2(
              sn: sn,
              left: candidate.endpoints['left'],
              right: candidate.endpoints['right'],
            ));
    if (!mounted || accepted) return;
    setState(() {
      // Restore only the local request placeholder. Never overwrite an actual
      // native event that arrived while the method result was still pending.
      if (_pair?.sn == sn && _pair?.phase == 'requesting') {
        _pair = previous;
        _connectionRequested = false;
      }
    });
  }

  Future<void> _reset() async {
    await _sdk.reset();
    if (!mounted) return;
    _initialized = false;
    _otaOwner = Object();
    _activeNamespace = null;
    _pair = null;
    _found.clear();
    _scanRequested = false;
    _connectionRequested = false;
    _hubRequested = false;
    _hubPhase = 'idle';
    _resetAudioProjection();
    _heartbeatCount = 0;
    _hubInput = null;
    _hubFailure = null;
    _notice = null;
  }

  void _record(String category, String level, String message) {
    _logs.insert(0, _LogEntry(DateTime.now(), category, level, message));
    if (_logs.length > 500) _logs.removeLast();
  }

  /// Codes are mapped to fixed labels: PlatformException.message/details can
  /// include host input, so even diagnostic failures never interpolate them.
  String _errorCode(Object error) => error is PlatformException
      ? _failureName(error.code)
      : '未知错误（${error is FormatException ? '数据格式' : '操作异常'}）';

  String _eventSummary(EvenDevicesEvent event) => [
        _eventTypes[event.type] ?? '未知原生事件',
        if (event.sn != null && RegExp(r'^[A-Z0-9]{14}$').hasMatch(event.sn!))
          'SN=${event.sn}',
        if (event.side == 'left' || event.side == 'right')
          event.side == 'left' ? '左腿' : '右腿',
        if (event.phase != null)
          event.type == 'ota'
              ? otaPhaseName(event.phase)
              : _phaseName(event.phase),
        if (event.failure != null)
          event.type == 'ota'
              ? otaFailureName(event.failure)
              : _failureName(event.failure),
        if (event.type == 'timeSync') event.success == true ? '成功' : '失败',
        if (event.type == 'evenHub' &&
            _inputNames.containsKey(event.details['event']))
          _inputNames[event.details['event']]!,
        if (event.generation != null) 'generation=${event.generation}',
        if (event.sessionGeneration != null)
          'session=${event.sessionGeneration}',
        if (event.attemptGeneration != null)
          'attempt=${event.attemptGeneration}',
        if (event.operation != null) 'operation=${event.operation}',
      ].join(' · ');

  @override
  void dispose() {
    // Tab changes retain the owner; only this host's teardown retires it.
    _audioRefresh?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_sdk.reset().catchError((Object _) {}));
    _namespace.dispose();
    _license.dispose();
    _hubText.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        key: const ValueKey('dashboard-capture'),
        child: Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Even G2', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Native SDK · 连接调试台',
                    style: TextStyle(fontSize: 12, color: Color(0xff63736c))),
              ],
            ),
            actions: [
              IconButton(
                key: const ValueKey('sdk-settings'),
                tooltip: 'SDK 设置',
                onPressed: _busy ? null : _settings,
                icon: const Icon(Icons.tune),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _statusCard(),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              // Keep the OTA form and event subscription while switching tabs.
              child: IndexedStack(index: _tab == 4 ? 1 : 0, children: [
                switch (_tab) {
                  0 => _scanPage(),
                  1 => _devicePage(),
                  2 => _evenHubPage(),
                  3 => _logsPage(),
                  _ => const SizedBox.shrink(),
                },
                G2OtaPanel(
                    key: ObjectKey(_otaOwner),
                    sdk: _sdk,
                    namespace: _activeNamespace,
                    sn: _pair?.sn,
                    ready: _ready && !_busy && !_hubLive),
              ]),
            ),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.radar), label: '扫描'),
              NavigationDestination(
                  icon: Icon(Icons.bluetooth_connected), label: '设备'),
              NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined), label: 'EvenHub'),
              NavigationDestination(
                  icon: Icon(Icons.terminal_outlined), label: '日志'),
              NavigationDestination(
                  icon: Icon(Icons.system_update_alt), label: 'OTA'),
            ],
          ),
        ),
      );

  Widget _statusCard() => _Card(
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: _ready ? const Color(0xffe1f2e9) : const Color(0xffedf0ee),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bluetooth,
                color: _ready ? const Color(0xff245849) : Colors.blueGrey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_ready ? 'G2 READY' : _phaseName(_pair?.phase),
                  key: const ValueKey('pair-status'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(_pair?.sn ?? '选择一台眼镜开始连接',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xff63736c))),
            ]),
          ),
          _Pill(_initialized ? '已初始化' : '未初始化', positive: _initialized),
        ]),
      );

  Widget _scanPage() => _page([
        _section('发现附近的眼镜', '扫描结果只代表设备可见，连接状态请到「设备」查看。'),
        if (!_initialized)
          _Hint(
            icon: Icons.key_outlined,
            text: '先在 SDK 设置中填入完整 License 并初始化。',
            action: TextButton(onPressed: _settings, child: const Text('打开设置')),
          ),
        _Card(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_scanRequested ? Icons.radar : Icons.bluetooth_searching,
                  size: 20, color: const Color(0xff245849)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_scanRequested ? '扫描请求已提交' : '扫描未启动',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${_found.length} 台'),
            ]),
            const SizedBox(height: 8),
            const Text('保留本次打开示例后收到的发现记录。',
                style: TextStyle(fontSize: 12, color: Color(0xff63736c))),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                key: const ValueKey('scan-start'),
                onPressed:
                    !_initialized || _busy || _scanRequested ? null : _scan,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('开始扫描'),
              ),
              OutlinedButton(
                onPressed: !_initialized || _busy || !_scanRequested
                    ? null
                    : () async {
                        if (await _run('停止扫描', _sdk.stopScan) && mounted) {
                          setState(() => _scanRequested = false);
                        }
                      },
                child: const Text('停止扫描'),
              ),
            ]),
          ]),
        ),
        if (_scanFailure != null)
          _Hint(icon: Icons.warning_amber, text: _scanFailure!, error: true),
        if (_found.isEmpty)
          const _Empty(
            icon: Icons.radar,
            title: '还没有发现眼镜',
            detail: '打开眼镜并靠近手机，然后点击开始扫描。',
          ),
        for (final entry in _found.entries)
          _candidateCard(entry.key, entry.value),
      ]);

  Widget _candidateCard(String sn, _Candidate candidate) => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.visibility_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(sn,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            _Pill(candidate.endpoints.length == 2 ? '双腿可见' : '等待另一腿',
                positive: candidate.endpoints.length == 2),
          ]),
          const SizedBox(height: 12),
          for (final side in const ['left', 'right'])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(side == 'left' ? '左腿  ' : '右腿  ',
                    style: const TextStyle(color: Color(0xff63736c))),
                Expanded(
                  child: Text(candidate.endpoints[side]?.address ?? '尚未发现',
                      style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ),
          if (candidate.lastSeen != null)
            Text('最近发现 ${_time(candidate.lastSeen!)}',
                style: const TextStyle(fontSize: 11, color: Color(0xff63736c))),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              key: ValueKey('connect-$sn'),
              onPressed: !_initialized ||
                      _busy ||
                      _hasConnection ||
                      candidate.endpoints.length != 2
                  ? null
                  : () => _connect(sn, candidate),
              child: const Text('连接并查看详情'),
            ),
          ),
        ]),
      );

  Widget _devicePage() => _page([
        _section('连接设备', '查看整机状态、左右腿授权阶段与端点详情。'),
        if (_pair == null) _historyCard(),
        if (_pair == null)
          _Empty(
            icon: Icons.bluetooth_connected,
            title: '尚未选择连接设备',
            detail: '在扫描页找到完整左右腿后提交连接请求。',
            action: TextButton(
                onPressed: () => setState(() => _tab = 0),
                child: const Text('前往扫描')),
          )
        else ...[
          _Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _detail('设备 SN', _pair!.sn),
              _detail('整机阶段', _phaseName(_pair!.phase)),
              _detail('整机代次', '${_pair!.generation ?? '未提供'}'),
              _detail('账号空间', _activeNamespace ?? '未初始化'),
              const Divider(height: 24),
              Text(_ready
                  ? '左右腿已完成原生企业验签与业务 AUTH。'
                  : '等待原生整机 READY。单腿连接成功不会启用业务操作。'),
              if (_pair!.failure != null) ...[
                const SizedBox(height: 10),
                Text(_failureName(_pair!.failure),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('sync-time'),
                  onPressed: !_initialized || !_ready || _busy || _hubLive
                      ? null
                      : () => _run('时间同步', _sdk.syncG2Time),
                  icon: const Icon(Icons.schedule, size: 18),
                  label: const Text('时间同步'),
                ),
                OutlinedButton(
                  onPressed: !_initialized || _busy
                      ? null
                      : () => _run('断开连接', () async {
                            await _sdk.disconnectG2();
                            if (!mounted) return;
                            _pair?.ready = false;
                            _pair?.phase = 'disconnectRequested';
                            _connectionRequested = false;
                            _hubRequested = false;
                            _hubPhase = 'closed';
                            _resetAudioProjection();
                          }),
                  child: const Text('断开连接'),
                ),
              ]),
            ]),
          ),
          _historyCard(),
          _legCard('left', _pair!.legs['left']!),
          _legCard('right', _pair!.legs['right']!),
        ],
        if (_notice != null)
          _Hint(icon: Icons.info_outline, text: _notice!, error: true),
      ]);

  Widget _historyCard() {
    final device = _lastDevice;
    final at = device?.connectedAt.toLocal();
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, size: 20),
          const SizedBox(width: 8),
          const Text('上次连接',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_historyBusy)
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator()),
        ]),
        const SizedBox(height: 12),
        if (device == null)
          Text(_historyBusy ? '正在读取连接记录…' : '暂无上次连接记录')
        else ...[
          SelectableText(device.sn,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('成功连接于 ${at!.year}/${at.month.toString().padLeft(2, '0')}/'
              '${at.day.toString().padLeft(2, '0')} ${_time(at)}'),
          const SizedBox(height: 6),
          Text(_initialized
              ? '重连时由原生 SDK 重新匹配 License 并验签。'
              : '请先初始化 SDK，再连接此设备。'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              key: const ValueKey('connect-last-device'),
              onPressed: !_initialized ||
                      _busy ||
                      _historyBusy ||
                      _hasConnection ||
                      _activeNamespace != device.namespace
                  ? null
                  : _connectLastDevice,
              icon: const Icon(Icons.bluetooth_connected, size: 18),
              label: const Text('连接上次设备'),
            ),
            TextButton(
              key: const ValueKey('forget-last-device'),
              onPressed: _historyBusy ? null : _forgetDevice,
              child: const Text('清除记录'),
            ),
          ]),
        ],
        if (_historyFailure != null) ...[
          const SizedBox(height: 8),
          Text(_historyFailure!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
    );
  }

  Widget _legCard(String side, _LegView leg) => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(side == 'left' ? 'L · 左腿' : 'R · 右腿',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            _Pill(_phaseName(leg.phase), positive: leg.phase == 'ready'),
          ]),
          const SizedBox(height: 12),
          _detail(
              '设备名称',
              leg.endpoint?.name.isNotEmpty == true
                  ? leg.endpoint!.name
                  : '原生未提供'),
          _detail('端点地址', leg.endpointId ?? leg.endpoint?.address ?? '未提供'),
          _detail('Session', '${leg.session ?? '未提供'}'),
          _detail('Attempt', '${leg.attempt ?? '未提供'}'),
          if (leg.failure != null) _detail('失败原因', _failureName(leg.failure)),
        ]),
      );

  Widget _evenHubPage() {
    final bytes = utf8.encode(_hubText.text).length;
    final valid = bytes > 0 && bytes <= 64;
    return _page([
      _section('EvenHub 文字页', '把一段文字显示到眼镜，触摸眼镜可在此查看事件。'),
      if (!_ready)
        const _Hint(icon: Icons.link, text: '先连接眼镜并等待整机 READY，才能发送文字页。'),
      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('待发送预览 · 576 × 288',
              style: TextStyle(fontSize: 12, color: Color(0xff63736c))),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xff111c17),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.topLeft,
              child: Text(_hubText.text,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                      color: Color(0xffb4edbd), fontSize: 16, height: 1.6)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('evenhub-text'),
            controller: _hubText,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '眼镜显示文字',
              helperText: '$bytes / 64 UTF-8 字节',
              errorText: valid ? null : '请输入 1–64 字节文字，中文按 UTF-8 计数',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              key: const ValueKey('evenhub-open'),
              onPressed: !_ready || _busy || _hubLive || !valid
                  ? null
                  : () async {
                      setState(() {
                        _hubRequested = true;
                        _hubFailure = null;
                        _heartbeatCount = 0;
                        _hubInput = null;
                      });
                      final accepted = await _run('打开 EvenHub',
                          () => _sdk.openEvenHubTextPage(text: _hubText.text));
                      if (!accepted && mounted) {
                        setState(() => _hubRequested = false);
                      }
                    },
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('显示到眼镜'),
            ),
            OutlinedButton(
              key: const ValueKey('evenhub-close'),
              onPressed: !_ready || _busy || !_hubLive
                  ? null
                  : () => _run('关闭 EvenHub', _sdk.closeEvenHub),
              child: const Text('关闭页面'),
            ),
          ]),
        ]),
      ),
      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _detail('页面状态', _hubRequested ? '请求已提交，等待原生结果' : _hubPhaseName),
          _detail('心跳确认', '$_heartbeatCount 次'),
          _detail('最近交互', _hubInput ?? '尚未收到触摸事件'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              key: const ValueKey('evenhub-microphone-start'),
              onPressed: !_ready ||
                      _busy ||
                      !const {'active', 'heartbeat', 'input'}
                          .contains(_hubPhase) ||
                      _microphone != _MicrophoneState.off
                  ? null
                  : () => _setMicrophone(true),
              icon: const Icon(Icons.mic, size: 18),
              label: const Text('开启麦克风'),
            ),
            OutlinedButton(
              key: const ValueKey('evenhub-microphone-stop'),
              onPressed: !_ready ||
                      _busy ||
                      (_microphone != _MicrophoneState.on &&
                          _microphone != _MicrophoneState.stopFailed)
                  ? null
                  : () => _setMicrophone(false),
              child: const Text('停止麦克风'),
            ),
          ]),
          _detail(
              '眼镜麦克风',
              switch (_microphone) {
                _MicrophoneState.off => '未开启',
                _MicrophoneState.starting => '正在开启',
                _MicrophoneState.on => _audioFrames == 0 ? '已开启，等待音频' : '正在接收',
                _MicrophoneState.stopping => '正在停止',
                _MicrophoneState.stopFailed => '停止未确认，请重试',
              }),
          _detail('收到音频', '$_audioFrames 帧 · $_audioBytes PCM 字节'),
          const Text('16 kHz · 单声道 · PCM16LE', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          Text(_previewLength == 0
              ? 'PCM 字节预览（十六进制）'
              : '最近一帧 · $_latestFrameBytes 字节 · 显示前 $_previewLength 字节'),
          const SizedBox(height: 6),
          Text(
            _previewLength == 0
                ? '暂无音频字节'
                : [
                    for (int i = 0; i < _previewLength; i++)
                      _audioPreview[i]
                          .toRadixString(16)
                          .padLeft(2, '0')
                          .toUpperCase(),
                  ].join(' '),
            key: const ValueKey('evenhub-audio-hex'),
            style: const TextStyle(fontFamily: 'monospace', height: 1.5),
          ),
          if (_hubFailure != null) _detail('失败原因', _failureName(_hubFailure)),
          const SizedBox(height: 8),
          const Text('创建成功后由原生 SDK 每 5 秒维护页面心跳；退出或断连后停止。',
              style: TextStyle(fontSize: 12, color: Color(0xff63736c))),
        ]),
      ),
    ]);
  }

  /// Resets only the host projection after its native owner is retired.
  void _resetAudioProjection() {
    _audioRefresh?.cancel();
    _audioRefresh = null;
    _microphone = _MicrophoneState.off;
    _audioPreview.fillRange(0, _audioPreview.length, 0);
    _previewLength = 0;
    _latestFrameBytes = 0;
    _audioFrames = 0;
    _audioBytes = 0;
  }

  /// A native audio event can arrive before its method result. Arm preview
  /// before enable and revoke it immediately on stop, even if stop needs retry.
  Future<void> _setMicrophone(bool enabled) async {
    final pending =
        enabled ? _MicrophoneState.starting : _MicrophoneState.stopping;
    setState(() {
      _resetAudioProjection();
      _microphone = pending;
    });
    final accepted = await _run(enabled ? '开启麦克风' : '停止麦克风', () async {
      await _sdk.executeEvenHubCommand(EvenHubCommand.audioControl,
          parameters: {'enabled': enabled});
    });
    // Teardown clears the pending state. A late ACK cannot revive old audio.
    if (!mounted || _microphone != pending) return;
    setState(() {
      if (enabled && accepted) {
        _microphone = _MicrophoneState.on;
      } else {
        _resetAudioProjection();
        if (!enabled && !accepted) _microphone = _MicrophoneState.stopFailed;
      }
    });
  }

  String get _hubPhaseName =>
      const {
        'idle': '未打开',
        'opening': '正在创建',
        'active': '页面已创建',
        'heartbeat': '页面运行中',
        'input': '页面运行中',
        'closing': '正在关闭',
        'closed': '已关闭',
        'failed': '页面失败',
      }[_hubPhase] ??
      '等待原生状态';

  List<_LogEntry> get _visibleLogs => (_pausedLogs ?? _logs).where((entry) {
        final query = _search.text.toLowerCase();
        return (_logCategory == '全部' || entry.category == _logCategory) &&
            (_logLevel == '全部' || entry.level == _logLevel) &&
            (query.isEmpty || entry.formatted.toLowerCase().contains(query));
      }).toList();

  Widget _logsPage() {
    final visible = _visibleLogs;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: _section(
            '日志看板',
            _pausedLogs == null
                ? '实时收集 · 最近 ${_logs.length} / 500 条'
                : '已暂停显示 · 后台继续收集 ${_logs.length} 条'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          key: const ValueKey('log-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              hintText: '搜索 SN、阶段或错误', prefixIcon: Icon(Icons.search)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const ValueKey('log-category'),
              value: _logCategory,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '分类'),
              items: const [
                '全部',
                '连接',
                '扫描',
                'EvenHub',
                'OTA',
                '操作',
                '传输',
                '错误',
                '其他'
              ]
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => _logCategory = value!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const ValueKey('log-level'),
              value: _logLevel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '级别'),
              items: const ['全部', '信息', '错误']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => _logLevel = value!),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(spacing: 0, children: [
          TextButton.icon(
            key: const ValueKey('log-pause'),
            onPressed: () => setState(() {
              _pausedLogs = _pausedLogs == null ? List.of(_logs) : null;
            }),
            icon: Icon(_pausedLogs == null ? Icons.pause : Icons.play_arrow,
                size: 18),
            label: Text(_pausedLogs == null ? '暂停显示' : '恢复显示'),
          ),
          TextButton.icon(
            key: const ValueKey('log-copy'),
            onPressed: visible.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(
                        text: visible
                            .map((entry) => entry.formatted)
                            .join('\n')));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('已复制 ${visible.length} 条筛选日志')));
                    }
                  },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('复制当前'),
          ),
          TextButton.icon(
            key: const ValueKey('log-clear'),
            onPressed: () => setState(() {
              _logs.clear();
              if (_pausedLogs != null) _pausedLogs = [];
            }),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清空'),
          ),
        ]),
      ),
      Expanded(
        child: visible.isEmpty
            ? const _Empty(
                icon: Icons.terminal_outlined,
                title: '没有符合条件的日志',
                detail: '调整筛选条件，或等待下一条原生事件。',
              )
            : ListView.separated(
                key: const PageStorageKey('log-list'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, index) {
                  final entry = visible[index];
                  return _Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${_time(entry.at)}  ${entry.category} · ${entry.level}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: entry.level == '错误'
                                      ? Theme.of(context).colorScheme.error
                                      : const Color(0xff63736c))),
                          const SizedBox(height: 5),
                          SelectableText(entry.message,
                              style:
                                  const TextStyle(fontSize: 12, height: 1.5)),
                        ]),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _settings() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _Settings(
          namespace: _namespace,
          license: _license,
          initialized: _initialized,
          initialize: () => _run('初始化', _initialize),
          update: () =>
              _run('更新 License', () => _sdk.updateLicenses(_license.text)),
          reset: () => _run('Reset', _reset),
        ),
      );

  Widget _page(List<Widget> children) => ListView(
        key: PageStorageKey('page-$_tab'),
        padding: const EdgeInsets.all(16),
        children: children,
      );

  Widget _section(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: Color(0xff63736c))),
        ]),
      );

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 78,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xff63736c)))),
          Expanded(
              child:
                  SelectableText(value, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

/// Settings keeps credentials off the dashboard and out of the diagnostic log.
/// An in-flight submission disables editing, so its raw JSON cannot change mid-call.
class _Settings extends StatefulWidget {
  const _Settings({
    required this.namespace,
    required this.license,
    required this.initialized,
    required this.initialize,
    required this.update,
    required this.reset,
  });
  final TextEditingController namespace;
  final TextEditingController license;
  final bool initialized;
  final Future<bool> Function() initialize;
  final Future<bool> Function() update;
  final Future<bool> Function() reset;

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool _saving = false;
  bool _showLicense = false;
  late bool _active = widget.initialized;
  String? _result;

  Future<void> _submit(Future<bool> Function() operation, String success,
      {bool? initialized}) async {
    setState(() => _saving = true);
    final accepted = await operation();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _result = accepted ? success : '操作失败，请查看日志中的错误码';
      if (accepted && initialized != null) _active = initialized;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('SDK 设置',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: '关闭设置',
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('namespace-input'),
                controller: widget.namespace,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: '账号命名空间'),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(child: Text('完整 License JSON')),
                TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _showLicense = !_showLicense),
                    child: Text(_showLicense ? '隐藏内容' : '编辑内容')),
              ]),
              if (_showLicense)
                TextField(
                  key: const ValueKey('license-input'),
                  controller: widget.license,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                      hintText: '粘贴签名平台导出的完整 JSON，不要只复制单个签名'),
                )
              else
                Text(widget.license.text.isEmpty ? '尚未填写' : '已填入完整 JSON（内容已隐藏）',
                    style: const TextStyle(
                        color: Color(0xff63736c), fontSize: 12)),
              const SizedBox(height: 16),
              const Text('完整证明集合交给 Kotlin / Swift SDK 校验与按 SN 匹配。',
                  style: TextStyle(fontSize: 12, height: 1.5)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(
                  key: const ValueKey('sdk-initialize'),
                  onPressed: _saving
                      ? null
                      : () => _submit(widget.initialize, 'SDK 已初始化',
                          initialized: true),
                  child: const Text('初始化'),
                ),
                OutlinedButton(
                  onPressed: _saving || !_active
                      ? null
                      : () => _submit(widget.update, 'License 已更新'),
                  child: const Text('更新 License'),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () =>
                          _submit(widget.reset, 'SDK 已重置', initialized: false),
                  child: const Text('Reset'),
                ),
              ]),
              if (_saving) const LinearProgressIndicator(),
              if (_result != null) ...[
                const SizedBox(height: 12),
                Text(_result!, key: const ValueKey('settings-result')),
              ],
            ],
          ),
        ),
      );
}

/// Presentation snapshots retain reported endpoint generations without inventing
/// values that Android or another transport has not supplied.
class _PairView {
  _PairView(this.sn, Map<String, G2Endpoint> endpoints)
      : legs = {
          'left': _LegView(endpoints['left']),
          'right': _LegView(endpoints['right']),
        };
  final String sn;
  final Map<String, _LegView> legs;
  String phase = 'requesting';
  String? failure;
  int? generation;
  bool ready = false;
  // A duplicate READY from this owner must not rewrite an explicitly cleared
  // record. A new pair generation creates a new presentation snapshot.
  bool historyRecorded = false;
}

class _LegView {
  _LegView(this.endpoint);
  final G2Endpoint? endpoint;
  String phase = 'unknown';
  String? endpointId;
  String? failure;
  int? session;
  int? attempt;
}

class _Candidate {
  final endpoints = <String, G2Endpoint>{};
  DateTime? lastSeen;
}

class _LogEntry {
  const _LogEntry(this.at, this.category, this.level, this.message);
  final DateTime at;
  final String category;
  final String level;
  final String message;
  String get formatted => '${_time(at)} [$category/$level] $message';
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? margin;
  @override
  Widget build(BuildContext context) => Container(
        margin: margin ?? const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xffe5eae7)),
        ),
        child: child,
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.positive = false});
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: positive ? const Color(0xffe5f2e9) : const Color(0xffeef1ef),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: positive
                    ? const Color(0xff245849)
                    : const Color(0xff63736c))),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(
      {required this.icon,
      required this.text,
      this.action,
      this.error = false});
  final IconData icon;
  final String text;
  final Widget? action;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 18,
              color: error
                  ? Theme.of(context).colorScheme.error
                  : const Color(0xff63736c)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: error
                          ? Theme.of(context).colorScheme.error
                          : const Color(0xff63736c)))),
          if (action != null) action!,
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(
      {required this.icon,
      required this.title,
      required this.detail,
      this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: const Color(0xff9baaa1)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, height: 1.6, color: Color(0xff63736c))),
          if (action != null) action!,
        ]),
      );
}

String _time(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:'
    '${at.second.toString().padLeft(2, '0')}.${at.millisecond.toString().padLeft(3, '0')}';

String _phaseName(String? phase) =>
    const {
      'requesting': '连接请求已提交',
      'unknown': '等待原生状态',
      'discovered': '已发现',
      'waitingForForeground': '等待前台',
      'connecting': '正在连接',
      'enterpriseAuthorizing': '企业验签中',
      'businessAuthenticating': '业务 AUTH 中',
      'retrying': '正在重试',
      'ready': '已就绪',
      'disconnected': '已断开',
      'disconnectRequested': '断开请求已提交',
      'failed': '连接失败',
      'opening': '正在创建',
      'active': '页面已创建',
      'heartbeat': '心跳已确认',
      'input': '交互事件',
      'closing': '正在关闭',
      'closed': '页面已关闭',
    }[phase] ??
    (phase == null ? '尚未连接' : '未知原生阶段');

String _failureName(String? code) =>
    const {
      'busy': '原生会话忙',
      'notReady': '整机尚未就绪',
      'notConnected': '尚未连接',
      'notInitialized': 'SDK 尚未初始化',
      'permissionDenied': '缺少蓝牙权限',
      'scanNotStarted': '原生扫描未启动',
      'bluetoothUnavailable': '蓝牙不可用',
      'deviceNotSeen': '未发现目标设备',
      'proofNotFound': '未匹配到目标 SN 的证明',
      'invalidLicense': 'License 校验失败',
      'invalidArguments': '参数不合法',
      'sdkInUse': 'SDK 已被其他宿主占用',
      'nativeSdkError': '原生 SDK 拒绝操作',
      'nativeError': '原生 SDK 拒绝操作',
      'connectionFailed': '物理连接失败',
      'authenticationFailed': '原生授权失败',
      'enterpriseServiceMissing': '未发现企业服务 8450',
      'characteristicMissing': '缺少企业服务特征',
      'mtuTooSmall': '链路 MTU 不足',
      'authorizationNotificationFailed': '验签通知订阅失败',
      'authorizationWriteFailed': '证明发送失败',
      'authorizationMalformedResult': '验签结果格式异常',
      'authorizationSerialMismatch': '证明 SN 不匹配',
      'authorizationSignatureRejected': '签名被拒绝',
      'authorizationDeviceError': '设备验签错误',
      'authorizationConnectionState': '验签连接状态异常',
      'authorizationTimedOut': '验签超时',
      'businessNotificationFailed': '业务通知订阅失败',
      'businessWriteFailed': '业务写入失败',
      'businessAuthorizationViolation': '业务授权异常',
      'businessAuthTimedOut': '业务 AUTH 超时',
      'timeSyncFailed': '时间同步失败',
      'invalidText': '文字须为 1–64 UTF-8 字节',
      'timedOut': '设备响应超时',
      'transportRejected': '设备传输被拒绝',
      'deviceRejected': '设备业务请求被拒绝',
      'writeFailed': '业务写入失败',
      'disconnected': '连接已断开',
      'malformedResponse': '设备响应格式异常',
      'heartbeatFailed': '页面心跳失败',
    }[code] ??
    '未知错误码';

const _eventTypes = {
  'discovery': '扫描发现',
  'g2': '连接状态',
  'evenHub': 'EvenHub',
  'timeSync': '时间同步',
  'ota': '固件升级',
  'transport': '原生传输事件',
  'business': '业务入站事件',
};

const _inputNames = {
  'click': '单击',
  'doubleClick': '双击',
  'scrollUp': '向上滑动',
  'scrollDown': '向下滑动',
  'longPress': '长按',
  'longPressRelease': '长按释放',
  'foregroundEnter': '进入前台',
  'foregroundExit': '退出前台',
  'abnormalExit': '异常退出',
  'exit': '页面退出',
};
