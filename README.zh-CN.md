# Fuck TTNet

针对 TikTok 本地 TTNet traffic-control 缓存的 KernelSU 模块。

[English README](README.md)

这个模块的范围刻意做得很窄。它不伪装设备，不代理流量，不清除 TikTok 数据，
也不修改 SIM、语言、地区或时区设置。它只删除一条已经验证过的本地 TTNet
规则；这条规则会让 TikTok 在请求进入 DNS 或系统网络栈之前，直接把请求丢掉。

## 适用场景

当 TikTok 国际版显示无网络，但手机网络本身正常，并且 logcat 里能看到下面
这些 TTNet 错误时，适合使用这个模块：

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

模块只针对这个包名：

```text
com.zhiliaoapp.musically
```

它不是通用的 TikTok 解锁模块。如果日志里显示的是 DNS 失败、TLS 错误、代理
错误、HTTP 4xx/5xx，或者 Android 网络策略拦截，那通常不是这个模块要解决的
问题。

## 修改内容

TikTok 会把 TTNet 运行时配置放在自己的私有数据目录里。模块检查这两个文件：

```text
/data/data/com.zhiliaoapp.musically/files/server.json
/data/data/com.zhiliaoapp.musically/files/tt_net_config.config
```

模块只删除这条已知的全局 drop 规则：

```text
rule_id=3011076
service_name="drop flow"
host_group=["*"]
contain_group=["/"]
drop=1
possibility=100
```

简单说，这条规则的含义是：

```text
所有 host、所有 path，100% 丢弃。
```

模块会在开机时运行一次，之后在后台持续检查，因为 TikTok 可能在启动后重新
写入 TTNet 配置。

模块会在原文件旁边创建一次性备份：

```text
server.json.fuck_ttnet.bak
tt_net_config.config.fuck_ttnet.bak
```

修补完成后，模块会恢复 TikTok 文件的 owner/group，设置权限为 `0600`，并用
`restorecon` 恢复 SELinux context。

## 安装

在 KernelSU Manager 中安装 `fuck_ttnet-v1.0.1.zip`，然后重启设备。

重启后，强制停止 TikTok 再重新打开：

```sh
adb shell am force-stop com.zhiliaoapp.musically
```

模块也提供 action 脚本。如果你的 KernelSU Manager 版本支持模块 action，可以
从管理器里手动触发一次修补。

## 验证

模块日志：

```text
/data/adb/modules/fuck_ttnet/fuck_ttnet.log
```

常用 logcat 检查命令：

```sh
adb logcat -d -v time \
  | grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|http code=200'
```

修复前，关键特征是 TTNet 本地丢弃：

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

修复后，TikTok 应该重新发出真实网络请求。常见成功日志包括：

```text
http code=200
request fetch task succeeded
```

## 恢复

如果不再需要模块，可以在 KernelSU Manager 中禁用或卸载它。

如果要手动恢复 TikTok 的 TTNet 文件，把 `.fuck_ttnet.bak` 备份复制回原文件，
再恢复文件 owner/group 和 SELinux context。多数情况下，如果需要彻底重置，
直接清除 TikTok 数据或重装 TikTok 会更简单。

## 根因

这个问题不是手机真的没有网络。

正常请求流程大概是：

```text
TikTok -> DNS -> TCP connect -> TLS -> request/response
```

出问题时，请求在 DNS 之前就被 TTNet 本地策略丢掉了：

```text
TikTok -> TTNet local traffic-control drop
```

所以日志里会出现 `dns=-1`、`connect=-1`、`ssl=-1`。请求根本没有离开 TikTok
进程，因此改路由规则、换代理节点或调整 Android 网络权限，并不能解决这个
特定问题。

TikTok 为什么会收到或保留这条 TTNet 规则，设备侧无法完整观察。可能参与判断
的信号包括账号地区、store region、carrier region、代理出口地区、SIM/网络
国家、设备历史状态，以及已经缓存的 TTNet 策略。排查时，语言/时区和运营商
相关请求参数已经改到日本，但 TikTok 仍然返回 `-555`，直到本地 drop 规则被
移除。

已确认的本地原因是缓存里的 `rule_id=3011076` 全局 drop flow。删除这条规则后，
TTNet 行为从本地 `-555` 丢弃变成真实网络响应，例如 `http code=200`。

## 范围和限制

- 只针对 TikTok 国际版。
- 只删除 `rule_id=3011076` 的全局 `drop flow`。
- 不伪装 SIM、账号地区、设备型号或 Play Store 安装来源。
- 如果 TikTok 修改规则 ID 或 TTNet 配置格式，匹配逻辑可能需要更新。
- 如果请求到达服务器后被 TikTok 服务端策略拦截，这个模块不会绕过服务端响应。
