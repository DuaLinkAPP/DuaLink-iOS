<p align="center">
  <img src="./Docs/Assets/AppIcon.svg" width="160" alt="DuaLink App 图标">
</p>

<h1 align="center">DuaLink iOS</h1>

<p align="center">连接 iPhone 与鸿蒙 DuaLink</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/dualink/id6780105243">App Store 下载</a>
  · <a href="#使用">使用说明</a>
  · <a href="#编译">源码编译</a>
</p>

通过本地蓝牙转发 iPhone 通知、回复通知和同步实时活动。通信在两台设备之间完成，不依赖开发者服务器。

这里提供 iOS 端源码，需要配合鸿蒙端 DuaLink 使用。

## 下载与使用条件

符合以下条件的用户，可以直接[从 App Store 下载 DuaLink](https://apps.apple.com/us/app/dualink/id6780105243)，无需自行编译：

| 条件 | 要求 |
| --- | --- |
| 设备与系统 | iPhone，iOS 26.5 或更高版本 |
| 手机所在位置 | **iPhone 实际位于欧盟** |
| Apple 账户地区 | **登录的 Apple 账户国家或地区属于欧盟成员国** |
| 应用版本 | 使用包含“通知回复”功能的版本 |

**手机位置与账户地区必须同时满足要求。** 仅把手机的“语言与地区”改为欧盟，或更换下载、安装方式，并不能自动获得通知回复资格。美国区账户不属于欧盟账户。

上面的下载链接使用美国区网页地址；网页地址本身不会改变你的 Apple 账户地区或使用资格。

这些条件针对通知回复的正式使用。公开源码和自行签名不等于解除地区限制；开发者可按 Apple 的规则在其他地区进行开发测试。具体规则见 [Apple 官方说明](https://developer.apple.com/documentation/accessorynotifications)。

## 使用

1. 鸿蒙端选择“通知回复”，保持接收服务运行。
2. iPhone 开启“使用通知回复”，添加鸿蒙手机。
3. 按系统提示允许通知转发。

两端模式需要一致。只有仍有效、且来源 App 提供文字回复操作的通知才能回复。

如果使用鸿蒙端的短信模式，iPhone 上的 DuaLink 无需操作。本项目不直接读取或发送短信。

自行编译需要为主 App 和三个扩展配置签名及所需能力；免费 Apple 账号支持情况尚未验证。当前已通过编译、协议测试和模拟器界面测试，独立签名后的双机通信与后台回复仍需真机验证。

## 编译

建议使用 Xcode 27.1 或兼容的更新版本。

1. 打开 `DuaLink.xcodeproj`，选择 `DuaLink` Scheme。
2. 将 `Config/Local.xcconfig.example` 复制为 `Config/Local.xcconfig`。
3. 填入自己的 `DEVELOPMENT_TEAM` 和唯一的 `DUALINK_BUNDLE_ID_PREFIX`。
4. 为四个 Target 配置相同的 App Group，并确认签名包含对应能力。
5. 选择 iPhone，开启开发者模式后运行。

| Target | 能力 |
| --- | --- |
| DuaLink | App Groups |
| DuaLinkDataProvider | App Groups、`com.apple.developer.accessory-data-provider` |
| DuaLinkSecurity | App Groups、`com.apple.developer.accessory-transport-security` |
| DuaLinkTransport | App Groups、`com.apple.developer.accessory-transport-extension`、`bluetooth-central` |

`Config/Local.xcconfig` 是本地签名配置，不要提交到仓库。

## 测试

```sh
swift test --package-path NotificationLab
```

## 隐私

设置和设备名称保存在本机。经系统授权的通知通过加密蓝牙链路发送到已授权设备；通知正文、回复内容和密钥不会上传到开发者服务。

## 许可

采用 [MPL 2.0](LICENSE)。允许商用；分发时须按许可证要求提供受其覆盖的源码及修改。
