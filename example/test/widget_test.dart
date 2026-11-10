import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:even_devices_native/even_devices_native.dart';
import 'package:even_devices_native_example/main.dart';
import 'package:even_devices_native_example/device_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const sn = 'S200LABJ270010';
const otherSn = 'S200LABJ270011';
const secret = 'proof-and-license-contents-must-not-enter-diagnostics';
const rawLicense =
    '{"app_id":"demo","licenses":[{"sn":"$sn","signature":"$secret"}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final historyCalls = <MethodCall>[];
  final historyRecords = <String, String>{};
  Object? historyError;
  String? clipboard;
  Object? scanError;

  setUp(() {
    calls.clear();
    historyCalls.clear();
    historyRecords.clear();
    historyError = null;
    clipboard = null;
    scanError = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel(DeviceHistoryStore.channelName), (call) async {
      historyCalls.add(call);
      if (historyError != null) throw historyError!;
      final args = call.arguments as Map;
      final namespace = args['namespace'] as String;
      switch (call.method) {
        case 'load':
          return historyRecords[namespace];
        case 'save':
          historyRecords[namespace] = args['record'] as String;
        case 'clear':
          historyRecords.remove(namespace);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel(EvenDevicesNative.methodChannelName), (call) async {
      calls.add(call);
      if (call.method == 'requestBluetoothPermissions') return true;
      if (call.method == 'scan' && scanError != null) throw scanError!;
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel(EvenDevicesNative.eventChannelName),
        (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel(DeviceHistoryStore.channelName), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel(EvenDevicesNative.methodChannelName), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel(EvenDevicesNative.eventChannelName), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> event(WidgetTester tester, Map<String, Object?> fields) async {
    await tester.runAsync(() async {
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        EvenDevicesNative.eventChannelName,
        const StandardMethodCodec().encodeSuccessEnvelope(fields),
        (_) => delivered.complete(),
      );
      await delivered.future;
    });
    await tester.pump();
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text(name)));
    await tester.pumpAndSettle();
  }

  Future<void> initialize(WidgetTester tester,
      {String namespace = 'native-demo'}) async {
    await tester.tap(find.byKey(const ValueKey('sdk-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑内容'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('namespace-input')), namespace);
    await tester.enterText(
        find.byKey(const ValueKey('license-input')), rawLicense);
    await tester.tap(find.byKey(const ValueKey('sdk-initialize')));
    await tester.pumpAndSettle();
    expect(find.text('SDK 已初始化'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pumpAndSettle();
  }

  Future<void> discovery(WidgetTester tester, {String target = sn}) =>
      event(tester, {
        'type': 'discovery',
        'namespace': 'native-demo',
        'sn': target,
        'devices': [
          {
            'side': 'left',
            'address': 'AA:BB:CC:DD:EE:01',
            'name': 'Even G2_L_270010'
          },
          {
            'side': 'right',
            'address': 'AA:BB:CC:DD:EE:02',
            'name': 'Even G2_R_270010'
          },
        ],
      });

  Future<void> g2(WidgetTester tester, String phase,
          {String? side,
          String target = sn,
          int generation = 10,
          String? failure,
          String namespace = 'native-demo'}) =>
      event(tester, {
        'type': 'g2',
        'namespace': namespace,
        'sn': target,
        'phase': phase,
        'generation': generation,
        'sessionGeneration': generation,
        if (side != null) 'side': side,
        if (side != null)
          'endpointId':
              side == 'left' ? 'AA:BB:CC:DD:EE:01' : 'AA:BB:CC:DD:EE:02',
        if (side != null) 'attemptGeneration': side == 'left' ? 21 : 22,
        if (failure != null) 'failure': failure,
      });

  Future<void> ready(WidgetTester tester) async {
    await discovery(tester);
    await g2(tester, 'ready', side: 'left');
    await g2(tester, 'ready', side: 'right');
    await g2(tester, 'ready');
  }

  Future<void> hub(WidgetTester tester, String phase,
          {String target = sn,
          int generation = 10,
          String? input,
          int count = 0}) =>
      event(tester, {
        'type': 'evenHub',
        'namespace': 'native-demo',
        'sn': target,
        'phase': phase,
        'generation': generation,
        'sessionGeneration': generation,
        'attemptGeneration': 22,
        'operation': 1,
        'heartbeatCount': count,
        if (input != null) 'event': input,
      });

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NativeSdkExample());
    await tester.pumpAndSettle();
  }

  Future<void> retire(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
      'launch separates four sections and waits for manual initialization',
      (tester) async {
    await launch(tester);
    expect(find.text('发现附近的眼镜'), findsOneWidget);
    expect(find.text('尚未连接'), findsOneWidget);
    expect(find.byKey(const ValueKey('license-input')), findsNothing);
    expect(calls, isEmpty);
    await tab(tester, '设备');
    expect(find.text('尚未选择连接设备'), findsOneWidget);
    expect(find.text('还没有发现眼镜'), findsNothing);
    await tab(tester, 'EvenHub');
    expect(find.text('EvenHub 文字页'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('evenhub-open')))
            .onPressed,
        isNull);
    await tab(tester, '日志');
    expect(find.text('日志看板'), findsOneWidget);
    expect(find.text('示例已启动，等待手动初始化'), findsOneWidget);
    expect(calls, isEmpty);
    await retire(tester);
  });

  testWidgets(
      'raw license forwarding and scan candidates remain separate from connected details',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    final request = calls.singleWhere((call) => call.method == 'initialize');
    expect((request.arguments as Map)['licenseJson'], rawLicense);
    await tester.tap(find.byKey(const ValueKey('scan-start')));
    await tester.pumpAndSettle();
    expect(find.text('扫描请求已提交'), findsOneWidget);
    await discovery(tester);
    expect(find.text('双腿可见'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('connect-$sn')));
    await tester.tap(find.byKey(const ValueKey('connect-$sn')));
    await tester.pumpAndSettle();
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('连接请求已提交'), findsWidgets);
    expect(find.text('双腿可见'), findsNothing);
    await g2(tester, 'enterpriseAuthorizing', side: 'left');
    expect(find.text('企业验签中'), findsWidgets);
    await g2(tester, 'ready', side: 'left');
    expect(find.text('G2 READY'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('sync-time')))
            .onPressed,
        isNull);
    await g2(tester, 'ready', side: 'right');
    expect(find.text('G2 READY'), findsNothing);
    await g2(tester, 'ready');
    expect(find.text('G2 READY'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('sync-time')))
            .onPressed,
        isNotNull);
    await retire(tester);
  });

  testWidgets(
      'unrelated failure, busy rejection and old generation cannot replace current READY',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await ready(tester);
    await g2(tester, 'failed',
        target: otherSn, generation: 11, failure: 'busy');
    await g2(tester, 'failed',
        target: otherSn, generation: 11, failure: 'proofNotFound');
    await g2(tester, 'failed',
        side: 'left', generation: 9, failure: 'connectionFailed');
    await g2(tester, 'failed',
        side: 'left',
        generation: 20,
        namespace: 'old-account',
        failure: 'connectionFailed');
    await event(tester, {
      'type': 'g2',
      'sn': sn,
      'phase': 'failed',
      'generation': 20,
      'failure': 'authorizationTimedOut',
    });
    await event(tester, {
      'type': 'g2',
      'namespace': 'native-demo',
      'sn': sn,
      'phase': 'failed',
      'side': 'left',
      'generation': 10,
      'sessionGeneration': 10,
      'attemptGeneration': 20,
      'failure': 'authorizationTimedOut',
    });
    expect(find.text('G2 READY'), findsOneWidget);
    await tab(tester, '设备');
    expect(find.text('验签超时'), findsNothing);
    await g2(tester, 'failed', side: 'left', failure: 'authorizationTimedOut');
    expect(find.text('G2 READY'), findsNothing);
    await tab(tester, '设备');
    expect(find.text('验签超时'), findsWidgets);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('sync-time')))
            .onPressed,
        isNull);
    await retire(tester);
  });

  testWidgets('only explicit connect changes the target after a pair failure',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await ready(tester);
    await g2(tester, 'failed', side: 'left', failure: 'connectionFailed');
    await g2(tester, 'ready', target: otherSn, generation: 11);
    expect(find.text('G2 READY'), findsNothing);
    expect(find.text(sn), findsWidgets);
    expect(find.text(otherSn), findsNothing);
    await discovery(tester, target: otherSn);
    await tab(tester, '扫描');
    await tester.ensureVisible(find.byKey(const ValueKey('connect-$otherSn')));
    await tester.tap(find.byKey(const ValueKey('connect-$otherSn')));
    await tester.pumpAndSettle();
    expect(find.text(otherSn), findsWidgets);
    expect(
        (calls.singleWhere((call) => call.method == 'connectG2').arguments
            as Map)['sn'],
        otherSn);
    await g2(tester, 'ready', target: otherSn, generation: 12);
    expect(find.text('G2 READY'), findsOneWidget);
    await retire(tester);
  });

  testWidgets(
      'EvenHub waits for native ACKs, displays heartbeat/input and forwards close',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await ready(tester);
    await tab(tester, 'EvenHub');
    await tester.enterText(
        find.byKey(const ValueKey('evenhub-text')), 'Hello native!');
    await tester.ensureVisible(find.byKey(const ValueKey('evenhub-open')));
    await tester.tap(find.byKey(const ValueKey('evenhub-open')));
    await tester.pumpAndSettle();
    expect(
        (calls
            .singleWhere((call) => call.method == 'openEvenHubTextPage')
            .arguments as Map)['text'],
        'Hello native!');
    expect(find.text('页面已创建'), findsNothing);
    await hub(tester, 'opening');
    await hub(tester, 'active');
    await hub(tester, 'heartbeat', count: 2);
    await hub(tester, 'input', count: 2, input: 'click');
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('2 次'), findsOneWidget);
    expect(find.text('单击'), findsOneWidget);
    await hub(tester, 'failed', target: otherSn, count: 8);
    await hub(tester, 'closed', generation: 9);
    expect(find.text('页面运行中'), findsOneWidget);
    await tab(tester, '设备');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('sync-time')))
            .onPressed,
        isNull);
    await tab(tester, 'EvenHub');
    await tester.ensureVisible(find.byKey(const ValueKey('evenhub-close')));
    await tester.tap(find.byKey(const ValueKey('evenhub-close')));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'closeEvenHub'), hasLength(1));
    await hub(tester, 'closed');
    await tester.pump(const Duration(seconds: 20));
    expect(
        calls.where((call) => call.method.toLowerCase().contains('heartbeat')),
        isEmpty);
    await retire(tester);
  });

  testWidgets('missing or zero generation cannot grant READY or a Hub session',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await discovery(tester);
    for (final generation in <int?>[null, 0]) {
      await event(tester, {
        'type': 'g2',
        'namespace': 'native-demo',
        'sn': sn,
        'phase': 'ready',
        if (generation != null) 'generation': generation,
      });
    }
    expect(find.text('G2 READY'), findsNothing);
    await tab(tester, 'EvenHub');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('evenhub-open')))
            .onPressed,
        isNull);
    await ready(tester);
    await event(tester, {
      'type': 'evenHub',
      'namespace': 'native-demo',
      'sn': sn,
      'phase': 'active',
    });
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('evenhub-open')))
            .onPressed,
        isNotNull);
    await g2(tester, 'failed', side: 'left', failure: 'connectionFailed');
    await event(tester, {
      'type': 'g2',
      'namespace': 'native-demo',
      'sn': sn,
      'phase': 'ready',
    });
    expect(find.text('G2 READY'), findsNothing);
    await retire(tester);
  });

  testWidgets('UTF8 limit disables oversized text before a native request',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await ready(tester);
    await tab(tester, 'EvenHub');
    await tester.enterText(find.byKey(const ValueKey('evenhub-text')),
        List.filled(22, '中').join());
    await tester.pump();
    expect(find.text('请输入 1–64 字节文字，中文按 UTF-8 计数'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('evenhub-open')))
            .onPressed,
        isNull);
    expect(
        calls.where((call) => call.method == 'openEvenHubTextPage'), isEmpty);
    await retire(tester);
  });

  testWidgets('EvenHub admission busy releases only the pending submission',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await ready(tester);
    await tab(tester, 'EvenHub');
    await tester.tap(find.byKey(const ValueKey('evenhub-open')));
    await tester.pumpAndSettle();
    await event(tester, {
      'type': 'evenHub',
      'namespace': 'native-demo',
      'sn': sn,
      'generation': 10,
      'phase': 'failed',
      'failure': 'busy',
    });
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('evenhub-open')))
            .onPressed,
        isNotNull);
    await hub(tester, 'active');
    await event(tester, {
      'type': 'evenHub',
      'namespace': 'native-demo',
      'sn': sn,
      'generation': 10,
      'phase': 'failed',
      'failure': 'busy',
    });
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('页面已创建'), findsOneWidget);
    expect(find.text('G2 READY'), findsOneWidget);
    await retire(tester);
  });

  testWidgets(
      'log board pauses display, keeps collecting, filters, copies and excludes private payloads',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await event(tester, {
      'type': 'transport',
      'category': secret,
      'value': {'signature': secret, 'payload': secret}
    });
    await event(tester, {
      'type': 'g2',
      'sn': sn,
      'phase': secret,
      'failure': secret,
      'payload': secret
    });
    await tab(tester, '日志');
    expect(find.textContaining(secret), findsNothing);
    await tester.tap(find.byKey(const ValueKey('log-pause')));
    await tester.pumpAndSettle();
    await discovery(tester);
    expect(find.textContaining('扫描发现 · SN=$sn'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('log-pause')));
    await tester.pumpAndSettle();
    expect(find.textContaining('扫描发现 · SN=$sn'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('log-search')), sn);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('log-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, contains(sn));
    expect(clipboard, isNot(contains(secret)));
    expect(clipboard, isNot(contains('payload')));
    expect(clipboard, isNot(contains('signature')));
    await tester.tap(find.byKey(const ValueKey('log-clear')));
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的日志'), findsOneWidget);
    await retire(tester);
  });

  testWidgets(
      'scan rejection leaves retry available and never logs exception content',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    scanError = PlatformException(
        code: 'scanNotStarted', message: secret, details: rawLicense);
    await tester.tap(find.byKey(const ValueKey('scan-start')));
    await tester.pumpAndSettle();
    expect(find.text('扫描未启动'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('scan-start')))
            .onPressed,
        isNotNull);
    await tab(tester, '日志');
    await tester.tap(find.byKey(const ValueKey('log-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, contains('原生扫描未启动'));
    expect(clipboard, isNot(contains(secret)));
    await retire(tester);
  });

  testWidgets(
      'only whole-pair READY persists history and relaunch reconnects manually',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await discovery(tester);
    expect(historyRecords, isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('connect-$sn')));
    await tester.tap(find.byKey(const ValueKey('connect-$sn')));
    await tester.pumpAndSettle();
    expect(historyRecords, isEmpty);
    await g2(tester, 'ready', side: 'left');
    await g2(tester, 'ready', side: 'right');
    expect(historyRecords, isEmpty);
    await g2(tester, 'failed', failure: 'connectionFailed');
    expect(historyRecords, isEmpty);
    await g2(tester, 'ready', generation: 11, side: 'left');
    await g2(tester, 'ready', generation: 11, side: 'right');
    await g2(tester, 'ready', generation: 11);
    await tester.pumpAndSettle();
    final record = jsonDecode(historyRecords['native-demo']!) as Map;
    expect(record['sn'], sn);
    expect(record['left']['address'], 'AA:BB:CC:DD:EE:01');
    expect(record['right']['address'], 'AA:BB:CC:DD:EE:02');
    expect(historyRecords.values.single, isNot(contains(secret)));
    expect(
        record.keys,
        unorderedEquals([
          'schemaVersion',
          'namespace',
          'sn',
          'connectedAt',
          'left',
          'right'
        ]));

    await retire(tester);
    calls.clear();
    await launch(tester);
    await tab(tester, '设备');
    expect(find.text(sn), findsOneWidget);
    expect(find.text('G2 READY'), findsNothing);
    expect(calls, isEmpty);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('connect-last-device')))
            .onPressed,
        isNull);
    await initialize(tester);
    await tester.tap(find.byKey(const ValueKey('connect-last-device')));
    await tester.pumpAndSettle();
    final connection = calls.singleWhere((call) => call.method == 'connectG2');
    expect((connection.arguments as Map)['sn'], sn);
    expect((connection.arguments as Map)['leftAddress'], 'AA:BB:CC:DD:EE:01');
    expect((connection.arguments as Map)['rightAddress'], 'AA:BB:CC:DD:EE:02');
    expect(calls.where((call) => call.method == 'scan'), isEmpty);
    expect(find.text('G2 READY'), findsNothing);
    await retire(tester);
  });

  testWidgets(
      'history is namespace-scoped and forget leaves the native owner intact',
      (tester) async {
    await launch(tester);
    await initialize(tester);
    await ready(tester);
    await tester.pumpAndSettle();
    expect(historyRecords.keys, ['native-demo']);
    await initialize(tester, namespace: 'another-account');
    await tab(tester, '设备');
    expect(find.text('暂无上次连接记录'), findsOneWidget);
    expect(find.text(sn), findsNothing);
    expect(historyRecords.keys, ['native-demo']);
    await initialize(tester);
    await ready(tester);
    await tester.pumpAndSettle();
    calls.clear();
    await tester
        .ensureVisible(find.byKey(const ValueKey('forget-last-device')));
    await tester.tap(find.byKey(const ValueKey('forget-last-device')));
    await tester.pumpAndSettle();
    expect(historyRecords, isEmpty);
    expect(find.text('G2 READY'), findsOneWidget);
    expect(calls, isEmpty);
    await g2(tester, 'ready');
    await tester.pumpAndSettle();
    expect(historyRecords, isEmpty,
        reason: 'duplicate READY must not undo forget');
    await retire(tester);
  });

  testWidgets(
      'corrupt history and storage failures do not block a valid connection',
      (tester) async {
    historyRecords['native-demo'] = '{corrupt-$secret';
    await launch(tester);
    await initialize(tester);
    await tab(tester, '设备');
    expect(find.text('连接记录不可用，可重新扫描连接。'), findsOneWidget);
    expect(find.textContaining(secret), findsNothing);
    historyError =
        PlatformException(code: 'historyStorageFailed', message: secret);
    await ready(tester);
    await tester.pumpAndSettle();
    expect(find.text('G2 READY'), findsOneWidget);
    expect(find.text('连接记录保存失败，不影响当前连接。'), findsOneWidget);
    await tab(tester, '日志');
    await tester.tap(find.byKey(const ValueKey('log-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, isNot(contains(secret)));
    await retire(tester);
  });

  testWidgets('capture four phone sections for structural visual review',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Load a local system font only for developer screenshots. It is not an
    // application asset or dependency, and Linux CI can still run the test.
    final fontFile = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (fontFile.existsSync()) {
      final loader = FontLoader('sans-serif')
        ..addFont(
            Future.value(ByteData.sublistView(fontFile.readAsBytesSync())));
      await loader.load();
    }
    // Flutter bundles this asset for the example; avoid a developer-specific
    // SDK path so captures use the same Material icons as the installed app.
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await tester.pumpWidget(const NativeSdkExample());
    await tester.pumpAndSettle();
    await initialize(tester);
    await discovery(tester);
    await ready(tester);
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('dashboard-capture')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/visual-review/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    await capture('scan');
    await tab(tester, '设备');
    await capture('device');
    await tab(tester, 'EvenHub');
    await hub(tester, 'active');
    await hub(tester, 'heartbeat', count: 3);
    await capture('evenhub');
    await tab(tester, '日志');
    await capture('logs');
    await retire(tester);
    // The restored card is a manual reconnect affordance, not a live device.
    await launch(tester);
    await tab(tester, '设备');
    await initialize(tester);
    await capture('device-history');
    await retire(tester);
  });
}
