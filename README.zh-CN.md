# Fuck TTNet：TikTok 无网络诊断与本地 TTNet 修复

用于诊断 TikTok 国际版多种“无网络”情况的 KernelSU 模块；其中对本地缓存的
TTNet 规则 `3011076` / `ERR_TTNET_TRAFFIC_CONTROL_DROP` /
`InternalErrorCode=-555` 提供最强的本地修复支持。

[English README](README.md)

详细调查文档：[docs/investigation.md](docs/investigation.md)

更完整的无网络分类文档：[docs/no-network-cases.zh-CN.md](docs/no-network-cases.zh-CN.md)

搜索关键词：TikTok 无网络、TikTok TTNet 3011076、TTNet traffic control
drop、`ERR_TTNET_TRAFFIC_CONTROL_DROP`、`InternalErrorCode=-555`、
`DISPATCH_DROP`、`com.zhiliaoapp.musically`。

注意：这个仓库现在把“诊断”放在第一位。当前本地修复覆盖范围是：

- 强支持：本地缓存的 TTNet dispatch drop（`3011076`、`-555`）
- 有限支持：对 `ERR_CERT_AUTHORITY_INVALID` / `-202` 之类传输层故障做
  runtime cache reset
- 不支持本地修复：设备网络本身异常、区域停运、服务端区域策略

不要把所有“无网络”都直接当成 `3011076`。具体分类见上面的总览文档。

## 模块作用

Fuck TTNet 是一个“诊断优先”的模块。它会先告诉你当前 TikTok 的“无网络”
更像是哪一类：

- 本地 TTNet drop，模块可以修
- TLS / 代理信任链失败，模块只能做有限 reset
- 设备层或服务端层问题，需要到模块外处理

当前最强支持的修复，仍然是删除 TikTok 本地缓存里那条会让请求在 DNS、TCP、
TLS 之前被本地丢弃的 TTNet traffic-control 规则。

目标包名：

```text
com.zhiliaoapp.musically
```

目标文件：

```text
/data/data/com.zhiliaoapp.musically/files/server.json
/data/data/com.zhiliaoapp.musically/files/tt_net_config.config
```

目标规则：

```text
rule_id=3011076
service_name="drop flow"
host_group=["*"]
contain_group=["/"]
drop=1
possibility=100
```

通俗说：所有 host、所有 path，100% 丢弃。

这是特指 `3011076` / `-555` 这一类 TikTok TTNet 故障：logcat 会显示本地
traffic-control drop，而且 DNS、connect、SSL 计时都还没有开始。

这个模块不伪装 SIM、设备型号、语言、时区、商店地区、账号地区或代理设置，
也不清除 TikTok 数据。它只删除这条已知的本地 TTNet drop 规则，并在修补后
恢复 TikTok 文件 owner、`0600` 权限和 SELinux context。

替换文件前，模块会在原文件旁边创建一次性备份，后缀是 `.fuck_ttnet.bak`。

## 模块用法

从仓库打包模块 zip：

```sh
scripts/package.sh
```

现在 WebUI 前端源码位于 `frontend/`，使用 Vite 8 + TypeScript 构建。生成
的静态文件会写入 `webroot/`，而 `scripts/package.sh` 会在打包前自动执行
`pnpm build`。

在 KernelSU Manager 中安装模块 zip，然后重启。

重启后，强制停止 TikTok 再重新打开：

```sh
adb shell am force-stop com.zhiliaoapp.musically
```

从 KernelSU Manager 打开模块 WebUI。这现在是主入口。WebUI 会显示：

- diagnosis ID 和传输阶段
- Android 默认网络当前是否 `VALIDATED`
- 本地 TTNet 规则命中和缓存元数据
- 最近的 `-555`、`-202`、以及泛化 UI 无网络信号
- 模块日志和从 TikTok 日志里观察到的地区信号

WebUI 操作：

- `Refresh`：读取当前 TTNet 状态。
- `Attempt Repair`：按当前诊断结果执行对应的本地动作。
- `Force Stop TikTok`：修复后重启 TikTok 进程内的 TTNet 状态。
- `Copy Diagnostics`：复制脱敏后的诊断信息。

当前修复动作有三类：

- `patch_local_ttnet`：删除本地 `3011076` 元数据并停止 TikTok
- `reset_runtime_cache`：清理易失 runtime cache 并停止 TikTok
- `none`：当前诊断没有支持的本地修复

模块现在只保留 WebUI 工作流，不再暴露单独的 KernelSU action 入口。

不再需要时，可以直接在 KernelSU Manager 中禁用或卸载模块。

## 本地修复逻辑

这个模块不 hook TikTok，也不伪装设备。本地修复逻辑保持得很小、很明确：

1. 等待 TikTok 数据目录存在。
2. 给目标文件创建一次 `.fuck_ttnet.bak` 备份。
3. 从 `server.json` 删除完整的 `3011076` 全局 drop action。
4. 从 `tt_net_config.config` 的 dispatch rule-ID 列表里删除 `3011076`。
5. 恢复 TikTok 文件 owner、`0600` 权限和 SELinux context。

如果当前诊断命中的是 `3011076`，也可以用 root 手动做同样的修复。先强制停止
TikTok 并备份：

```sh
adb shell am force-stop com.zhiliaoapp.musically
adb shell su -c 'cd /data/data/com.zhiliaoapp.musically/files &&
  cp server.json server.json.manual.bak 2>/dev/null;
  cp tt_net_config.config tt_net_config.config.manual.bak 2>/dev/null'
```

然后只删除已知的坏规则：

- 在 `server.json` 里，删除完整 JSON object：它的 `rule_id` 是 `3011076`，
  并且包含 `action="tc"`、`service_name="drop flow"`、
  `host_group=["*"]`、`contain_group=["/"]`、`drop=1`、
  `possibility=100`。
- 在 `tt_net_config.config` 里，如果缓存的 `dispatch:` 规则 ID 列表包含
  `3011076`，只把这个 ID 从列表中删除。

编辑后恢复 owner/context，再重启 TikTok：

```sh
adb shell su -c 'ls -ldn /data/data/com.zhiliaoapp.musically/files'
```

把 `ls -ldn` 输出里的数字 owner/group 填到下面的 `APP_UID:APP_GID`：

```sh
adb shell su -c 'cd /data/data/com.zhiliaoapp.musically/files &&
  chown APP_UID:APP_GID server.json tt_net_config.config 2>/dev/null;
  chmod 600 server.json tt_net_config.config 2>/dev/null;
  restorecon server.json tt_net_config.config 2>/dev/null'
adb shell am force-stop com.zhiliaoapp.musically
```

不要删除无关 TTNet 规则。不要公开完整 TTNet 配置文件，除非已经移除账号、
token、cookie、设备标识等隐私字段。

模块日志：

```text
/data/adb/modules/fuck_ttnet/fuck_ttnet.log
```

常用检查：

```sh
adb shell su -c 'grep -Rsn 3011076 /data/data/com.zhiliaoapp.musically/files'
adb logcat -d -v time |
  grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|http code=200'
```

只有在手机网络本身正常，但 TikTok 显示无网络，并且 logcat 出现下面这种
TTNet 本地丢弃特征时，才应该使用 `3011076` 本地修复：

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

如果实际错误是设备网络未通过校验、TLS、代理、Android 网络策略，或者 TikTok
服务端返回的 HTTP 错误，那么 `3011076` 修复通常不是正确解法。

## 为什么会有这个 3011076 修复

TTNet 是 TikTok 应用内的网络栈。它会从本地缓存加载 TNC 运行时配置，并在
请求进入普通网络流程前先执行 URL dispatch action。

正常请求路径：

```text
TikTok -> DNS -> TCP connect -> TLS -> HTTP request
```

这次故障：

```text
TikTok -> TTNet URL dispatch -> local drop (3011076) -> -555
```

所以失败日志里会看到 `dns=-1`、`connect=-1`、`ssl=-1`：请求根本没有离开
TikTok 进程。

目前仍然不确定的是：TikTok 到底在什么上游条件下下发或保留 `3011076`。
更早的排查曾把“香港代理出口 + SIM 区域不匹配”当成高概率触发条件，但后续
证据并不足以把这个解释当成定论。更稳妥的说法是：

- `3011076` 是一个服务端下发的 TTNet/TNC dispatch rule ID
- 一旦这条规则已经缓存到本地，TTNet 就能在离线条件下继续执行本地 `-555` 丢弃
- 当前模块修的只是这个“本地缓存后遗症”

公开反编译的 TTNet 代码与这个现象一致：

- 本地 TNC 从 `ttnet_tnc_config` / `server.json` 加载。
- `ttnet_dispatch_actions` 会被解析成按优先级排序的 dispatch actions。
- `action="tc"` 会解析 `host_group`、`contain_group`、`drop`、
  `drop_code`、`possibility` 和 `service_name`。
- 命中的 `tc` action 如果带 `drop=1`，会返回 `DISPATCH_DROP`。
- OkHttp 路径看到“dispatch 后 URL 为空 + 有命中规则 ID”时，会抛出
  `ERR_TTNET_TRAFFIC_CONTROL_DROP`，默认错误码是 `-555`。

`3011076` 更准确地说是 TTNet/TNC dispatch rule ID。它不是 Android 错误码、
SIM/MCC 代码，也不是代理代码。真正造成阻断的是规则内容：
`drop=1`、host 通配、path 包含 `/`、概率 100。

已经证明的部分：

- 设备上曾经缓存过 `rule_id=3011076` 的全局 drop action。
- 删除这条 action 后，TikTok 从本地 `-555` 丢弃变成真实网络响应。
- 按公开反编译逻辑写出的白盒模型，对这条规则会得到同样的
  `DISPATCH_DROP`、空输出 URL、命中规则 ID 和 `-555`。
- 导致 `3011076` 出现的上游决策路径目前还没完全解开。
- 香港地区行为、服务端区域策略、代理出口、SIM 信号、设备历史都可能参与，
  但在没有更强证据前，不应把其中任何单一因素写成已经坐实的根因。

尚未证明的部分：

- 其他代理出口区域或 SIM/运营商组合是否也会触发 `3011076`。
- 触发条件是否仅取决于代理出口区域，还是 SIM MCC/MNC 不匹配、账号区域、
  商店区域或设备历史的组合。
- 限定范围的公开代码搜索找到了 TTNet traffic-control 代码和 TNC 样本，但没有
  找到公开的 `3011076` 精确命中。

同一台设备上现在还本地证实了另一类不能和 `3011076` 混淆的问题：
`net::ERR_CERT_AUTHORITY_INVALID` 配合 `InternalErrorCode=-202`。这类情况说明
TTNet/Cronet 已经进入 TLS 阶段并在证书链校验时失败，当前模块对它无效。详见
[docs/no-network-cases.zh-CN.md](docs/no-network-cases.zh-CN.md)。

## 白盒机制检查

仓库里有一个只在本地运行的 TTNet dispatch 机制模型：

```sh
python3 scripts/ttnet_dispatch_model.py --self-test
python3 scripts/ttnet_dispatch_model.py \
  --config samples/3011076_drop_rule.json \
  --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
python3 scripts/extract_ttnet_rule.py \
  --input samples/observed_3011076_drop_rule.json --sample |
  python3 scripts/ttnet_dispatch_model.py \
    --config - \
    --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
```

这不是“TikTok 真实选择 `3011076`”的完整复现；它只验证当本地 TNC 已经存在
这条规则时，客户端 TTNet 为什么会把请求丢成 `-555`。

如需重复调查中的公开源码搜索：

```sh
scripts/search_public_evidence.sh
```

## 范围和限制

- 只针对 TikTok 国际版。
- 当前最强支持的本地修复仍然是已知的 `3011076` 全局 drop flow。
- 模块现在运行在被动模式：诊断和修复都通过 WebUI 驱动，而不是后台自动改文件。
- 如果 TikTok 修改规则 ID 或配置格式，匹配逻辑可能需要更新。
- 如果请求已经到达 TikTok 服务端并被服务端拒绝，这个模块不能绕过服务端响应。
