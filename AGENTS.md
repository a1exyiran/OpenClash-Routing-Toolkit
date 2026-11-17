# AGENTS.md

给所有编码助手。长流程在 [`SKILL.md`](SKILL.md) 和 [`docs/workflow.md`](docs/workflow.md)，不要把那两份抄进这里。

本仓库提供已跑通的方法、[`scripts/`](scripts/) 里的工作脚本，和分三步的安装器 `install.sh`（`--check` → `--dry-run` → `--apply`）。注入前必须有用户自己的 `config.yaml`（`claude.node_match` 与 `claude.alias`）。没有用户自己的配置、没有这一次的明确确认，就停在 `--check` / `--dry-run`。

## 硬性规则

未经用户对**这一次、这台机器、这个维护窗口**明确同意，禁止：

- 写入路由器上的任何文件，或覆盖配置
- 重启 / 重载 OpenClash，或重启路由器
- 刷新订阅，或读取、复制、打印订阅 URL、密码、UUID、证书、API secret
- 把 `__PRIVATE_CONFIG__`、`__IP_ADDRESS__` 等占位符当成真实值去连机器
- 未经预览和确认，运行 `./install.sh --apply`（尤其是加 `--yes`），或把 `scripts/` 里的脚本直接拿到生产执行，或把 `config.example.yaml` 里的示例节点名、组名、占位路径当成用户环境的默认值
- 改动用户未点名的路由、DNS、防火墙、DHCP 或其他策略组
- 代开 GitHub issue / PR、代推、代打 tag（除非用户要求并看过正文）
- 用猜测补全仓库没给出的型号、OpenClash 版本、兼容性或性能数字

验证失败、SSH 中断、状态不明或流量异常：立刻停止，报告现场，按已批准的回滚处理，不要自行扩大改动。`bash -n` 或离线测试通过，都不等于生产验收通过。

规则是陷阱，不是地图：能从代码里读到的架构不必在这里复述。只记住上面这些容易做错的事。

## 工作流（预览优先）

1. 只读检查环境（见下方命令）。缺项标「未确认」。
2. 向用户要配置文件（复制 `config.example.yaml` 为 `config.yaml`，必须填写 `claude.node_match` 与 `claude.alias`）和凭据放置方式。没有这两项就不要进入写入计划，注入脚本也会拒绝执行。
3. 给出预览：将改哪些文件、会不会重启、成功标准、回滚命令。
4. **等确认。**
5. 按 [`SKILL.md`](SKILL.md) 一步一校验地执行；任一步失败则停止。
6. 报告里区分「已执行 / 已验证 / 未验证」。

## 命令

```sh
# 只读探测（可在路由器上运行；不写文件）
./install.sh --check

# 预览：列出会改的文件、钩子新旧 sha256、备份位置；临时目录渲染 + clash -t；不写入
./install.sh --dry-run --config /path/to/config.yaml [--target /path/to/live.yaml]

# 写入：只在用户看过这次 dry-run 并明确同意后。会再预览一遍，要求输入 yes
./install.sh --apply --config /path/to/config.yaml
# 用户明确同意、且是非交互会话时才加 --yes。apply 不重启 OpenClash，重启命令交给用户

# 语法检查与离线沙盒测试
# sh -n install.sh scripts/*.sh
# sh tests/sandbox_test.sh
```

回滚：`sh /etc/openclash/custom/claude_rollback.sh`（默认只检查）。用 `--apply` 装过时它会读 `.claude_backup/install.manifest` 里的原始钩子哈希和运行配置路径。先把检查输出给用户看，确认后再加 `--apply`。不要自动重启。没有清单时，路径和哈希必须来自这次备份，不要使用仓库里的占位路径。

测试与证据：本地失败日志要保留。不要编造仓库里没有的测试结果。

## 文档指针

| 文件 | 内容 |
|---|---|
| [`README.md`](README.md) | 项目是什么、怎么开始、场景、限制 |
| [`SKILL.md`](SKILL.md) | 安装 / 排查的逐步流程和示例口令 |
| [`docs/workflow.md`](docs/workflow.md) | 环境探测表、备份与验证细节 |
| [`config.example.yaml`](config.example.yaml) | 用户配置模板；`claude.node_match` / `claude.alias` 会被注入脚本读取 |
| [`install.sh`](install.sh) | `--check` / `--dry-run` / `--apply` 安装器 |
| [`scripts/`](scripts/) | 注入、更新、回滚、覆写钩子的工作脚本 |
| [`tests/sandbox_test.sh`](tests/sandbox_test.sh) | 伪造 /etc/openclash 的离线测试 |
| [`CLAUDE.md`](CLAUDE.md) | 仅指向本文件 |
