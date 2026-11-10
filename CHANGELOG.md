## Dependency integration

- Resolve native beta.14 through Maven Central on Android and an exact SwiftPM package on iOS.
- Require Flutter 3.32+, add the iOS Swift package adapter and privacy resource, and migrate both example hosts off CocoaPods.
- Preserve native archives for provenance checks; remove local Maven repository injection and the plugin podspec.

## 0.1.0-beta.14（本地构建）

- Android 原生 SDK 按 iOS 的两阶段业务 AUTH 应答处理 G2 连接。

## 0.1.0-beta.13（本地构建，未发布）

- Android/iOS 在原生侧接收 G2 STREAM 通知并解码 LC3，输出 16 kHz 单声道 PCM16 little-endian；Dart 只接收 typed binary，不参与音频解码。
- `evenHub` / `audioEvent` 提供只读 `audioPcm`、格式、`source`、`speakerRole` 与可空有符号 `direction`；分类采用 App 的方向判定，缺失方向保持 unknown。
- Demo 的 EvenHub 页可手动开启/停止麦克风，低频显示累计帧数和 PCM 字节数；不保存音频，不逐帧记录内容。
- 两个平台捆绑 google/liblc3，并保留许可。本地 Flutter、CocoaPods 与 SwiftPM 接入均使用 beta.13。AAR 内附原生组件清单，对应源码和构建入口见 [PROVENANCE.md](PROVENANCE.md)。
- 真机音频、方向分类及关闭后的停止行为仍待正式固件验收。

## 0.1.0-beta.12（本地构建）

- Kotlin 和 Swift SDK 提供 G2 双腿 OTA。Flutter 通过 `startOta`、`cancelOta` 和 `ota` 事件调用原生升级会话。
- 安装成功需在重连后读取左右腿版本并匹配调用方提供的目标版本。真机验收进度见[验证记录](docs/VALIDATION.md)。

## 0.1.0-beta.11

- 两端内置 beta.11 原生 SDK：EvenHub 指令、心跳、交互事件及时间同步均由原生处理。
- 原生 TimeSync magic 使用 1–255，保持完整应答关联与连接代次校验；修复后真机验收待完成。
- Demo 提供扫描、设备详情、EvenHub 和日志四个页面，保存并手动重连上次成功连接的设备。
- 新增独立仓库安装地址、包内协议与验证文档，以及 Even Hub 官方文档入口。

## 0.1.0-beta.5

- 新增独立 Flutter 薄插件，直接链接 Android/iOS beta.5 纯原生 SDK。
- 原样提交完整多 SN License JSON，校验和目标 SN 选择均由原生完成。
- 接入 G2 扫描、企业验签、双腿业务 AUTH、时间同步、断连和 reset。
- 提供手动示例、事件身份字段、产物校验和宿主构建验证；真实设备验收待执行。
