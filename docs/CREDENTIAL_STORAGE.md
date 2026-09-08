# DeepSeek API Key 存储契约

HaxPick 将 DeepSeek API Key 保存在当前用户的 `UserDefaults` 本地缓存中，键名为
`deepseek_api_key`。应用启动时读取并去除首尾空白；只有 `sk-` 开头的值才会作为有效 Key。

设置页使用本地 draft，点击保存后先校验格式，再写入 `UserDefaults` 并提交到运行时状态。清空时删除该键。由于 `UserDefaults` 写入不需要系统密码，也没有 Keychain 迁移、访问、清理或重试流程。

`AppState.apiKeyStorageState` 只有两种状态：

```text
.local  已从本地缓存读取或保存有效 Key
.empty  没有已配置的 Key
```

API Key 仍不写入代码、配置文件或网络请求之外的其他位置；DeepSeek 请求只通过运行时的 `apiKey` 提供认证值。
