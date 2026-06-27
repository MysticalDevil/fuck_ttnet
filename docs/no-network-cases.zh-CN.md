# TikTok 无网络问题分类

这个仓库最初只处理一种很具体的情况：删除本地缓存的 TTNet drop 规则
`3011076`。但 TikTok 的“无网络”并不只有这一类。

本文把目前已知情况按下面几个维度拆开：

- 可观察到的错误特征
- 更可能的触发机制
- 证据强度
- 是否已在本仓库环境里复现
- 是否能靠本地模块修掉

[English](no-network-cases.md)

## 证据等级

- `本地已证实`：已经在本仓库使用的设备上抓到文件或日志，并完成复现。
- `外部强支持`：有 TikTok 官方材料或一手研究支撑，但没有在本机完整重跑。
- `用户报告`：现象可信，但证据还不够强，不能当成定论。

## 总表

| 情况 | 常见特征 | 机制 | 证据 | 本地复现 | 本地可修 |
| --- | --- | --- | --- | --- | --- |
| 设备网络本身未通过校验 | Android 显示 Wi-Fi 无互联网，其他 App 也会部分异常 | 系统网络、DNS、Captive Portal 或代理链路本身异常 | 本地已证实 | 可以 | 不可以 |
| 本地 TTNet dispatch 丢弃 | `ERR_TTNET_TRAFFIC_CONTROL_DROP`、`InternalErrorCode=-555`、`dns=-1 connect=-1 ssl=-1` | 本地缓存的 TNC/TTNet 规则在网络 I/O 前丢弃请求 | 本地已证实 | 可以 | 可以 |
| TLS 信任链 / 代理证书失败 | `net::ERR_CERT_AUTHORITY_INVALID`、`InternalErrorCode=-202`、有真实 DNS/connect/SSL 耗时 | TTNet/Cronet 在 TLS 握手阶段失败 | 本地已证实 | 可以 | 不可以 |
| 区域停运 / 市场下线 | UI 上表现为“无网络”或区域不可用 | 服务在该地区本身就不可用 | 外部强支持 | 未本地重跑 | 通常不行 |
| 基于 SIM / IP 的服务端区域判定 | SIM/IP/运营商区域信号参与策略决策 | App 和服务端按区域信号决定是否允许使用 | 外部强支持 | 未本地重跑 | 通常不行 |

## 情况 0：设备网络本身未通过校验

### 情况 0 特征

- Android 自己就认为默认网络没有通过互联网校验。
- Wi‑Fi UI 可能显示“已连接但无法访问互联网”。
- 其他 App 也可能出现“文字能刷出，但图片、头像、后台请求异常”的情况。
- 这时 TikTok 专属日志往往不稳定，因为底层网络本身已经不健康。

### 情况 0 机制

这比 TikTok 更底层。DNS、Captive Portal 状态、路由器策略、代理健康度，
或者系统联网校验，在 TTNet 介入之前就已经有问题。

### 情况 0 证据

- 已在本仓库环境本地证实：**2026-06-27** 这台设备重启后，Android 网络重新变成
  `VALIDATED`，TikTok 同时不再继续打出之前的 `-202` 特征。

### 情况 0 复现状态

- 已在本地证实。

### 情况 0 是否本地可修

- 不是当前模块能修的。
- 正确处理层级在设备、Wi‑Fi、DNS、路由器或代理。

## 情况 1：本地 TTNet Dispatch 丢弃

### 情况 1 特征

- `ERR_TTNET_TRAFFIC_CONTROL_DROP`
- `InternalErrorCode=-555`
- `dns=-1`、`connect=-1`、`ssl=-1`
- TikTok 本地文件里有类似下面的 dispatch action：
  - `rule_id=3011076`
  - `action="tc"`
  - `drop=1`
  - host/path 是通配

### 情况 1 机制

TTNet 会从本地缓存加载 TNC dispatch 策略，并且能在 DNS、TCP、TLS 之前
直接丢请求。本仓库观测到的 `3011076` 就是一个全局 drop action。

### 情况 1 证据

- 白盒分析文档：[investigation.md](investigation.md)
- 模块实际修补的就是这两个文件：
  - `/data/data/com.zhiliaoapp.musically/files/server.json`
  - `/data/data/com.zhiliaoapp.musically/files/tt_net_config.config`

### 情况 1 复现状态

- 已在本地证实。
- 这个仓库里已经有真实复现：保留或注入本地 dispatch 规则，然后观察 `-555`。
- 当前模块和 WebUI 已经覆盖了这类情况。

### 情况 1 是否本地可修

- 可以。
- 当前 KernelSU 模块只针对这一类。

## 情况 2：TLS 信任链 / 代理证书失败

### 情况 2 特征

- `net::ERR_CERT_AUTHORITY_INVALID`
- `ErrorCode=11`
- `InternalErrorCode=-202`
- 请求已经打到了真实远端 IP
- DNS/connect/SSL 都有耗时，不是 `-1`

在当前设备 **2026-06-27** 的实机日志里，启动 TikTok 后同时看到了：

- `current_region=CN`
- `sys_region=JP`
- `mcc_mnc=46011`
- `carrier_region=HK`
- `carrier_region_v2=454`
- `residence=HK`
- `op_region=HK`

样本日志：

- [samples/observed_err_cert_authority_invalid.log](../samples/observed_err_cert_authority_invalid.log)

### 情况 2 机制

这不是本地 TTNet dispatch drop。TTNet/Cronet 已经进入 TLS 阶段，然后在证书
链校验时失败。Chromium 把 `ERR_CERT_AUTHORITY_INVALID` 定义为 `-202`。

支撑来源：

- Chromium net error 列表：
  <https://chromium.googlesource.com/chromium/src/+/main/net/base/net_error_list.h>

### 情况 2 关键区别

日志里出现 `carrier_region=HK` 或 `op_region=HK`，并不自动等于 `3011076`。
这次实机复现里，TikTok 已经发生了真实网络 I/O，失败点在证书校验。

### 情况 2 复现状态

- 已在本地证实。
- 通过清空 logcat、启动 TikTok、抓取新日志完成复现。

使用：

```sh
scripts/diagnose_no_network.sh
```

### 情况 2 是否本地可修

- 不能靠当前模块修。
- 这通常意味着代理 TLS 劫持、未被系统信任的 CA、或者网络路径上的证书链有问题。

## 情况 3：区域停运 / 市场下线

### 情况 3 特征

- 对用户来说常常表现成泛化的“无网络”或“当前区域不可用”。
- 公开材料里还没有找到一个明确、可复核的内部 TTNet/Cronet 错误码。
- 当前 APK 里确实存在这些用户提示字符串：
  - `No internet connection`
  - `This feature is temporarily unavailable`
  - `Widget not available in your region.`

### 情况 3 机制

这更像产品可用性决策，不一定是传输层故障，也不一定是本地 TTNet drop。
即使底层联网正常，App 或后端也可以按地区直接拒绝服务。

### 情况 3 证据

- TikTok 在 2020 年 7 月对 Axios 明确表示已停止在香港运营。
- SCMP 记录了已安装的 TikTok 会对香港 SIM 或香港 IP 的用户显示无网络体验。
- TikTok 官方支持文档说明，账号地区会参考 SIM 区域和 IP，并且某些功能并非所有地区都可用。

来源：

- <https://www.axios.com/2020/07/07/tiktok-to-pull-out-of-hong-kong>
- <https://www.scmp.com/abacus/tech/article/3092574/tiktok-has-officially-pulled-out-hong-kong-you-can-still-use-it-if-you>
- <https://support.tiktok.com/ar/account-and-privacy/account-information/account-region>

### 情况 3 复现状态

- 外部强支持。
- 本仓库还没有把它做成一次干净的历史重跑复现。

### 情况 3 是否本地可修

- 通常不行。
- 只有当“无网络”其实是服务端先下发了一个本地 TTNet drop 规则时，删本地规则才有意义。

## 情况 4：基于 SIM / IP 的服务端区域判定

### 情况 4 特征

- 仅开 VPN 未必够用。
- SIM、IP、运营商区域等信号会参与服务端策略决策。
- 公开资料里没有找到一个稳定、明确的 TikTok 内部错误码映射。

### 情况 4 机制

针对印度封禁的第一手研究表明，TikTok 存在基于 SIM 派生信号的 app-side /
server-side 区域判定。App 侧能读 SIM 国家，服务端也能依据请求里带出的区域
参数做策略判断。

这与当前本地日志里可见的信号族是一致的：

- `carrier_region`
- `carrier_region_v2`
- `mcc_mnc`
- `op_region`
- `residence`

### 情况 4 证据

PAM 2024 论文指出：

- TikTok 会调用 `getSimCountryISO`。
- 研究者修改 APK，把 `carrier_region=IN` 改成 `carrier_region=US`，并让
  `getSimCountryISO` 固定返回 `US` 后，App 可以再次工作。
- 仅使用 VPN、但保留印度 SIM 时，问题仍然存在。

一手来源：

- <https://www.devashishgosain.com/assets/files/On_app_filtering_in_India_PAM_24_Camera_Ready.pdf>

### 情况 4 复现状态

- 有强一手研究支撑。
- 还没有在本仓库设备上完整重跑。
- 这类情况不能靠“注入一个本地规则”就算真实复现，因为关键决策在服务端。

### 情况 4 是否本地可修

- 通常没有单一的本地修法。
- 如果服务端已经顺带下发了一个本地 TTNet drop 规则，模块可以清掉这个本地症状；
  但它不能改写背后的服务端区域策略。

## 实际排查顺序

当 TikTok 说“无网络”时，先按这个顺序分流：

1. 如果 Android 自己就显示默认网络未通过校验，先修设备或路由器联网状态。
2. 如果日志是 `ERR_TTNET_TRAFFIC_CONTROL_DROP` 和 `-555`，按本地 TTNet drop 处理。
3. 如果日志是 `ERR_CERT_AUTHORITY_INVALID` 和 `-202`，按 TLS / 代理信任链问题处理。
4. 如果已经有真实 HTTP 请求或区域不可用 UI，但没有 `-555`，优先怀疑服务端区域策略。
5. 如果目前只有 UI 现象，没有强日志特征，先抓新日志，不要先随机改设置。

仓库里的快速分类脚本：

```sh
scripts/diagnose_no_network.sh
```
