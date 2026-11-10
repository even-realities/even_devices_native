# Android Maven Central 与 iOS SPM 发布

SDK 使用 Apache 2.0 许可。iOS SPM 和 Flutter 插件分别发布，各自使用对应版本的二进制。

| 平台 | 分发入口 | 当前状态 |
| --- | --- | --- |
| Android | `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14` | beta.14 已发布到 Maven Central；公司命名空间已验证 |
| iOS | 本仓库根目录 `Package.swift`，product 为 `EvenDevicesSDK` | SPM 二进制入口；使用同名版本 tag |

## Android：第一次发布前

### 1. 注册公司可管理的账号

打开 [Central Portal](https://central.sonatype.com/)，注册并登录。
公司应保留账号恢复、后续发布和团队管理权限。
GitHub 仓库公开不会自动获得 `com.evenrealities` 的发布权限。

### 2. 验证公司命名空间

在账号菜单打开 **View Namespaces → Add Namespace**，申请
`com.evenrealities`。这个前缀覆盖计划使用的 `com.evenrealities.devices`。

复制 Portal 分配的 **Verification Key**，由公司 DNS 管理员添加：

| DNS 字段 | 内容 |
| --- | --- |
| 域名 | `evenrealities.com` |
| 主机记录 | 根域名 `@`，以 DNS 服务商的写法为准 |
| 类型 | `TXT` |
| 记录值 | Portal 实际显示的 Verification Key，不能自行编造 |

验证记录已公开解析后，再回到 Portal 点击 **Verify Namespace**：

```bash
dig +short TXT evenrealities.com
```

等待状态变成 **Verified**。具体域名与流程以
[Sonatype 命名空间指引](https://central.sonatype.org/register/namespace/)为准。

### 3. 创建 Portal 发布 Token

在 [Portal Account](https://central.sonatype.com/account) 中选择
**Generate User Token**，保存生成的 username/password 对。
它们是发布 Token，区别于网页登录密码。

发布时通过本机环境或 CI 密钥注入：

```text
CENTRAL_TOKEN_USERNAME=<Portal Token username>
CENTRAL_TOKEN_PASSWORD=<Portal Token password>
```

不需要把凭据发到聊天中，也不要写入仓库。上传脚本运行时读取环境变量，
不会把 Token 放入命令行参数或打印到日志。

### 4. 准备 GPG 发行签名密钥

使用公司的发行签名密钥。首次创建时可执行：

```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format LONG
```

在交互流程中填写公司的发行身份、有效期和密码，记录完整指纹。
通过 GPG agent 解锁后，打包脚本使用该指纹签名。
备份私钥并由公司保管；不要放到 Git 或公开发行包中。

按 [Sonatype GPG 指引](https://central.sonatype.org/publish/requirements/gpg/)
分发公钥，例如：

```bash
gpg --keyserver hkps://keyserver.ubuntu.com --send-keys <完整公钥指纹>
```

这里的 GPG 密钥用于 Maven 发行包签名，与眼镜 `8403` 企业验签的密钥体系不同。
SDK 不需要持有眼镜签名平台的私钥。

## Android：打包与上传

在本仓库根目录执行。脚本使用 Python 标准库和系统 GPG，无新增构建依赖。

先生成不含正式签名的检查包：

```bash
python3 tool/package_maven_central.py --version 0.1.0-beta.14 --unsigned
```

默认目录为 `build/central/0.1.0-beta.14/unsigned`。
其中 ZIP 名称带 `unsigned`，`release.json` 中 `upload_ready` 为 `false`，
上传脚本会拒绝该包。

配置好公司 GPG 密钥后，生成正式签名包：

```bash
python3 tool/package_maven_central.py \
  --version 0.1.0-beta.14 --signing-key <完整签名密钥指纹>
```

默认输出 `build/central/0.1.0-beta.14/signed/`：

```text
release.json
<Central bundle>.zip
maven/com/evenrealities/devices/even-devices-native-android/0.1.0-beta.14/
  even-devices-native-android-0.1.0-beta.14.aar
  even-devices-native-android-0.1.0-beta.14.pom
  even-devices-native-android-0.1.0-beta.14.module
  even-devices-native-android-0.1.0-beta.14-sources.jar
  even-devices-native-android-0.1.0-beta.14-javadoc.jar
  ...每个主文件的 .asc 和 md5/sha1/sha256/sha512
```

脚本校验现有 AAR 身份及依赖信息，只在发行目录补齐公开 POM 元数据。
sources JAR 包含从构建提交取得的 Android 实现源码，javadoc JAR 包含原生接入指南。双端原生源码、构建工具和编解码器输入见 [构建来源](../PROVENANCE.md)。

本地签名校验通过仅表示可以提交 Portal；命名空间权限、公钥可获取性及其它规则
仍由 Central 服务端验证。现有输出目录不会被覆盖，重跑时指定新的 `--output-dir`。

Token 已配置到当前进程环境后，上传并在 Central 验证通过后自动发布：

```bash
python3 tool/publish_maven_central.py upload \
  build/central/0.1.0-beta.14/signed --publish

python3 tool/publish_maven_central.py status <返回的 deployment_id>
```

需要先在 Portal 检查时，省略 `--publish`。状态到 `VALIDATED` 后可执行：

```bash
python3 tool/publish_maven_central.py publish <deployment_id>
python3 tool/publish_maven_central.py status <deployment_id>
```

`UPLOADED` 表示服务器接受了上传；`VALIDATED` 表示等待发布。
只有 `PUBLISHED` 才表示 Central 完成发布，随后还应从
`https://repo.maven.apache.org/maven2/com/evenrealities/devices/even-devices-native-android/0.1.0-beta.14/`
实际下载并核对产物。接口和状态见
[Portal Publisher API](https://central.sonatype.org/publish/publish-portal-api/)。
发布后同一版本不可覆盖；下一版须更新版本和对应的审计产物。

## iOS：SPM 接入与发布

SPM 通过 Git 仓库和版本 tag 分发，不需要另建一个 SPM 网站账号。
本仓库根目录清单指向 `spm/EvenDevicesSDK-0.1.0-beta.14.xcframework.zip`，
二进制跟随 Git tag 下载，无单独 ZIP 鉴权或远程 checksum 配置。

用户在 Xcode **File → Add Package Dependencies** 输入：

```text
https://github.com/even-realities/flutter_enterprise_sdk.git
```

本地可通过 **Add Local** 接入。使用已发布的 Git 标签时，选择 **Exact Version：`0.1.0-beta.14`**，product 选择 `EvenDevicesSDK`。
纯原生接入示例见 [Native SDK guide](NATIVE_SDK.md)。

维护者每次更新版本时：

1. 更新整批原生产物及校验值，保留许可、来源和实际验收记录。
2. 执行 `./tool/verify_artifacts.sh` 和 SPM 真机/模拟器宿主链接验证。
3. 提交根清单与对应二进制，为该提交创建唯一的语义版本 tag；不要移动已有 tag。
4. 使用新目录从公开 Git 地址按 tag 解析并构建纯 iOS 宿主。

可用 `swift package compute-checksum spm/EvenDevicesSDK-0.1.0-beta.14.xcframework.zip` 核对 `spm/provenance.json` 中的 SHA-256。
Apple 的说明见[二进制 Swift package 分发](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)。

## 验证边界

发行脚本测试覆盖坐标、校验值、附属包、签名与上传状态语义；
SPM 构建验证解析和链接。它们不会连接眼镜，
beta.12 的真机验收边界仍见[验证记录](VALIDATION.md)。
