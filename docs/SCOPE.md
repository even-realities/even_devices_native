# 支持范围

`even_devices_native` 是 Android Kotlin / iOS Swift G2 SDK 的 Flutter 适配层。两端原生二进制随仓库提供，宿主不依赖父工程或内部 Maven 服务。

当前接口包括：

- 蓝牙权限请求、G2 扫描、双腿连接、断连和 reset。
- 原生解析完整 License JSON，按目标 SN 选择签名证明，通过 8403 企业验签，再完成业务 AUTH；双腿均成功后发布整机 READY。
- 原生时间同步、EvenHub 页面与文字/图片更新、音频/IMU控制、菜单回执、事件及页面心跳。
- G2 双腿固件升级与取消，重连后校验两腿版本，进度和结果通过 OTA 事件上报。
- Demo 的设备详情、独立日志页，以及按 namespace 隔离的上次成功连接记录与手动重连。

Flutter 转换参数和事件。原生 SDK 拥有连接、证明校验、协议编码、应答、分包、超时与取消；连接回调保留适用的 generation 身份信息。

此版本尚未接入 R1、通知、完整业务队列、后台自动恢复和异步 License provider。图片输入要求已转换为固件格式的字节，尚未提供 PNG/BMP 转换或压缩工具。真实眼镜验收范围见[验证记录](VALIDATION.md)。

Even Hub 的显示与交互概念可参考[官方入门文档](https://hub.evenrealities.com/docs/get-started/overview)，本插件 API 见[接入说明](../README.md)。
