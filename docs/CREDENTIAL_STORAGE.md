# DeepSeek API Key 存储契约

HaxPick 将 DeepSeek API Key 保存在当前用户的 `UserDefaults` 本地偏好设置中，键名为
`deepseek_api_key`。应用启动时读取并去除首尾空白；只有 `sk-` 开头的值才会作为有效 Key。

该存储是当前 macOS 用户可读取的**明文偏好设置**，不是 Keychain 或其他加密凭据存储。这样做是为了避免开发签名、安装更新或 Keychain 状态变化触发额外的系统密码验证；因此用户不应把这项“本地保存”理解为系统级安全存储。

设置页使用本地 draft，点击保存后先校验格式，再写入 `UserDefaults` 并提交到运行时状态。清空时删除该键。由于 `UserDefaults` 写入不需要系统密码，也没有 Keychain 迁移、访问、清理或重试流程。

`AppState.apiKeyStorageState` 只有两种状态：

```text
.local  已从本地偏好设置读取或保存有效 Key
.empty  没有已配置的 Key
```

API Key 仍不写入代码、仓库文件或日志；DeepSeek 请求只通过运行时的 `apiKey` 提供认证值。若未来恢复 Keychain，应同步更新这里的存储契约与迁移策略。
