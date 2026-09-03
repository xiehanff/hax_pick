# DeepSeek API Key 存储与恢复契约

本文档记录 HaxPick 对 DeepSeek API Key 的持久化、升级迁移、故障降级和恢复规则。

## 主存储

API Key 的主持久化存储是 macOS Keychain Generic Password：

```text
service: com.hax.haxpick.deepseek-api-key
account: deepseek-api-key
accessible: when unlocked, this device only
```

`UserDefaults.deepseek_api_key` 只允许作为旧版本升级时的 legacy fallback，不作为新凭证的正常写入位置。

## Credential health

`AppState.apiKeyStorageState` 明确描述当前凭证状态：

```text
.keychain
  Key 已由 Keychain 持久化。

.legacyMigrationPending
  当前使用 legacy UserDefaults Key；Keychain 明确缺少 item，迁移写入失败。

.keychainUnavailable
  当前无法安全确定或修复 Keychain 状态；可以临时使用 legacy fallback，但禁止把 legacy 写回未知状态的 Keychain。

.empty
  当前没有已配置 API Key，且 Keychain 状态已明确可用/为空。
```

菜单栏设置必须根据这个状态显示真实存储情况，不能只根据 `apiKey` 是否非空推断“已保存在 Keychain”。

## 启动读取顺序

```text
启动
  ↓
读取 Keychain
  ├─ 有有效 sk- Key
  │    → Keychain 为权威值
  │    → 删除 legacy plaintext
  │    → .keychain
  │
  ├─ 明确 ItemNotFound
  │    ↓
  │  检查 legacy
  │    ├─ 无有效 legacy → .empty
  │    └─ 有 legacy
  │         ├─ 写入 Keychain 成功 → 删除 legacy → .keychain
  │         └─ 写入失败 → 保留 legacy → .legacyMigrationPending
  │
  ├─ 找到 item 但内容格式无效
  │    → 先尝试删除确定损坏的 item
  │    ├─ 删除成功 → 再按 ItemNotFound 路径处理 legacy
  │    └─ 删除失败 → .keychainUnavailable，禁止 legacy write-back
  │
  └─ transient read error
       → Keychain 权威状态未知
       → 可临时读取 legacy
       → .keychainUnavailable
       → 禁止 legacy write-back
```

核心不变量：

> 只有明确知道 Keychain 没有可用 item 时，legacy 才允许迁移写入。Keychain 状态未知时绝不拿旧凭证覆盖。

## 显式保存与清空

设置页使用 local draft，运行时 `AppState.apiKey` 表示最后一个成功提交的凭证。

保存：

```text
local draft
  ↓ 格式校验
Keychain save
  ├─ 成功
  │    → 删除 legacy plaintext
  │    → commit runtime apiKey
  │    → state = .keychain
  │
  └─ 失败
       → runtime 不变
       → Keychain 上一 committed value 不变
       → legacy fallback 不变
       → storage state 不变
       → UI 显示错误
```

清空同样遵循事务顺序：

```text
Keychain delete
  ├─ 成功
  │    → 删除 legacy plaintext
  │    → runtime = empty
  │    → state = .empty
  │
  └─ 失败
       → runtime / Keychain / legacy / state 全部保持上一 committed 状态
```

因此 legacy 的退休时机是：

> **Keychain save/delete 已经成功之后。**

不能为了“避免旧 Key 回弹”在持久化成功之前先删除最后一个可恢复的 legacy 凭证。

## 安全重试

`.legacyMigrationPending` 和 `.keychainUnavailable` 可以显示「重试」。

重试不是简单调用 `save(legacy)`，而是重新执行完整读取流程：

```text
重试
  ↓
fresh Keychain read
  ├─ 已出现有效新 Key
  │    → 使用新 Key
  │    → 删除 legacy
  │    → 不写旧 legacy
  │
  ├─ 明确 ItemNotFound
  │    → 才允许尝试迁移 legacy
  │
  ├─ 确定损坏 item
  │    → 先清理；清理成功后才允许迁移
  │
  └─ read / cleanup error
       → 保持 fallback
       → 禁止 legacy write-back
```

如果用户正在设置页编辑一个尚未保存的 draft，点击「重试」不能覆盖这段本地输入；只有 draft 仍等于重试前 committed Key 时，UI 才自动同步重试后发现的新 committed Key。

## 测试不变量

至少保持以下回归测试：

- Keychain 有效值优先于 legacy；
- migration 成功后才删除 legacy；
- migration save failure 保留 legacy 并标记 pending；
- transient read failure 不进行 legacy write-back；
- retry 时若出现更新 Keychain 值，旧 legacy 不得覆盖它；
- 确定损坏 item 必须先成功清理，才能迁移 legacy；
- explicit save/clear failure 不得删除上一 committed legacy；
- explicit save/clear failure 不得修改 runtime/state；
- storage warning 文案不得把 legacy fallback 描述成“已安全保存在 Keychain”。
