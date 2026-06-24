# Fuck TTNet：TikTok TTNet 3011076 无网络修复

针对 TikTok 国际版因 TTNet 规则 `3011076`、
`ERR_TTNET_TRAFFIC_CONTROL_DROP`、`InternalErrorCode=-555` 导致无网络的
KernelSU 模块。

[English README](README.md)

详细调查文档：[docs/investigation.md](docs/investigation.md)

搜索关键词：TikTok 无网络、TikTok TTNet 3011076、TTNet traffic control
drop、`ERR_TTNET_TRAFFIC_CONTROL_DROP`、`InternalErrorCode=-555`、
`DISPATCH_DROP`、`com.zhiliaoapp.musically`。

## 模块作用

Fuck TTNet 删除 TikTok 本地缓存里的一条 TTNet traffic-control 规则。这条
规则会让 TikTok 在 DNS、TCP、TLS 之前就把请求本地丢弃。

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

在 KernelSU Manager 中安装模块 zip，然后重启。

重启后，强制停止 TikTok 再重新打开：

```sh
adb shell am force-stop com.zhiliaoapp.musically
```

如果 KernelSU Manager 支持模块 action，可以手动运行一次 action。action 会
打印修补前后的规则命中数量。

不再需要时，可以直接在 KernelSU Manager 中禁用或卸载模块。

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
TTNet 本地丢弃特征时，才适合使用：

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

如果实际错误是 DNS、TLS、代理、Android 网络策略，或者 TikTok 服务端返回的
HTTP 错误，这个模块通常不是正确解法。

## 为什么会出现

TTNet 是 TikTok 应用内的网络栈。它会从本地缓存加载 TNC 运行时配置，并在
请求进入普通网络流程前先执行 URL dispatch action。

正常请求路径：

```text
TikTok -> DNS -> TCP connect -> TLS -> HTTP request
```

这次故障路径：

```text
TikTok -> TTNet URL dispatch -> local traffic-control drop
```

所以失败日志里会看到 `dns=-1`、`connect=-1`、`ssl=-1`：请求根本没有离开
TikTok 进程。

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

尚未证明的部分：

- TikTok 服务端为什么给这台设备下发或保留 `3011076`。
- 触发条件到底是账号、商店地区、运营商/网络地区、代理出口、设备历史、
  缓存策略状态，还是多种信号组合。
- 限定范围的公开代码搜索找到了 TTNet traffic-control 代码和 TNC 样本，但没有
  找到公开的 `3011076` 精确命中。

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
- 只删除已知的 `3011076` 全局 drop flow。
- TikTok 启动后可能重写 TTNet 配置，所以 service 脚本会在后台重复检查。
- 如果 TikTok 修改规则 ID 或配置格式，匹配逻辑可能需要更新。
- 如果请求已经到达 TikTok 服务端并被服务端拒绝，这个模块不能绕过服务端响应。
