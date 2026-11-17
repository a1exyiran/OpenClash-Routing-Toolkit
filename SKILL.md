---
name: openclash-routing-toolkit
description: 在用户自己的 OpenWrt / OpenClash / Mihomo 路由器上，预览并部署自定义分流持久化脚本；当用户要在订阅更新后保留规则、或要回滚一次失败注入时使用。先检查环境并预览，未确认不写入。触发词包括 OpenClash 分流、订阅更新后规则丢失、按 AGENTS.md 部署、routing toolkit。
---

# OpenClash Routing Toolkit — Skill

硬性禁令以根目录 [`AGENTS.md`](AGENTS.md) 为准，不要在这里放宽。细节表在 [`docs/workflow.md`](docs/workflow.md)。

## 何时使用

- 用户要在自己的 OpenWrt / OpenClash 路由器上保留自定义分流，使其在订阅更新或重启后还在；
- 用户要预览、部署或回滚一次注入；
- 用户说「读 AGENTS.md / SKILL.md 然后部署」，或把 README 里那句口令发给你。

## 先问清

1. 目标是哪台机器，你将如何登录（不要让用户把密码写进仓库或聊天记录里长期保存）。
2. 这次是否允许改配置、是否有维护窗口、是否允许重启 OpenClash。
3. 配置文件在哪（复制 `config.example.yaml` 为 `config.yaml`，必须有 `claude.node_match` 与 `claude.alias`）。没有这两项就只做环境检查，不进入写入计划。
4. 订阅 / 凭据文件由用户自己放置；你只检查存在与权限，不把内容读到对话里。

## 流程

### 1. 检查环境（只读）

运行或按 [`docs/workflow.md`](docs/workflow.md) 收集：是否为 OpenWrt / ImmortalWrt、架构、内存与 swap、OpenClash 是否安装、生效配置路径、Mihomo 二进制、Ruby、断网后是否还有带外管理。缺的标「未确认」。不要为了探测而重启服务。把报告给用户看，然后停下。

可用：`./install.sh --check --config <config.yaml>`。

### 2. 预览将要改动的文件

列出完整路径、将安装或替换的脚本、会不会重启、成功标准、回滚命令。若能在临时目录构建产物，做结构检查；内存足够时才建议全量 `clash -t`。

用 `./install.sh --dry-run --config <config.yaml> [--target <生效配置>]`。它列出将安装 / 替换的文件、钩子新旧 sha256、apply 会做的备份、缓存与凭据状态，在 `/tmp` 临时目录渲染注入结果，内存够时跑 `clash -t`，不写 OpenClash 目录。把输出原样给用户看。`build=reject` 表示还没有节点缓存；`预览未通过` 就停下排查，不要进入写入。不要用 `curl | bash` 绕过预览。

### 3. 等确认

没有用户对这一次预览的明确同意，不要写入，不要重启，不要打开凭据内容。

### 4. 部署（仅在用户确认后）

`./install.sh --apply --config <config.yaml>`：它会再预览一遍，用户输入 `yes` 才写入（非交互会话只有在用户明确同意后才加 `--yes`）。它备份钩子与生效配置并记 sha256、装脚本、接钩子、写 `.claude_backup/install.manifest`、做校验，**不重启**。凭据仍由用户放置。没有节点缓存时，在内核运行中先跑一次 `claude_update.sh`。重启 `/etc/init.d/openclash restart` 只在用户同意的维护窗口、由用户确认后执行。任一步失败则停止，按第 6 步回滚。

### 5. 验证

对照 README 里的场景表：规则是否还在、钩子是否离线命中缓存、非目标流量是否仍走原策略。报告中区分已执行 / 已验证 / 未验证。

### 6. 失败则回滚

先跑 `sh /etc/openclash/custom/claude_rollback.sh`（只检查），把输出给用户看，确认后再加 `--apply`。它按 install.manifest 核对原始钩子备份的哈希后恢复钩子；失败就停，不继续删凭据或缓存。不自动重启。没有清单时，哈希和路径必须来自这次备份，不能来自仓库里写死的占位路径。

## 常见坑

- 钩子发生在内核启动前，启动阶段不能拉订阅。
- 空的策略组在某些内核里可能出现 `COMPATIBLE`（本地沙盒证据；与生产内核版本可能不同）。
- 锁竞态：宁可这次不注入，也不要和活着的持有者一起写。
- 全量 `clash -t` 需要足够内存和正确的 `SAFE_PATHS`。
- 启动脚本不检查钩子返回码（R-04），失败不等于自动停机。
- 占位符和 `config.example.yaml` 里的示例节点不是可部署配置。`Claude专用` 是项目功能组名；要钉死的节点必须由用户的 `claude.node_match` / `claude.alias` 提供。

## 示例口令

- 「只检查我的 OpenWrt/OpenClash 环境，不要写入或重启。」
- 「列出将要改的文件和回滚方式，先做预览，等我确认。」
- 「这是我确认过的预览，按 SKILL.md 逐步执行，出错先停。」
- 「按我这次的备份做回滚检查，先不要真正执行。」
