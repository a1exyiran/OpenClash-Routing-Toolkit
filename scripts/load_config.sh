#!/bin/sh
# load_config.sh — 读取 claude.node_match / claude.alias
#
# 由同目录的脚本 source：
#   SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
#   # shellcheck source=load_config.sh
#   . "$SCRIPT_DIR/load_config.sh"
#   toolkit_require_config   # 缺项则以非 0 退出
#   toolkit_load_config      # 缺项返回 1，不退出
#
# 查找顺序：
#   1. $CLAUDE_CONFIG（若已设置，必须是可读文件）
#   2. $CLAUDE_CFG_DIR/config.yaml
#   3. 本脚本所在目录的上一级 /config.yaml（仓库根目录）
#   4. 本脚本所在目录 /config.yaml
#
# 不会自动使用 config.example.yaml。示例值必须先复制为 config.yaml。
# 若环境变量 CLAUDE_NODE_MATCH 与 CLAUDE_ALIAS 都已设置，可作为覆盖使用。
#
# 成功后导出：CLAUDE_CONFIG（若来自文件）、CLAUDE_NODE_MATCH、CLAUDE_ALIAS

_toolkit_lib_dir=$(CDPATH= cd -- "$(dirname -- "${TOOLKIT_SCRIPT_DIR:-$0}")" 2>/dev/null && pwd) || _toolkit_lib_dir=""

toolkit_config_path() {
  if [ -n "${CLAUDE_CONFIG:-}" ]; then
    printf '%s' "$CLAUDE_CONFIG"
    return 0
  fi
  if [ -n "${CLAUDE_CFG_DIR:-}" ] && [ -f "$CLAUDE_CFG_DIR/config.yaml" ]; then
    printf '%s' "$CLAUDE_CFG_DIR/config.yaml"
    return 0
  fi
  if [ -n "$_toolkit_lib_dir" ] && [ -f "$_toolkit_lib_dir/../config.yaml" ]; then
    printf '%s' "$_toolkit_lib_dir/../config.yaml"
    return 0
  fi
  if [ -n "$_toolkit_lib_dir" ] && [ -f "$_toolkit_lib_dir/config.yaml" ]; then
    printf '%s' "$_toolkit_lib_dir/config.yaml"
    return 0
  fi
  return 1
}

_toolkit_help() {
  cat >&2 <<'HINT'
请复制 config.example.yaml 为 config.yaml，填写：

  claude:
    node_match: "美国01"     # Ruby 正则，必须恰好命中一个订阅节点名
    alias: "Claude-Node"    # 改名后的显示名，会成为 Claude专用 组的首位

然后任选一种方式提供该文件：
  - 环境变量 CLAUDE_CONFIG=/path/to/config.yaml
  - 放到 $CLAUDE_CFG_DIR/config.yaml（默认 /etc/openclash/custom/config.yaml）
  - 放到仓库根目录的 config.yaml（不要提交）

HINT
}

# 返回 0 并导出变量；失败返回非 0（不 exit）
toolkit_load_config() {
  _ruby="${CLAUDE_RUBY:-ruby}"
  _cfg=""
  if _cfg=$(toolkit_config_path); then
    if [ ! -f "$_cfg" ] || [ ! -r "$_cfg" ]; then
      echo "ERROR: 配置文件不可读：$_cfg" >&2
      return 2
    fi
    CLAUDE_CONFIG=$(CDPATH= cd -- "$(dirname -- "$_cfg")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename -- "$_cfg")")
    export CLAUDE_CONFIG
  else
    _cfg=""
  fi

  # 环境变量已齐且无文件时，仍做校验
  if [ -z "$_cfg" ] && [ -n "${CLAUDE_NODE_MATCH:-}" ] && [ -n "${CLAUDE_ALIAS:-}" ]; then
    _cfg=""
  elif [ -z "$_cfg" ]; then
    return 1
  fi

  if ! "$_ruby" -e 'exit 0' >/dev/null 2>&1; then
    echo "ERROR: 需要 Ruby（psych）才能读取配置。请安装 ruby，或设置 CLAUDE_RUBY。" >&2
    return 2
  fi

  _parsed=$("$_ruby" -ryaml -E UTF-8 -e '
reserved = %w[DIRECT REJECT REJECT-DROP PASS GLOBAL COMPATIBLE Claude专用 ClaudeAuto APNs推送]
path = ARGV[0]
env_match = ENV["CLAUDE_NODE_MATCH"].to_s.strip
env_alias = ENV["CLAUDE_ALIAS"].to_s.strip
match = env_match
alis  = env_alias
if path && !path.empty? && File.file?(path)
  begin
    d = Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
  rescue Exception => e
    warn "ERROR: 无法解析配置文件 #{path}（#{e.class}）"
    exit 3
  end
  unless d.is_a?(Hash)
    warn "ERROR: 配置文件根节点必须是映射：#{path}"
    exit 3
  end
  c = d["claude"]
  unless c.is_a?(Hash)
    warn "ERROR: 配置缺少 claude: 段（需要 claude.node_match 与 claude.alias）：#{path}"
    exit 3
  end
  # 环境变量优先，便于一次性覆盖
  match = env_match.empty? ? c["node_match"].to_s.strip : env_match
  alis  = env_alias.empty? ? c["alias"].to_s.strip : env_alias
end
if match.empty? || alis.empty?
  warn "ERROR: 未配置 claude.node_match 或 claude.alias。"
  exit 3
end
if alis.include?("\n") || match.include?("\n")
  warn "ERROR: claude.node_match / claude.alias 不能包含换行。"
  exit 3
end
if reserved.include?(alis)
  warn "ERROR: claude.alias 不能使用保留名 #{alis}。"
  exit 3
end
begin
  Regexp.new(match)
rescue RegexpError => e
  warn "ERROR: claude.node_match 不是合法的 Ruby 正则：#{e.message}"
  exit 3
end
require "shellwords"
puts "CLAUDE_NODE_MATCH=#{Shellwords.escape(match)}"
puts "CLAUDE_ALIAS=#{Shellwords.escape(alis)}"
' "${_cfg}") || return 3

  eval "$_parsed" || return 3
  export CLAUDE_NODE_MATCH CLAUDE_ALIAS
  return 0
}

toolkit_require_config() {
  toolkit_load_config
  _rc=$?
  if [ "$_rc" -eq 0 ]; then
    return 0
  fi
  if [ "$_rc" -eq 1 ]; then
    echo "ERROR: 未找到配置文件，拒绝继续（节点匹配规则不能使用内置默认值）。" >&2
    _toolkit_help
  fi
  return "$_rc"
}
