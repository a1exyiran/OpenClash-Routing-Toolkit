<div align="center">
  <img src="assets/banner.jpg" alt="Claude 纯净 IP 最省钱方案：只让 Claude 走纯净 IP，其余流量走便宜线路" width="100%">

# OpenClash Routing Toolkit

只让 Claude 走家宽纯净 IP，其余流量走便宜机场。<br>
订阅更新、路由器重启，规则还在。

[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-OpenWrt%20%2F%20OpenClash-1d4ed8.svg)](#限制)
[![Shell](https://img.shields.io/badge/Shell-POSIX%20sh-0ea5e9.svg)](#快速开始)
[![Tested](https://img.shields.io/badge/Tested-ImmortalWrt%20aarch64%20%2F%20Mihomo-7c3aed.svg)](#限制)
[![Install](https://img.shields.io/badge/Install-dry--run%20first-f59e0b.svg)](#快速开始)

[长文介绍](https://x.com/theyiran/status/2122701262991073350)

</div>

> [!IMPORTANT]
> 只适用于你自己管理、并且已经在用 OpenClash 和 Mihomo 的机器。先 `--dry-run`，你确认后再 `--apply`。不要用 `curl | bash`。仓库里只有占位符，请不要提交或截图真实订阅、证书、节点套餐、IP 或家用路径。不保证兼容所有版本。第一次在真路由器上使用，请留好能登进去的后路。

## 为什么

为了让 Claude 不封号，很多人把整台路由器都切到纯净 IP。能用，但刷视频、更新游戏、手机后台同步，全都在走那条最贵的线。真正需要干净出口的，其实只有 Claude 那几个域名。

这套脚本做的是：纯净 IP 只买家宽里最便宜的小流量套餐，专门给 Claude 用；其余流量交给随便一个便宜大碗的机场。两边同时挂在 OpenClash 上，该走哪条走哪条。

<p align="center">
  <img src="assets/gif-a-split.gif" alt="只有 Claude 走贵的那条：家里的设备经 OpenClash 分流，Claude / Anthropic 走家宽纯净 IP，其他流量走便宜机场" width="100%">
</p>

它不替代 OpenClash 或 Mihomo，也不提供订阅。

## 订阅更新也不丢

问题不在会不会分流，而在改完能不能留得住。直接改已经生成好的配置，订阅一重建，规则就被盖掉。

所以改名、补规则、固定出口，都做在构建层。给目标节点一个稳定别名，放在专属组第一位。正则必须恰好命中一个节点才改名，命中 0 个或多于 1 个就跳过，不会去猜。

<p align="center">
  <img src="assets/gif-b-persist.gif" alt="左边在面板里手动改，订阅更新后规则没了；右边这套方案，订阅更新和路由器重启之后规则还在" width="100%">
</p>

启动时钩子只读事先准备好的缓存，不往外拉订阅：

```text
fetch=skipped(offline)
verify=OK
```

## 特性

- 只动 Anthropic 自己的服务。ChatGPT、Gemini 和家里其余国际流量，仍走原来的便宜线。
- 认 6 个域名，并补上 Anthropic 公开网段 `160.79.104.0/21`；`DOMAIN-KEYWORD,stun` 也指到同一个专属组，避免页面和 STUN 出口不一致。STUN 流量很小，音视频仍走原来的规则。
- 订阅更新、OpenClash 重启之后，分流规则尽量还在。
- `install.sh` 分三步：`--check` 只读探测，`--dry-run` 预览（可在临时目录跑 `clash -t`），`--apply` 确认后才写入并自动备份，从不自动重启。
- 回滚默认只检查，加上参数才真改。

## 快速开始

先把 [`config.example.yaml`](config.example.yaml) 复制为 `config.yaml`，填写 `claude.node_match`（Ruby 正则，必须恰好命中一个订阅节点）和 `claude.alias`（改名后的显示名，会成为 `Claude专用` 组的首位）。示例值必须改成你自己的。订阅地址不要写进这个文件。

凭据由你自己放到 `/etc/openclash/custom/claude_b.yaml`（内容 `url: ...`，`chmod 600`）。安装器只检查它在不在、权限是什么，不读内容。

也可以先把下面这段发给助手，让它只检查、只预览：

```text
请先阅读这个仓库 main 分支的 AGENTS.md 和 SKILL.md（https://raw.githubusercontent.com/a1exyiran/OpenClash-Routing-Toolkit/main/AGENTS.md 与 https://raw.githubusercontent.com/a1exyiran/OpenClash-Routing-Toolkit/main/SKILL.md），检查我的 OpenWrt/OpenClash 环境，只预览将要改动的文件，未经我确认不要写入或重启服务。仓库：https://github.com/a1exyiran/OpenClash-Routing-Toolkit
```

需要：OpenWrt / ImmortalWrt，已安装 OpenClash、Mihomo、Ruby。可用内存低于 `deploy.min_mem_available_mb`（默认 190）时，`--dry-run` 会跳过 `clash -t`。

### 检查

```sh
./install.sh --check --config ./config.yaml
```

### 预览（不写入）

```sh
./install.sh --dry-run --config ./config.yaml
```

会列出要改的文件、钩子改法、备份位置，并在 `/tmp` 临时目录里渲染一份注入结果，内核存在且内存够时跑 `clash -t`。不写 OpenClash 目录。默认只读缓存（与开机钩子一致）；加 `--fetch` 则经本机代理拉一次订阅。

### 写入（需确认）

```sh
./install.sh --apply --config ./config.yaml
```

先再跑一遍预览，不通过就拒绝；通过后要你输入 `yes`（非交互环境必须显式加 `--yes`）。然后备份、安装脚本、接上钩子并校验。不重启，也不改生效配置本身；钩子在下一次 OpenClash 启动时才生效。重复执行时，如果文件都已是目标版本，什么都不写。

没有节点缓存时（dry-run 会提示 `build=reject`），先在内核运行时拉一次：

```sh
sh /etc/openclash/custom/claude_update.sh <运行时配置>
```

<details>
<summary>apply 会改哪些文件</summary>

- 安装 / 替换：`/etc/openclash/custom/` 下的 `claude_inject.sh`、`claude_update.sh`、`claude_rollback.sh`、`load_config.sh`、`config.yaml`（权限 600）。
- 覆写钩子 `openclash_custom_overwrite.sh`：保留你现在的钩子内容，去掉结尾的 `exit 0`，追加 Claude 注入段，并给出新旧 sha256。
- 备份当前钩子、生效配置、将被替换的文件到 `/etc/openclash/custom/.claude_backup/install_<时间戳>/`，`SHA256SUMS` 可以用 `sha256sum -c` 核对。原始钩子另存为 `.claude_backup/openclash_custom_overwrite.sh.orig`，并记下 md5 / sha256。清单写在 `.claude_backup/install.manifest`。
- 校验：`sh -n`、哈希、用已安装的脚本对临时副本试跑一次注入。

</details>

### 重启

```sh
/etc/init.d/openclash restart
```

请在维护窗口自己执行。安装器不会替你重启。

### 验证

```sh
tail -n 20 /etc/openclash/custom/claude_hook.log
# 期望：fetch=skipped(offline)、verify=OK、done level=L1

grep -c 'Claude专用' /etc/openclash/<你的配置名>.yaml
```

成功时：你注入的规则仍在规则列表前部并指向专属组；其余规则和原策略组还在；非目标流量仍走原出口。

`bash -n` 通过或离线测试通过，都不等于生产验收通过。网络层验收通过，也不等于 Claude 的登录会话一定可用。

<details>
<summary>一次维护窗口里的校验摘录</summary>

```text
# 启动钩子：内核还没起来，只读缓存，不拉订阅
fetch=skipped(offline)
verify=OK
L1 inject rc=0 elapsed=5s
```

```text
# 维护窗口里的内核校验（单次记录，不是性能承诺）
rc=0 elapsed=7s
configuration file /tmp/claude_inject_dryrun.yaml test is successful
CLASH_T=PASS
```

第一次并不总是一次过。并发锁专项曾是 `PASS=19 FAIL=20`，修完再跑才到 `PASS=39 FAIL=0`。维护窗口里第一次 `clash -t` 也因路径不在 `SAFE_PATHS` 失败，补测才通过。

</details>

### 回滚

```sh
sh /etc/openclash/custom/claude_rollback.sh           # 只检查，列出会做什么
sh /etc/openclash/custom/claude_rollback.sh --apply   # 执行
/etc/init.d/openclash restart                         # 你自己决定什么时候重启
```

先恢复钩子到安装前备份并核对哈希；这一步失败就停止，不要继续删除凭据或缓存。不自动重启。回滚会删除 `claude_b.yaml` 凭据和节点缓存；需要保留的话先自己备份。

[`scripts/claude_rollback.sh`](scripts/claude_rollback.sh) 会读 `.claude_backup/install.manifest`：用里面记下的原始钩子 md5 / sha256 核对 `.orig` 备份后恢复钩子，从运行时配置里剥掉注入的组、规则和节点，删掉凭据和缓存，再删掉安装器装上去、且之后没被改过的脚本。没有清单时（手动安装），需要用 `CLAUDE_STOCK_MD5`、`CLAUDE_RUN_CONFIG` 指定这次备份的哈希和路径，不要使用仓库里的占位路径。安装前的完整备份留在 `.claude_backup/install_<时间戳>/`。

不想用安装器，也可以按 [`docs/workflow.md`](docs/workflow.md) 手动做同样的事：备份 → 预览（`CLAUDE_CONFIG=./config.yaml ./scripts/claude_inject.sh --dry-run /path/to/current.yaml`）→ 放文件 → 重启。

## 配置

注入脚本会读取 `claude.node_match` 与 `claude.alias`；缺少任一项都会拒绝执行（没有内置的默认节点名）。

| 键 | 必填 | 说明 |
|---|---|---|
| `claude.node_match` | 是 | 在订阅节点里找出要钉死的那一个。Ruby 正则，必须恰好命中 1 个，否则跳过、不改名。 |
| `claude.alias` | 是 | 改名后的显示名，成为 `Claude专用` 组的首位（默认出口）。不能使用 `DIRECT`、`REJECT`、`Claude专用`、`ClaudeAuto`、`APNs推送` 等保留名。 |
| `openclash.config_path` | 否 | 生效配置路径。留空时从 `uci` 读取，也可用 `--target FILE` 指定。 |
| `openclash.custom_dir` | 否 | 自定义目录，默认 `/etc/openclash/custom`。 |
| `openclash.core_path` | 否 | Mihomo / clash_meta 路径，默认 `/etc/openclash/core/clash_meta`。 |
| `deploy.min_mem_available_mb` | 否 | 可用内存低于此值时 `--dry-run` 跳过 `clash -t`，默认 `190`。 |

> [!NOTE]
> 域名规则和 `Claude专用` 组名目前仍是项目固定的。`config.example.yaml` 里的 `policy.*`、`router.*`、`credentials.file`、`deploy.allow_restart` / `require_dry_run` 还没有被脚本读取，改了不会生效。订阅凭据的实际路径是 `/etc/openclash/custom/claude_b.yaml`。

占位符是 `__NAME__` 形式，避免尖括号在 shell 里被当成重定向。占位符不是真实值。

## 工作原理

OpenClash 的自定义覆盖钩子发生在内核启动之前。钩子跑起来时，本地代理端口往往还不可用，所以启动阶段不能去拉订阅，只能读缓存；订阅更新要放在内核仍在跑的时候（`claude_update.sh`）。

当前注入的规则是项目固定的：

```text
DOMAIN-SUFFIX,claude.ai,Claude专用
DOMAIN-SUFFIX,claude.com,Claude专用
DOMAIN-SUFFIX,anthropic.com,Claude专用
DOMAIN-SUFFIX,claude.app,Claude专用
DOMAIN-SUFFIX,claudeusercontent.com,Claude专用
DOMAIN-SUFFIX,claudemcpcontent.com,Claude专用
IP-CIDR,160.79.104.0/21,Claude专用,no-resolve
DOMAIN-KEYWORD,stun,Claude专用
```

`160.79.104.0/21` 是 ARIN 公开登记的 Anthropic 网段（NET-160-79-104-0-1），不是某条家用地址。像 `claude.dev`、`claudecode.ai` 这种第三方域名，不会被一起改道。

完整流程见 [`docs/workflow.md`](docs/workflow.md)。

<details>
<summary>给 Agent 的口令</summary>

| 你想做的事 | 可以说 |
|---|---|
| 只检查，不改 | 「读 AGENTS.md 和 SKILL.md，只检查我的环境，不要写入或重启。」 |
| 先预览 | 「检查环境，列出将要改的文件和回滚方式，先做预览，等我确认。」 |
| 确认后才部署 | 「这是我确认过的预览。按 SKILL.md 逐步执行，一步一校验。途中出错先停下来。」 |
| 回滚 | 「按我这次的备份做回滚检查，先不要真正执行，把命令给我看。」 |

未经确认不得写入。不要代开 GitHub issue / PR，除非用户要求并看过正文。完整禁令见 [`AGENTS.md`](AGENTS.md)，逐步流程见 [`SKILL.md`](SKILL.md)。

</details>

## 限制

- 域名规则和 `Claude专用` 组名目前仍是项目固定的；要钉死的节点改为从配置读取。这套脚本还不是通用分流工具。
- 未承诺兼容所有 OpenWrt / OpenClash / Mihomo 版本。历史环境：ImmortalWrt SNAPSHOT r32912，Linux 6.6.69，aarch64，内存 485 MB、没有 swap，Mihomo `alpha-g86257fc`。路由器型号和 OpenClash 的准确版本在资料里未能确认。
- 安装器目前只在离线沙盒里测过（伪造的 `/etc/openclash` 目录、真实 Mihomo `-t`、BusyBox ash），还没有在真实路由器上跑过完整的 `--apply` → 重启。
- 启动脚本不检查钩子返回码（残项 R-04），不能宣称完整失败关闭。钩子失败了，内核仍可能继续起来。专属组是 `select`，固定出口挂了不会自动切走。
- 生效配置里需要有一个名字以「自动选择」结尾的 url-test 组，`APNs推送` 组会把它当上游；没有的话注入的结构校验通不过，`--dry-run` 会报预览未通过。
- 部分后期变更缺少独立运行日志。
- 回滚会删除 `claude_b.yaml` 凭据和节点缓存；需要保留的话先自己备份。
- 网络层验收通过，不等于 Claude 的登录会话一定可用。注入或订阅暂时失败时，按设计降级，而不是 silently 落到直连或别的组（本地沙盒见过空组出现 `COMPATIBLE`；完整失败关闭仍有已知残项，见上）。

> [!WARNING]
> 安装器还没有在真实路由器上跑过完整的 `--apply` → 重启。第一次用请留好带外管理。

## 安全说明

- 不要上传订阅、证书、真实 IP、节点套餐、服务商品牌或家用路径，也别让助手把这些写进 Git。
- 安装器不读取、不打印订阅地址；凭据文件只检查是否存在与权限。
- `--apply` 必须输入 `yes`，或显式加上 `--yes`。
- 从不自动重启 OpenClash。
- `curl | bash` 不是默认安装方式。

## 开发与测试

给 Agent 的短规则在 [`AGENTS.md`](AGENTS.md)（Claude Code 可先读 [`CLAUDE.md`](CLAUDE.md)，它只指向前者）。离线沙盒测试：`sh tests/sandbox_test.sh`（可加 `MIHOMO_BIN=/path/to/mihomo` 用真实内核校验，`RUN_SH="busybox ash"` 用 ash 跑）。测试与部署长流程在 [`SKILL.md`](SKILL.md) 和 [`docs/workflow.md`](docs/workflow.md)。本地测试的失败日志请自行保留，不要编造仓库里没有的测试结果。

## 许可证

本项目以 [MIT License](LICENSE) 发布，版权所有 © 2026 亦然y1ran。本项目依赖并感谢 OpenWrt / ImmortalWrt、OpenClash、Mihomo 及其文档；本仓库不隶属于这些项目。
