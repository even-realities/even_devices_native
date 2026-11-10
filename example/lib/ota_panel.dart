import 'dart:async';

import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Manual host for one native update. The panel holds the selected document
/// and displays events for the submitted ID across disconnect and reconnect.
class G2OtaPanel extends StatefulWidget {
  const G2OtaPanel(
      {super.key,
      required this.sdk,
      required this.namespace,
      required this.sn,
      required this.ready});
  final EvenDevicesNative sdk;
  final String? namespace;
  final String? sn;
  final bool ready;

  @override
  State<G2OtaPanel> createState() => _G2OtaPanelState();
}

class _G2OtaPanelState extends State<G2OtaPanel> {
  static const _documents =
      MethodChannel('even_devices_native_example/firmware');
  final _version = TextEditingController();
  late final StreamSubscription<EvenDevicesEvent> _subscription;
  Uint8List? _image;
  String? _filename;
  String? _submittedSn;
  int? _operation;
  EvenDevicesEvent? _latest;
  String? _error;
  bool _pending = false;
  bool get _active =>
      _operation != null &&
      !const {'cancelled', 'failed', 'succeeded'}.contains(_latest?.phase);

  @override
  void initState() {
    super.initState();
    _subscription = widget.sdk.events.listen((event) {
      if (!mounted ||
          event.type != 'ota' ||
          event.namespace != widget.namespace ||
          _submittedSn == null ||
          event.sn != _submittedSn ||
          (event.operation ?? 0) <= 0) {
        return;
      }
      // The SDK can emit its first event before its method result. Once an ID
      // is available, only that operation may update this display.
      if (_operation != null && event.operation != _operation) return;
      setState(() => _latest = event);
    }, onError: (Object _) {
      if (mounted) setState(() => _error = '原生事件流异常');
    });
  }

  /// Canceling the system picker leaves the prior selection intact.
  Future<void> _pick() async {
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      final file = await _documents.invokeMapMethod<String, Object?>('pick');
      if (!mounted || file == null) return;
      final name = file['name'], data = file['bytes'];
      if (name is! String || data is! Uint8List || data.isEmpty) {
        throw const FormatException('Invalid firmware selection');
      }
      setState(() {
        _filename = name;
        _image = data;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is PlatformException && e.code == 'invalidFirmwareFile'
                ? '请选择 32 MiB 以内的非空 .bin 文件。'
                : '无法读取所选文件。');
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _start() async {
    setState(() {
      _submittedSn = widget.sn;
      _pending = true;
      _error = null;
      _latest = null;
      _operation = null;
    });
    try {
      final id = await widget.sdk
          .startOta(firmware: _image!, targetVersion: _version.text.trim());
      if (mounted) {
        setState(() {
          _operation = id;
          if (_latest?.operation != id) _latest = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submittedSn = null;
          _latest = null;
          _error = otaFailureName(e is PlatformException ? e.code : null);
        });
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.sdk.cancelOta(operationId: _operation!);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = otaFailureName(e is PlatformException ? e.code : null));
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _version.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _latest?.progress;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('G2 固件升级', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      Text('升级设备：${_active ? _submittedSn : widget.sn ?? '尚未连接'}'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
          onPressed: _pending || _active ? null : _pick,
          icon: const Icon(Icons.folder_open),
          label: const Text('选择固件 .bin')),
      if (_filename != null) Text('$_filename（${_image!.length} 字节）'),
      const SizedBox(height: 12),
      TextField(
          key: const ValueKey('ota-version'),
          controller: _version,
          enabled: !_pending && !_active,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: '目标固件版本', hintText: '例如 2.4.1.4')),
      const SizedBox(height: 14),
      FilledButton(
          onPressed: widget.ready &&
                  widget.sn != null &&
                  _image != null &&
                  _version.text.trim().isNotEmpty &&
                  !_pending &&
                  !_active
              ? _start
              : null,
          child: const Text('开始升级')),
      OutlinedButton(
          onPressed: _active && !_pending ? _cancel : null,
          child: const Text('取消升级')),
      if (_operation != null) Text('操作 ID：$_operation · SN：$_submittedSn'),
      if (_latest != null) Text(otaPhaseName(_latest!.phase)),
      if (progress != null) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        Text('传输进度 ${(progress * 100).floor()}%'),
      ],
      if (_latest?.leftVersion != null) Text('左腿回读版本：${_latest!.leftVersion}'),
      if (_latest?.rightVersion != null)
        Text('右腿回读版本：${_latest!.rightVersion}'),
      if (_latest?.failure != null) Text(otaFailureName(_latest!.failure)),
      if (_error != null)
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]);
  }
}

/// Unknown firmware phases and failure strings are never interpolated into logs.
String otaPhaseName(String? phase) =>
    const {
      'started': '升级已开始',
      'transferring': '正在传输固件',
      'recovering': '连接中断，正在恢复当前组件',
      'transportCompleted': '传输完成，等待重连验版',
      'verifying': '正在核对双腿固件版本',
      'succeeded': '双腿目标版本已确认',
      'failed': '升级失败',
      'cancelled': '升级已取消',
    }[phase] ??
    '等待原生升级状态';

String otaFailureName(String? code) {
  // Rejections include a firmware status byte. Only the numeric field is
  // admitted here; raw platform exceptions can include host-supplied input.
  final rejected = RegExp(
          r'^(?:deviceRejected_|(?:firmware|notify)Rejected:)(-?[0-9]{1,3})$')
      .firstMatch(code ?? '');
  if (rejected != null) return '设备拒绝升级（状态码 ${rejected.group(1)}）';
  return const {
        'notReady': '左右腿尚未就绪',
        'busy': '原生会话忙',
        'invalidTargetVersion': '目标版本格式错误或与固件不一致',
        'invalidFirmware': '固件包无效',
        'versionMismatch': '设备版本与目标不匹配',
        'versionUnverified': '未能确认双腿版本',
        'versionReadFailed': '设备版本读取失败',
        'disconnected': '设备已断开连接',
        'timedOut': '等待设备响应超时',
        'responseTimeout': '等待设备响应超时',
        'otaResponseTimeout': '等待设备响应超时',
        'rawTimeout': '传输窗口响应超时',
        'writeTimeout': '写入超时',
        'notifyTimeout': '等待升级结果超时',
        'otaNotifyTimeout': '等待升级结果超时',
        'bindFailed': '升级通道绑定失败',
        'parkFailed': '端点交接失败',
        'retirementFailed': '升级会话释放失败',
        'recoveryFailed': '升级恢复失败',
        'otaRecoveryTimeout': '等待升级恢复超时',
        'recoveryTimeout': '等待升级恢复超时',
        'otaDiscoveryTimeout': '发现升级服务超时',
        'otaServiceMissing': '缺少升级服务',
        'otaCharacteristicMissing': '缺少升级特征',
        'otaNotifyFailed': '订阅升级通知失败',
        'otaPacketTooLarge': '升级报文超过连接上限',
        'malformedResponse': '升级响应格式异常',
        'reauthorizationFailed': '升级重连验签失败',
        'writeFailed': '固件写入失败',
      }[code] ??
      '原生升级操作失败';
}
