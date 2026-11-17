# 只让 Claude 走纯净 IP，其余流量用现有的便宜线路

[![OpenWrt](https://img.shields.io/badge/OpenWrt-ImmortalWrt-blue)](#限制与已知问题)
[![OpenClash](https://img.shields.io/badge/OpenClash-custom%20hook-lightgrey)](#限制与已知问题)
[![Mihomo](https://img.shields.io/badge/Mihomo-kernel-lightgrey)](#限制与已知问题)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

仓库名 `OpenClash-Routing-Toolkit`。在你自己的 OpenWrt / ImmortalWrt 路由器上，把 Claude 的流量单独送到纯净 IP 线路，其余流量继续走更便宜的那条；订阅更新和 OpenClash 重启之后，这套分流尽量还在。失败时可以检查、可以往回退。它不替代 OpenClash 或 Mihomo，也不提供订阅。

> [!IMPORTANT]
> 只适用于你自己管理、并且已经在用 OpenClash 和 Mihomo 的机器。先预览，你确认后再写入。仓库里的示例只有占位符，请不要提交或截图真实订阅、证书、节点套餐、IP 或家用路径。`curl | bash` 不是默认安装方式，也不保证兼容所有版本。

现在能公开的是已经跑通过的方法和脚本（见 [`scripts/`](scripts/)）。注入脚本会读取 `config.yaml` 里的 `claude.node_match` 与 `claude.alias`。安装器 `install.sh` 分三步：`--check` 只读探测，`--dry-run` 预览会改什么，`--apply` 你确认后才写入，从不自动重启。

## 它做什么

启动时钩子只做离线注入，订阅更新放在内核还在跑的时候。校验通过再原子替换，回滚默认先检查。实际场景是：Claude / Anthropic 自有流量走你指定的纯净 IP 出口，其余流量保持原策略。请用你自己的订阅，并在配置里填写要钉死的节点匹配规则和别名，不要照搬示例值。

这不是图形面板，也不保证对任意路由器都能一次跑通；每台机器都要先 `--dry-run` 看结果。

## 演示

下面是一次维护窗口里的真实校验摘录。路径已是临时文件，配置名和地址在仓库里是占位符。

订阅更新 / 重启之后，怎样算「还在」：

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

## 30 秒开始（推荐：先发给你的 AI）

把仓库地址换成你的克隆或 fork，把下面整段发给助手。**它应先检查、先预览；未经你确认，不得写入任何文件、不得重启服务。**

```text
请先阅读这个仓库 main 分支的 AGENTS.md 和 SKILL.md（https://raw.githubusercontent.com/a1exyiran/OpenClash-Routing-Toolkit/main/AGENTS.md 与 https://raw.githubusercontent.com/a1exyiran/OpenClash-Routing-Toolkit/main/SKILL.md），检查我的 OpenWrt/OpenClash 环境，只预览将要改动的文件，未经我确认不要写入或重启服务。仓库：https://github.com/a1exyiran/OpenClash-Routing-Toolkit
```

自己动手的话，在路由器上克隆仓库后按这个顺序来（详见下面「安装」）：

```sh
./install.sh --check   --config ./config.yaml   # 只读探测
./install.sh --dry-run --config ./config.yaml   # 列出会改的文件，临时目录渲染 + clash -t，不写入
./install.sh --apply   --config ./config.yaml   # 再预览一遍，输入 yes 才写入；不重启
/etc/init.d/openclash restart                   # 你自己在维护窗口执行
```

不要改用 `curl | bash`。

## 典型场景

对标常见网络工具的「先给能跑通的例子」。以下都是你在**自己的**路由器上、用**自己的**订阅和组名时，要能验证的事：

| 场景 | 怎样才算成功 |
|---|---|
| 订阅刚更新过 | 你注入的规则仍在规则列表前部，并指向你指定的策略组；其余规则和原策略组还在 |
| OpenClash 刚重启过 | 钩子日志为离线命中缓存（例如 `fetch=skipped(offline)`），结构校验通过；非目标流量仍走原出口 |
| 注入或订阅暂时失败 | 按设计降级，而不是 silently 落到直连或别的组（本地沙盒见过空组出现 `COMPATIBLE`；完整失败关闭仍有已知残项，见限制） |
| 决定撤掉这次改动 | 先跑回滚检查，确认原厂钩子备份校验通过，再执行恢复；不自动重启 |

## 安装

1. 确认环境：OpenWrt / ImmortalWrt，已安装 OpenClash 与 Mihomo、Ruby；看可用内存（历史机器只有 485 MB、无 swap，内存紧张时 `--dry-run` 会跳过 `clash -t`，门槛是 `deploy.min_mem_available_mb`）。
2. 复制 [`config.example.yaml`](config.example.yaml) 为 `config.yaml`，填写 `claude.node_match`（Ruby 正则，必须恰好命中一个订阅节点）和 `claude.alias`（改名后的显示名，会成为 `Claude专用` 组的首位）。示例值 `美国01` / `Claude-Node` 只是占位，必须改成你自己的。`openclash.config_path` 留空时从 `uci` 读取，也可以用 `--target FILE` 指定。订阅地址不写进这个文件。
3. 订阅凭据由你自己放到 `/etc/openclash/custom/claude_b.yaml`（内容 `url: ...`，`chmod 600`）。安装器只检查它在不在、权限是什么，不读内容。
4. 只读探测：`./install.sh --check --config ./config.yaml`。
5. 预览：`./install.sh --dry-run --config ./config.yaml`。它会列出：
   - 要安装 / 替换的文件：`/etc/openclash/custom/` 下的 `claude_inject.sh`、`claude_update.sh`、`claude_rollback.sh`、`load_config.sh`、`config.yaml`（600）；
   - 覆写钩子 `openclash_custom_overwrite.sh` 的改法：保留你现在的钩子内容，去掉结尾的 `exit 0`，追加 Claude 注入段，并给出新旧 sha256；
   - apply 会做的备份、缓存路径（`claude_cache/`）和凭据状态；
   - 在 `/tmp` 临时目录里用当前生效配置渲染一份注入结果（默认只读缓存，和开机钩子一样；加 `--fetch` 则经本机代理拉一次订阅），内核存在且内存够时跑 `clash -t`。

   dry-run 不写 OpenClash 目录下的任何文件，临时目录结束即删。
6. 写入：`./install.sh --apply --config ./config.yaml`。它先把预览再跑一遍，预览不通过就拒绝；通过后要你输入 `yes`（非交互环境必须显式加 `--yes`）。然后：
   - 备份当前钩子、生效配置、将被替换的文件到 `/etc/openclash/custom/.claude_backup/install_<时间戳>/`，`SHA256SUMS` 可以用 `sha256sum -c` 核对；
   - 原始钩子另存为 `.claude_backup/openclash_custom_overwrite.sh.orig`，并记下 md5 / sha256；
   - 安装脚本、接上钩子、写清单 `.claude_backup/install.manifest`；
   - 校验：`sh -n`、哈希、用已安装的脚本对临时副本试跑一次注入。

   不重启 OpenClash，也不改生效配置本身；钩子在下一次 OpenClash 启动时才生效。重复执行 `--apply` 时，如果文件都已是目标版本，什么都不写。
7. 没有节点缓存时（dry-run 会提示 `build=reject`），先在内核运行时拉一次：`sh /etc/openclash/custom/claude_update.sh <运行时配置>`。
8. 在你的维护窗口手动重启：`/etc/init.d/openclash restart`。
9. 按上一节的表格和下面的「验证」核对。出问题按「回滚」处理。

不想用安装器，也可以按 [`docs/workflow.md`](docs/workflow.md) 手动做同样的事：备份 → 预览（`CLAUDE_CONFIG=./config.yaml ./scripts/claude_inject.sh --dry-run /path/to/current.yaml`）→ 放文件 → 重启。

## 验证

可复制的检查方向（路径按你的实机调整，不要使用仓库里的 `__PRIVATE_CONFIG__` 占位符去连机器）：

```sh
# 只读探测
./install.sh --check --config ./config.yaml

# 预览 + 临时目录里的 clash -t（不写入）
./install.sh --dry-run --config ./config.yaml

# 重启后看钩子日志：期望 fetch=skipped(offline)、verify=OK、done level=L1
tail -n 20 /etc/openclash/custom/claude_hook.log

# 运行时配置里应该有 Claude专用 组和规则
grep -c 'Claude专用' /etc/openclash/<你的配置名>.yaml
```

成功标准见「典型场景」。`bash -n` 通过或离线测试通过，都不等于生产验收通过。

## 回滚

回滚默认先检查、再执行。原则：

- 先恢复钩子到安装前备份，并核对哈希；
- 这一步失败就停止，不要继续删除凭据或缓存；
- 不自动重启；需要重启时单独确认；
- 恢复后确认自定义注入已撤、非目标策略还在、服务仍可用。

用 `--apply` 装过的话，直接跑已安装的那份：

```sh
sh /etc/openclash/custom/claude_rollback.sh           # 只检查，列出会做什么
sh /etc/openclash/custom/claude_rollback.sh --apply   # 执行
/etc/init.d/openclash restart                         # 你自己决定什么时候重启
```

[`scripts/claude_rollback.sh`](scripts/claude_rollback.sh) 会读 `.claude_backup/install.manifest`：用里面记下的原始钩子 md5 / sha256 核对 `.orig` 备份后恢复钩子，从运行时配置里剥掉注入的组、规则和节点，删掉凭据和缓存，再删掉安装器装上去、且之后没被改过的脚本。钩子恢复失败就停，后面的都不动。安装前的完整备份留在 `.claude_backup/install_<时间戳>/`。没有清单时（手动安装），需要用 `CLAUDE_STOCK_MD5`、`CLAUDE_RUN_CONFIG` 指定这次备份的哈希和路径，不要使用仓库里的占位路径。

## 原理简述

OpenClash 的自定义覆盖钩子发生在内核启动之前。钩子跑起来时，本地代理端口往往还不可用，所以启动阶段不能去拉订阅，只能读缓存；订阅更新要放在内核仍在跑的时候。流程见 [`docs/workflow.md`](docs/workflow.md)。

## 给 Agent 的口令

| 你想做的事 | 可以说 |
|---|---|
| 只检查，不改 | 「读 AGENTS.md 和 SKILL.md，只检查我的环境，不要写入或重启。」 |
| 先预览 | 「检查环境，列出将要改的文件和回滚方式，先做预览，等我确认。」 |
| 确认后才部署 | 「这是我确认过的预览。按 SKILL.md 逐步执行，一步一校验。途中出错先停下来。」 |
| 回滚 | 「按我这次的备份做回滚检查，先不要真正执行，把命令给我看。」 |

未经确认不得写入。不要代开 GitHub issue / PR，除非用户要求并看过正文。完整禁令见 [`AGENTS.md`](AGENTS.md)，逐步流程见 [`SKILL.md`](SKILL.md)。

## 配置

- 使用 [`config.example.yaml`](config.example.yaml) 复制为 `config.yaml`。注入脚本会读取 `claude.node_match` 与 `claude.alias`；缺少任一项都会拒绝执行。
- 占位符是 `__NAME__` 形式，避免尖括号在 shell 里被当成重定向。占位符不是真实值。

## 限制与已知问题

- 域名规则和 `Claude专用` 组名目前仍是项目固定的；要钉死的节点改为从配置读取。
- 未承诺兼容所有 OpenWrt / OpenClash / Mihomo 版本。历史环境：ImmortalWrt SNAPSHOT r32912，Linux 6.6.69，aarch64，Mihomo `alpha-g86257fc`。路由器型号和 OpenClash 版本在资料里未能确认。
- 启动脚本不检查钩子返回码（残项 R-04），不能宣称完整失败关闭。
- 部分后期变更缺少独立运行日志。
- 安装器目前只在离线沙盒里测过（伪造的 `/etc/openclash` 目录、真实 Mihomo `-t`、BusyBox ash），还没有在真实路由器上跑过完整的 `--apply` → 重启。第一次用请留好带外管理。
- 生效配置里需要有一个名字以「自动选择」结尾的 url-test 组，`APNs推送` 组会把它当上游；没有的话注入的结构校验通不过，`--dry-run` 会报预览未通过。
- 回滚会删除 `claude_b.yaml` 凭据和节点缓存；需要保留的话先自己备份。

## 开发与测试

给 Agent 的短规则在 [`AGENTS.md`](AGENTS.md)（Claude Code 可先读 [`CLAUDE.md`](CLAUDE.md)，它只指向前者）。离线沙盒测试：`sh tests/sandbox_test.sh`（可加 `MIHOMO_BIN=/path/to/mihomo` 用真实内核校验，`RUN_SH="busybox ash"` 用 ash 跑）。测试与部署长流程在 [`SKILL.md`](SKILL.md) 和 [`docs/workflow.md`](docs/workflow.md)。本地测试的失败日志请自行保留，不要编造仓库里没有的测试结果。

## 许可证与致谢

本项目以 [MIT License](LICENSE) 发布，版权所有 © 2026 亦然y1ran。本项目依赖并感谢 OpenWrt / ImmortalWrt、OpenClash、Mihomo 及其文档；本仓库不隶属于这些项目。
