# flutter_enterprise_sdk

[English](README.md) | 简体中文

一个用于在 Android 和 iOS 上连接**企业指定 Even G2 眼镜**的 Flutter 插件。蓝牙连接、按设备序列号（SN）匹配 License，以及设备验签均由 Kotlin / Swift 原生 SDK 完成。

## 插件内容

- 设备扫描、左右腿连接状态、企业验签和时间同步。
- Even Hub 页面、文字、图片、音频、IMU、菜单及交互指令；原生 SDK 负责协议编码、应答和页面心跳。
- 内置 Android AAR、iOS XCFramework，附带扫描、设备、Even Hub 和日志分开展示的示例。

当前支持 G2，详见[能力与范围](docs/SCOPE.md)。

## 安装

在 App 的 `pubspec.yaml` 中添加依赖，然后执行 `flutter pub get`：

```yaml
dependencies:
  even_devices_native:
    git:
      url: https://github.com/even-realities/flutter_enterprise_sdk.git
      ref: main
```

正式项目建议将 `main` 替换为审核后的 commit，保证构建可复现。

要求：Android 5.0+（API 21）、iOS 15+，以及已启用企业服务的眼镜固件。仓库使用 Flutter 3.32.0；构建要求与蓝牙权限见[平台配置](docs/INTEGRATION.zh-CN.md#平台要求)。iOS 宿主须在 `Info.plist` 中添加 `NSBluetoothAlwaysUsageDescription`。

## 如何使用

### 1. 初始化并扫描

准备签名平台导出的 License JSON，其中包含 App ID 和已授权的眼镜 SN。在 App 中声明资源：

```yaml
flutter:
  assets:
    - assets/even_license.json
```

先监听事件，再初始化：

```dart
import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/services.dart';

final sdk = EvenDevicesNative.instance;
final subscription = sdk.events.listen((event) {
  // 将 discovery 事件中的 event.sn 和 event.devices 展示在扫描列表中。
  if (event.type == 'g2' &&
      event.phase == 'ready' &&
      event.side == null &&
      (event.generation ?? 0) > 0) {
    // 左右腿均已授权，可在 UI 中启用设备操作。
  }
  // 通过 timeSync 和 evenHub 事件观察指令结果及交互。
});

if (!await sdk.requestBluetoothPermissions()) {
  throw StateError('Bluetooth permission denied');
}
await sdk.initialize(
  namespace: 'my-enterprise-app',
  licenseJson: await rootBundle.loadString('assets/even_license.json'),
);
await sdk.scan();
```

### 2. 连接选中的眼镜

从扫描事件中收集同一 SN 的左右腿，两个端点可能分别到达。使用原始地址和名称提交连接：

```dart
Future<void> connectSelectedGlasses({
  required String sn,
  required G2Endpoint left,
  required G2Endpoint right,
}) async {
  await sdk.stopScan();
  await sdk.connectG2(sn: sn, left: left, right: right);
}
```

原生 SDK 按目标 SN 匹配 License JSON，未匹配时在连接前拒绝。保留导出的 `app_id` 原值；App 中仅保存签名证明，签名平台账号和私钥应保存在 App 之外。

### 3. 显示 Even Hub 页面

收到原生整机 `ready` 事件后，显示一个短文字页面：

```dart
await sdk.openEvenHubTextPage(text: 'Hello Even Hub');
// evenHub / active 表示眼镜确认创建页面；原生 SDK 自动续期心跳。
// 通过 evenHub / input 事件接收交互。

// 用户结束使用时：
await sdk.closeEvenHub();
await sdk.disconnectG2();
await sdk.reset();
await subscription.cancel();
```

连接和短文字页接口完成时表示请求已提交，实际结果通过 `sdk.events` 返回。其它页面及设备交互使用 `executeEvenHubCommand`，参数见[指令契约](docs/evenhub_commands.json)和[接入参考](docs/INTEGRATION.zh-CN.md)。

## 纯原生 SDK

iOS 原生 App 可通过 Swift Package Manager 添加本仓库，选择 **EvenDevicesSDK** 和精确版本 `0.1.0-beta.12`，接入 G2 固件升级。Android 尚未发布到 Maven Central。详见[原生接入指南](docs/NATIVE_SDK.md)。

## 运行示例

连接手机后，在仓库根目录执行：

```bash
fvm flutter pub get
cd example
fvm flutter run
```

打开设置，粘贴 License JSON 并初始化；扫描并选择眼镜后，在设备、Even Hub 和日志页进行操作。示例会记录上次成功连接的眼镜，供手动重连。详见[示例说明](example/README.md)。

## 官方文档

接下来阅读 **[Even Hub 官方文档：Get Started / Overview](https://hub.evenrealities.com/docs/get-started/overview)**，了解 Even Hub、显示与交互设计，以及应用开发流程。Flutter 连接 API 的用法以本仓库示例和接入参考为准。

[验证状态](docs/VALIDATION.md) · [原生产物来源](PROVENANCE.md) · [Apache 2.0 许可证](LICENSE) · [第三方许可](THIRD_PARTY_NOTICES.md)
