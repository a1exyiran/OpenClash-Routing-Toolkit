# 只让 Claude 走纯净 IP，其余流量用现有的便宜线路

[![OpenWrt](https://img.shields.io/badge/OpenWrt-ImmortalWrt-blue)](#限制与已知问题)
[![OpenClash](https://img.shields.io/badge/OpenClash-custom%20hook-lightgrey)](#限制与已知问题)
[![Mihomo](https://img.shields.io/badge/Mihomo-kernel-lightgrey)](#限制与已知问题)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

仓库名 `OpenClash-Routing-Toolkit`。在你自己的 OpenWrt / ImmortalWrt 路由器上，把 Claude 的流量单独送到纯净 IP 线路，其余流量继续走更便宜的那条；订阅更新和 OpenClash 重启之后，这套分流尽量还在。失败时可以检查、可以往回退。它不替代 OpenClash 或 Mihomo，也不提供订阅。

> [!IMPORTANT]
> 只适用于你自己管理、并且已经在用 OpenClash 和 Mihomo 的机器。先预览，你确认后再写入。仓库里的示例只有占位符，请不要提交或截图真实订阅、证书、节点套餐、IP 或家用路径。`curl | bash` 不是默认安装方式，也不保证兼容所有版本。

现在能公开的是已经跑通过的方法和脚本（见 [`scripts/`](scripts/)）。通用配置解析和 Agent 安装器还在做。

## 它做什么

启动时钩子只做离线注入，订阅更新放在内核还在跑的时候。校验通过再原子替换，回滚默认先检查。实际场景是：Claude / Anthropic 自有流量走你指定的纯净 IP 出口，其余流量保持原策略。请用你自己的两条订阅和组名，不要照搬仓库里的历史对象。

这不是图形面板，也还不是可以对任意路由器一键执行的发行版。

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
请先阅读这个仓库的 AGENTS.md 和 SKILL.md，检查我的 OpenWrt/OpenClash 环境，只预览将要改动的文件，未经我确认不要写入或重启服务：https://github.com/a1exyiran/OpenClash-Routing-Toolkit
```

这句话现在就可以用来约束助手。通用安装器（读你的 `config.yaml` 并真正落地）仍为 **即将提供 / 待实现**，不要把它理解成已经能一键改路由器。只读探测可以用：

```sh
./install.sh --check
```

`--dry-run` 和 `--apply` 尚未实现，脚本会拒绝执行。不要改用 `curl | bash`。工作脚本在 [`scripts/`](scripts/)，按下面的手动安装步骤预览后再用，不要把它们当成一键安装器。

## 典型场景

对标常见网络工具的「先给能跑通的例子」。以下都是你在**自己的**路由器上、用**自己的**订阅和组名时，要能验证的事：

| 场景 | 怎样才算成功 |
|---|---|
| 订阅刚更新过 | 你注入的规则仍在规则列表前部，并指向你指定的策略组；其余规则和原策略组还在 |
| OpenClash 刚重启过 | 钩子日志为离线命中缓存（例如 `fetch=skipped(offline)`），结构校验通过；非目标流量仍走原出口 |
| 注入或订阅暂时失败 | 按设计降级，而不是 silently 落到直连或别的组（本地沙盒见过空组出现 `COMPATIBLE`；完整失败关闭仍有已知残项，见限制） |
| 决定撤掉这次改动 | 先跑回滚检查，确认原厂钩子备份校验通过，再执行恢复；不自动重启 |

## 手动安装

在 Agent 安装器落地之前，这是正经路径。详细步骤见 [`docs/workflow.md`](docs/workflow.md)。

1. 确认环境：OpenWrt / ImmortalWrt，已安装 OpenClash 与 Mihomo，知道生效配置路径；看可用内存（历史机器只有 485 MB、无 swap，内存紧张时不要强行全量 `clash -t`）。
2. 准备你自己的配置，参考 [`config.example.yaml`](config.example.yaml)。订阅放在路由器上权限收紧的单独文件里，不要写进 Git。
3. 备份：当前钩子、生效配置、`/etc/openclash/custom/` 里将被替换的文件；记下哈希。
4. 在临时目录预览构建，确认产物结构，必要时再做 `clash -t`。脚本在 [`scripts/`](scripts/)，组名和规则要改成你自己的。
5. 你确认预览无误后，再把经过核验的脚本放到自定义目录，按你的维护窗口决定是否重启。
6. 按上一节的表格做验证。

## 验证

可复制的检查方向（路径按你的实机调整，不要使用仓库里的 `__PRIVATE_CONFIG__` 占位符去连机器）：

```sh
# 只读探测（可在路由器上运行本仓库的提纲脚本）
./install.sh --check

# 内核校验示例（对预览产物，不是对未备份的生产文件）
# clash -t -d /etc/openclash -f /tmp/preview.yaml

# 启动后看钩子日志里是否离线命中缓存、校验是否通过
# logread | grep -E 'fetch=skipped|verify='
```

成功标准见「典型场景」。`bash -n` 通过或离线测试通过，都不等于生产验收通过。

## 回滚

回滚默认先检查、再执行。原则：

- 先恢复钩子到安装前备份，并核对哈希；
- 这一步失败就停止，不要继续删除凭据或缓存；
- 不自动重启；需要重启时单独确认；
- 恢复后确认自定义注入已撤、非目标策略还在、服务仍可用。

回滚检查可用 [`scripts/claude_rollback.sh`](scripts/claude_rollback.sh)，默认只检查、不修改。路径和哈希以你这次的备份为准，不要使用仓库里的占位路径。

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

- 使用 [`config.example.yaml`](config.example.yaml) 做清单。解析落地仍为待实现。
- 占位符是 `__NAME__` 形式，避免尖括号在 shell 里被当成重定向。占位符不是真实值。

## 限制与已知问题

- 历史实现仍绑着当时那一组具体规则；通用配置驱动为待实现。
- 未承诺兼容所有 OpenWrt / OpenClash / Mihomo 版本。历史环境：ImmortalWrt SNAPSHOT r32912，Linux 6.6.69，aarch64，Mihomo `alpha-g86257fc`。路由器型号和 OpenClash 版本在资料里未能确认。
- 启动脚本不检查钩子返回码（残项 R-04），不能宣称完整失败关闭。
- 部分后期变更缺少独立运行日志。
- `./install.sh --dry-run` / `--apply` 尚未实现。

## 开发与测试

给 Agent 的短规则在 [`AGENTS.md`](AGENTS.md)（Claude Code 可先读 [`CLAUDE.md`](CLAUDE.md)，它只指向前者）。测试与部署长流程在 [`SKILL.md`](SKILL.md) 和 [`docs/workflow.md`](docs/workflow.md)。本地测试的失败日志请自行保留，不要编造仓库里没有的测试结果。

## 许可证与致谢

本项目以 [MIT License](LICENSE) 发布，版权所有 © 2026 亦然y1ran。本项目依赖并感谢 OpenWrt / ImmortalWrt、OpenClash、Mihomo 及其文档；本仓库不隶属于这些项目。
