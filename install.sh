#!/bin/sh
# OpenClash Routing Toolkit — installer
#
# 用法：
#   ./install.sh --help
#   ./install.sh --check   [--config FILE]                  只读探测
#   ./install.sh --dry-run  --config FILE [--target FILE] [--fetch]
#                                                           预览：列出会改哪些文件，在临时目录渲染注入后的配置并做内核校验
#   ./install.sh --apply    --config FILE [--target FILE] [--yes]
#                                                           确认后写入：备份 → 安装脚本 → 接上覆写钩子 → 校验
#
# 约束：
#   · --check / --dry-run 不写 OpenClash 目录下的任何文件，只用 /tmp 下的临时目录（结束即删）
#   · --apply 必须交互输入 yes，或显式加 --yes；非交互且没有 --yes 时直接退出
#   · 从不重启 / 重载 OpenClash，只打印重启命令
#   · 不读取、不打印订阅地址；凭据文件只检查是否存在与权限
#   · POSIX sh（BusyBox ash 可用），依赖：ruby（psych）、sha256sum、md5sum、awk
#
# 测试用环境变量（正常使用不需要）：
#   OPENCLASH_ROOT   默认 /etc/openclash
#   OPENCLASH_INIT   默认 /etc/init.d/openclash
#   CLAUDE_CFG_DIR   覆盖自定义目录（默认取 config.yaml 的 openclash.custom_dir，再退回 $OPENCLASH_ROOT/custom）

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

VERSION="1.0"
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SELF_DIR/scripts"
OC_ROOT="${OPENCLASH_ROOT:-/etc/openclash}"
OC_INIT="${OPENCLASH_INIT:-/etc/init.d/openclash}"
TOOLKIT_FILES="load_config.sh claude_inject.sh claude_update.sh claude_rollback.sh"
HOOK_NAME="openclash_custom_overwrite.sh"
MARK_BEGIN="# >>> openclash-routing-toolkit (install.sh) >>>"
BLOCK_TITLE="Claude 专属出口注入"
RUBY_BIN="${CLAUDE_RUBY:-ruby}"

usage() {
  cat <<'USAGE'
OpenClash Routing Toolkit installer

  --check [--config FILE]
        只读探测：系统、内存、OpenClash 目录、内核、Ruby、钩子状态、配置键。
  --dry-run --config FILE [--target FILE] [--fetch]
        预览：列出将安装 / 替换的文件、钩子改动、备份位置和缓存路径；
        在临时目录渲染注入后的配置，内核存在且内存够时跑 clash -t。
        不写 OpenClash 目录。默认只读缓存（与开机钩子一致），--fetch 改为经本机代理拉一次订阅。
  --apply --config FILE [--target FILE] [--yes]
        先做一遍和 --dry-run 相同的预览，确认后：备份钩子与生效配置（记 sha256）、
        安装 scripts/、接上覆写钩子、校验。不重启 OpenClash。
  --target FILE   生效配置路径。默认取 config.yaml 的 openclash.config_path，再退回 uci。
  --yes           跳过交互确认（只在你已看过同一份预览时使用）。

推荐顺序：--check → --dry-run → --apply → 手动重启 → 验证；出问题用 scripts/claude_rollback.sh。
USAGE
}

have() { command -v "$1" >/dev/null 2>&1; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
die() { _c="$1"; shift; echo "ERROR: $*" >&2; exit "$_c"; }
perm_of() { ls -ld "$1" 2>/dev/null | cut -c1-10; }

WORK=""
LOCK=""
cleanup() {
  [ -n "$WORK" ] && rm -rf "$WORK"
  [ -n "$LOCK" ] && rmdir "$LOCK" 2>/dev/null
  return 0
}
trap cleanup 0
trap 'exit 130' INT TERM

# ------------------------------------------------------------------ check
cmd_check() {
  echo "== only-read probe  $(date '+%F %T' 2>/dev/null || true)"
  echo "-- os"
  if [ -f /etc/openwrt_release ]; then
    grep -E '^(DISTRIB_ID|DISTRIB_RELEASE|DISTRIB_REVISION)=' /etc/openwrt_release 2>/dev/null
  elif [ -f /etc/os-release ]; then
    grep -E '^(ID|NAME|VERSION)=' /etc/os-release
  else
    echo "unconfirmed: not an OpenWrt-like os-release layout"
  fi
  echo "-- kernel / arch"
  uname -a 2>/dev/null || echo "unconfirmed: uname"
  echo "-- memory"
  if [ -r /proc/meminfo ]; then
    grep -E '^(MemTotal|MemAvailable|SwapTotal):' /proc/meminfo
  else
    echo "unconfirmed: /proc/meminfo"
  fi
  echo "-- openclash"
  if [ -x "$OC_INIT" ]; then echo "init: $OC_INIT exists"; else echo "unconfirmed: $OC_INIT not found"; fi
  if [ -d "$OC_ROOT" ]; then echo "dir: $OC_ROOT exists"; else echo "unconfirmed: $OC_ROOT not found"; fi
  _core=""
  for _c in "$OC_ROOT/core/clash_meta" "$OC_ROOT/clash"; do
    [ -x "$_c" ] && { _core="$_c"; break; }
  done
  if [ -n "$_core" ]; then
    echo "core: $_core"
    "$_core" -v 2>/dev/null | head -n 1 || true
  else
    echo "unconfirmed: Mihomo/clash binary not found at common paths"
  fi
  _cd="${CLAUDE_CFG_DIR:-$OC_ROOT/custom}"
  _h="$_cd/$HOOK_NAME"
  if [ -f "$_h" ]; then
    if grep -qF "$MARK_BEGIN" "$_h" 2>/dev/null; then
      echo "hook: $_h (toolkit installed by install.sh)"
    elif grep -qF "$BLOCK_TITLE" "$_h" 2>/dev/null; then
      echo "hook: $_h (contains a manual toolkit block, no install.sh marker)"
    else
      echo "hook: $_h (no toolkit block)"
    fi
    echo "  sha256=$(sha "$_h")"
  else
    echo "unconfirmed: hook $_h not found"
  fi
  [ -f "$_cd/.claude_backup/install.manifest" ] && echo "manifest: $_cd/.claude_backup/install.manifest"
  if [ -e "$_cd/claude_b.yaml" ]; then
    echo "credential: $_cd/claude_b.yaml present ($(perm_of "$_cd/claude_b.yaml"); content not read)"
  else
    echo "credential: $_cd/claude_b.yaml not present (needed later for claude_update.sh)"
  fi
  if have uci; then
    _p=$(uci -q get openclash.config.config_path 2>/dev/null || true)
    [ -n "$_p" ] && echo "uci config_path: $_p"
  fi
  echo "-- ruby"
  if have "$RUBY_BIN"; then "$RUBY_BIN" -v; else echo "unconfirmed: ruby not in PATH"; fi
  echo "-- toolkit config (claude.node_match / claude.alias)"
  _cfg="${CONFIG:-${CLAUDE_CONFIG:-}}"
  if [ -z "$_cfg" ] && [ -f ./config.yaml ]; then _cfg=./config.yaml; fi
  if [ -z "$_cfg" ]; then
    echo "unconfirmed: no config.yaml given (pass --config FILE, or set CLAUDE_CONFIG)"
    echo "  required keys: claude.node_match, claude.alias  (see config.example.yaml)"
  elif [ ! -f "$_cfg" ]; then
    echo "missing: $_cfg"
  elif have "$RUBY_BIN"; then
    "$RUBY_BIN" -ryaml -E UTF-8 -e '
path = ARGV[0]
begin
  d = Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
rescue Exception => e
  puts "parse_error: #{path} (#{e.class})"
  exit 0
end
c = d.is_a?(Hash) ? d["claude"] : nil
unless c.is_a?(Hash)
  puts "missing keys: claude.node_match, claude.alias  (#{path} has no claude: section)"
  exit 0
end
m = c["node_match"].to_s.strip
a = c["alias"].to_s.strip
miss = []
miss << "claude.node_match" if m.empty?
miss << "claude.alias" if a.empty?
if miss.empty?
  begin
    Regexp.new(m)
    puts "ok: #{path}"
    puts "  claude.node_match=#{m}"
    puts "  claude.alias=#{a}"
  rescue RegexpError => e
    puts "invalid: claude.node_match is not a valid Ruby regexp (#{e.message})"
  end
else
  puts "missing keys: #{miss.join(", ")}  in #{path}"
end
' "$_cfg"
  else
    echo "found: $_cfg (ruby not available, keys not parsed)"
  fi
  echo
  echo "check finished. no files were written."
  echo "next: ./install.sh --dry-run --config FILE"
}

# ------------------------------------------------------------------ 准备
load_settings() {
  have "$RUBY_BIN" || die 2 "需要 ruby（psych）。"
  _cfg="${CONFIG:-${CLAUDE_CONFIG:-}}"
  if [ -z "$_cfg" ] && [ -f ./config.yaml ]; then _cfg=./config.yaml; fi
  [ -n "$_cfg" ] || die 2 "缺少 --config FILE（复制 config.example.yaml 为 config.yaml 并填写 claude.node_match / claude.alias）。"
  [ -f "$_cfg" ] && [ -r "$_cfg" ] || die 2 "配置文件不可读：$_cfg"
  CLAUDE_CONFIG=$(CDPATH='' cd -- "$(dirname -- "$_cfg")" && printf '%s/%s' "$(pwd)" "$(basename -- "$_cfg")")
  export CLAUDE_CONFIG
  TOOLKIT_SCRIPT_DIR="$SRC_DIR/load_config.sh"
  # shellcheck source=scripts/load_config.sh
  . "$SRC_DIR/load_config.sh"
  toolkit_require_config || exit $?

  _kv=$("$RUBY_BIN" -ryaml -rshellwords -E UTF-8 -e '
d = Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true) rescue {}
d = {} unless d.is_a?(Hash)
oc = d["openclash"].is_a?(Hash) ? d["openclash"] : {}
dp = d["deploy"].is_a?(Hash) ? d["deploy"] : {}
v = {
  "Y_CONFIG_PATH" => oc["config_path"].to_s.strip,
  "Y_CUSTOM_DIR"  => oc["custom_dir"].to_s.strip,
  "Y_CORE_PATH"   => oc["core_path"].to_s.strip,
  "Y_MIN_MEM"     => dp["min_mem_available_mb"].to_s.strip,
}
v.each { |k, x| abort "E_NEWLINE #{k}" if x.include?("\n"); puts "#{k}=#{Shellwords.escape(x)}" }
' "$CLAUDE_CONFIG") || die 2 "无法读取 openclash / deploy 段：$CLAUDE_CONFIG"
  eval "$_kv"

  CFG_DIR="${CLAUDE_CFG_DIR:-}"
  [ -n "$CFG_DIR" ] || CFG_DIR="${Y_CUSTOM_DIR:-$OC_ROOT/custom}"
  CORE_BIN="${Y_CORE_PATH:-$OC_ROOT/core/clash_meta}"
  MIN_MEM="${Y_MIN_MEM:-190}"
  case "$MIN_MEM" in ''|*[!0-9]*) MIN_MEM=190 ;; esac
  case "$CFG_DIR" in *' '*|*'	'*) die 2 "自定义目录路径不能含空白：$CFG_DIR" ;; esac
  HOOK="$CFG_DIR/$HOOK_NAME"
  BAKDIR="$CFG_DIR/.claude_backup"
  HOOK_ORIG="$BAKDIR/$HOOK_NAME.orig"
  MANIFEST="$BAKDIR/install.manifest"

  # 生效配置：--target > openclash.config_path > uci
  LIVE_SRC="${TARGET:-$Y_CONFIG_PATH}"
  if [ -z "$LIVE_SRC" ] && have uci; then
    LIVE_SRC=$(uci -q get openclash.config.config_path 2>/dev/null || true)
  fi
  [ -n "$LIVE_SRC" ] || die 2 "找不到生效配置。请用 --target FILE 指定，或在 config.yaml 填 openclash.config_path。"
  [ -f "$LIVE_SRC" ] || die 2 "生效配置不存在：$LIVE_SRC"
  # OpenClash 运行时副本：/etc/openclash/<同名>.yaml，钩子改的是它
  LIVE_RUN=""
  _rb="$OC_ROOT/$(basename -- "$LIVE_SRC")"
  if [ "$_rb" != "$LIVE_SRC" ] && [ -f "$_rb" ]; then LIVE_RUN="$_rb"; fi
  BASE_CFG="${LIVE_RUN:-$LIVE_SRC}"
  RUN_FOR_ROLLBACK="${LIVE_RUN:-$OC_ROOT/$(basename -- "$LIVE_SRC")}"

  [ -d "$CFG_DIR" ] || die 2 "OpenClash 自定义目录不存在：$CFG_DIR（OpenClash 是否已安装？）"
  [ -f "$HOOK" ] || die 2 "覆写钩子不存在：$HOOK（OpenClash 是否已安装？）"
  for _f in $TOOLKIT_FILES $HOOK_NAME; do
    [ -r "$SRC_DIR/$_f" ] || die 2 "仓库文件缺失：$SRC_DIR/$_f"
  done
  WORK=$(mktemp -d /tmp/octk_install.XXXXXX) || die 3 "mktemp 失败"
  chmod 700 "$WORK"
}

# 构建新钩子：原始钩子（去掉结尾的 exit 0）+ 仓库里的 Claude 注入段
build_hook() {
  _base="$1"; _out="$2"
  _start=$(grep -n "$BLOCK_TITLE" "$SRC_DIR/$HOOK_NAME" | head -n 1 | cut -d: -f1)
  [ -n "$_start" ] || return 1
  _start=$((_start - 1))
  awk '{ l[NR] = $0 }
       END {
         n = NR
         while (n > 0 && l[n] ~ /^[ \t]*$/) n--
         if (n > 0 && l[n] ~ /^[ \t]*exit[ \t]+0[ \t]*$/) n--
         for (i = 1; i <= n; i++) print l[i]
       }' "$_base" > "$_out" || return 1
  {
    echo ""
    echo "$MARK_BEGIN"
    echo "# 以下由 install.sh 追加；原始钩子备份在 .claude_backup/$HOOK_NAME.orig"
    echo "# 撤销：sh $CFG_DIR/claude_rollback.sh（先检查）→ --apply"
    # shellcheck disable=SC2016
    echo 'CONFIG_FILE="${CONFIG_FILE:-${1:-}}"'
    # shellcheck disable=SC2016
    echo 'LOG_FILE="${LOG_FILE:-/tmp/openclash.log}"'
    awk -v s="$_start" 'NR >= s' "$SRC_DIR/$HOOK_NAME"
  } >> "$_out" || return 1
  sh -n "$_out" 2>/dev/null
}

# 依据当前钩子状态决定基底
pick_hook_base() {
  HOOK_STATE=stock
  HOOK_BASE="$HOOK"
  NEED_ORIG=1
  if grep -qF "$MARK_BEGIN" "$HOOK"; then
    HOOK_STATE=installed
  elif grep -qF "$BLOCK_TITLE" "$HOOK"; then
    HOOK_STATE=manual
  fi
  if [ "$HOOK_STATE" != stock ]; then
    [ -f "$HOOK_ORIG" ] || die 4 "钩子里已有注入段，但找不到原始备份 $HOOK_ORIG，无法安全重建。请先人工恢复原厂钩子。"
    if [ -f "$HOOK_ORIG.md5" ] && [ "$(cat "$HOOK_ORIG.md5")" != "$(md5 "$HOOK_ORIG")" ]; then
      die 4 "原始钩子备份校验不符：$HOOK_ORIG（与 .md5 记录不一致），拒绝继续。"
    fi
    HOOK_BASE="$HOOK_ORIG"
    NEED_ORIG=0
  fi
}

file_action() {
  # $1 源 $2 目标 → new / replace / unchanged
  if [ ! -e "$2" ]; then echo new
  elif [ "$(sha "$1")" = "$(sha "$2")" ]; then echo unchanged
  else echo replace
  fi
}

summarize_cfg() {
  "$RUBY_BIN" -ryaml -E UTF-8 -e '
def c(p)
  d = Psych.safe_load(File.read(p), permitted_classes: [], permitted_symbols: [], aliases: true)
  d = {} unless d.is_a?(Hash)
  [(d["proxies"] || []).size, (d["proxy-groups"] || []).size, (d["rules"] || []).size, d]
end
a = c(ARGV[0]); b = c(ARGV[1])
puts "   proxies #{a[0]} -> #{b[0]}, proxy-groups #{a[1]} -> #{b[1]}, rules #{a[2]} -> #{b[2]}"
sel = (b[3]["proxy-groups"] || []).find { |g| g.is_a?(Hash) && g["name"] == "Claude专用" }
puts "   Claude专用 = #{(sel && sel["proxies"] || []).first(3).join(", ")}#{(sel && sel["proxies"].to_a.size > 3) ? ", ..." : ""}"
puts "   前 9 条规则："
(b[3]["rules"] || []).first(9).each { |r| puts "     #{r}" }
' "$1" "$2" 2>/dev/null || echo "   (摘要生成失败)"
}

# ------------------------------------------------------------------ 预览（dry-run 与 apply 共用）
plan() {
  pick_hook_base
  build_hook "$HOOK_BASE" "$WORK/hook.new" || die 4 "构建新钩子失败（语法检查未通过）"
  NEW_HOOK_SHA=$(sha "$WORK/hook.new")
  PLAN_HOOK_SHA=$(sha "$HOOK")
  CHANGES=0

  echo "== install.sh $VERSION  mode=$MODE  $(date '+%F %T')"
  echo "-- 配置"
  echo "   config     : $CLAUDE_CONFIG"
  echo "   node_match : $CLAUDE_NODE_MATCH"
  echo "   alias      : $CLAUDE_ALIAS"
  echo "   custom dir : $CFG_DIR"
  echo "   生效配置   : $LIVE_SRC"
  [ -n "$LIVE_RUN" ] && echo "   运行时副本 : $LIVE_RUN（钩子在 OpenClash 启动时改写它）"

  echo "-- 将安装 / 替换的文件"
  for _f in $TOOLKIT_FILES; do
    _a=$(file_action "$SRC_DIR/$_f" "$CFG_DIR/$_f")
    [ "$_a" = unchanged ] || CHANGES=$((CHANGES + 1))
    printf '   %-9s %s\n' "$_a" "$CFG_DIR/$_f"
  done
  _a=$(file_action "$CLAUDE_CONFIG" "$CFG_DIR/config.yaml")
  [ "$_a" = unchanged ] || CHANGES=$((CHANGES + 1))
  printf '   %-9s %s  (权限 600)\n' "$_a" "$CFG_DIR/config.yaml"
  if [ "$(sha "$HOOK")" = "$NEW_HOOK_SHA" ]; then
    _a=unchanged
  else
    _a=modify; CHANGES=$((CHANGES + 1))
  fi
  printf '   %-9s %s\n' "$_a" "$HOOK"
  echo "             当前状态=$HOOK_STATE  当前 sha256=$(sha "$HOOK")"
  echo "             新钩子 = $( [ "$HOOK_BASE" = "$HOOK" ] && echo 当前钩子 || echo 原始备份 )去掉结尾 exit 0 + Claude 注入段，sha256=$NEW_HOOK_SHA"

  echo "-- apply 会做的备份"
  echo "   $BAKDIR/install_<时间戳>/   当前钩子、生效配置、将被替换的文件；SHA256SUMS 记哈希，ORIGINS 记原路径"
  if [ "$NEED_ORIG" -eq 1 ]; then
    echo "   $HOOK_ORIG（+ .md5 / .sha256）  原始钩子，rollback 用它恢复"
  else
    echo "   $HOOK_ORIG 已存在，保持不动（md5 $(md5 "$HOOK_ORIG")）"
  fi
  echo "   $MANIFEST  记录本次安装的文件与哈希"

  echo "-- 运行期路径（不由 install 创建）"
  echo "   缓存   : $CFG_DIR/claude_cache/nodes.yaml, meta.txt  $( [ -s "$CFG_DIR/claude_cache/nodes.yaml" ] && echo '(已存在)' || echo '(尚无，首次需 claude_update.sh 拉取)')"
  if [ -e "$CFG_DIR/claude_b.yaml" ]; then
    echo "   凭据   : $CFG_DIR/claude_b.yaml 存在，权限 $(perm_of "$CFG_DIR/claude_b.yaml")（内容未读取）"
  else
    echo "   凭据   : $CFG_DIR/claude_b.yaml 不存在（由你自己放，内容 url: ...，chmod 600）"
  fi
  echo "   日志   : $CFG_DIR/claude_hook.log, /tmp/claude_inject.log"
  echo "   不会改 : 生效配置本身、DNS、防火墙、crontab；不重启 OpenClash"

  # 渲染
  echo "-- 渲染注入后的配置（临时目录）"
  cp "$BASE_CFG" "$WORK/base.yaml" || die 3 "复制生效配置失败"
  mkdir -p "$WORK/bak"
  if [ "$FETCH" -eq 1 ]; then
    _imode=--dry-run
    echo "   来源：经本机代理拉取订阅（--fetch）"
  else
    _imode=--offline
    echo "   来源：只读缓存（与开机钩子相同）"
  fi
  cp "$WORK/base.yaml" "$WORK/render.yaml"
  CLAUDE_CFG_DIR="$CFG_DIR" CLAUDE_BACKUP_DIR="$WORK/bak" CLAUDE_LOG="$WORK/inject.log" \
    CLAUDE_DRYRUN_OUT="$WORK/render.yaml" CLAUDE_VERIFY_CORE=0 \
    sh "$SRC_DIR/claude_inject.sh" "$_imode" "$WORK/render.yaml" > "$WORK/inject.out" 2>&1
  RENDER_RC=$?
  grep -E 'fetch=|cache=|parse=|rename=|build mode=|verify|ERROR|E_' "$WORK/inject.out" | sed 's/^/   | /'
  BUILD_MODE=$(sed -n 's/.*--- build mode=\([a-z-]*\).*/\1/p' "$WORK/inject.out" | tail -n 1)
  grep -q 'fallback to reject-only\|退回 REJECT-only' "$WORK/inject.out" && BUILD_MODE=reject
  if [ "$RENDER_RC" -ne 0 ]; then
    echo "   渲染失败 rc=$RENDER_RC"
  else
    echo "   渲染完成 build=$BUILD_MODE"
    summarize_cfg "$WORK/base.yaml" "$WORK/render.yaml"
  fi

  # 内核校验
  CORE_RESULT=SKIPPED
  if [ "$RENDER_RC" -ne 0 ]; then
    CORE_RESULT="SKIPPED(渲染失败)"
  elif [ ! -x "$CORE_BIN" ]; then
    CORE_RESULT="SKIPPED(找不到内核 $CORE_BIN)"
  else
    _avail=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
    _avail=${_avail:-0}
    if [ "$_avail" -lt "$MIN_MEM" ]; then
      CORE_RESULT="SKIPPED(MemAvailable ${_avail}MB < ${MIN_MEM}MB)"
    else
      mkdir -p "$WORK/vd"
      for _g in Country.mmdb GeoSite.dat GeoIP.dat ASN.mmdb; do
        [ -f "$OC_ROOT/$_g" ] && ln -sf "$OC_ROOT/$_g" "$WORK/vd/$_g"
      done
      if have timeout; then
        GOGC=20 timeout 120 "$CORE_BIN" -t -d "$WORK/vd" -f "$WORK/render.yaml" > "$WORK/core.log" 2>&1
      else
        GOGC=20 "$CORE_BIN" -t -d "$WORK/vd" -f "$WORK/render.yaml" > "$WORK/core.log" 2>&1
      fi
      if grep -q 'test is successful' "$WORK/core.log"; then
        CORE_RESULT=PASS
      else
        CORE_RESULT=FAIL
        tail -n 3 "$WORK/core.log" | sed 's/^/   | /'
      fi
    fi
  fi
  echo "   clash -t: $CORE_RESULT"

  PLAN_OK=1
  [ "$RENDER_RC" -eq 0 ] || PLAN_OK=0
  [ "$CORE_RESULT" = FAIL ] && PLAN_OK=0
  echo "-- 结论"
  echo "   需要改动的文件数：$CHANGES"
  if [ "$PLAN_OK" -eq 1 ]; then echo "   预览通过"; else echo "   预览未通过，apply 会拒绝执行"; fi
  if [ "$BUILD_MODE" = reject ]; then
    echo "   注意：当前没有可用节点缓存，重启后 Claude 流量会先被 REJECT（不会漏到其他线路），"
    echo "         内核起来后运行 claude_update.sh 拉取节点即可恢复。"
  fi
}

# ------------------------------------------------------------------ apply
copy_verified() {
  # $1 src $2 dst $3 mode → 原子替换并校验 sha256
  _tmp="$2.octk.$$"
  cp "$1" "$_tmp" && chmod "$3" "$_tmp" && mv -f "$_tmp" "$2" || { rm -f "$_tmp"; return 1; }
  [ "$(sha "$1")" = "$(sha "$2")" ]
}

backup_one() {
  # $1 原路径 $2 备份文件名
  [ -f "$1" ] || return 0
  cp -p "$1" "$BK/$2" || return 1
  _s=$(sha "$1")
  [ "$_s" = "$(sha "$BK/$2")" ] || return 1
  printf '%s  %s\n' "$_s" "$2" >> "$BK/SHA256SUMS"
  printf '%s %s\n' "$2" "$1" >> "$BK/ORIGINS"
}

cmd_apply() {
  if [ "$PLAN_OK" -ne 1 ]; then
    echo "ERROR: 预览未通过，拒绝写入。" >&2
    exit 4
  fi
  if [ "$CHANGES" -eq 0 ]; then
    echo ""
    echo "全部文件已是目标版本，无需写入（不创建新备份）。"
    print_next
    exit 0
  fi
  echo ""
  if [ "$ASSUME_YES" -eq 1 ]; then
    echo "已加 --yes，按上面的预览写入。"
  elif [ -t 0 ]; then
    printf '确认按上面的预览写入？输入 yes 继续，其他任意输入取消：'
    read -r _ans || _ans=""
    [ "$_ans" = yes ] || { echo "已取消，未写入任何文件。"; exit 5; }
  else
    echo "非交互环境且没有 --yes，已取消，未写入任何文件。" >&2
    exit 5
  fi

  LOCK="/tmp/.octk_install.lock"
  mkdir "$LOCK" 2>/dev/null || { LOCK=""; die 6 "另一个 install.sh 正在运行（/tmp/.octk_install.lock）。"; }

  # 预览之后（等确认期间）钩子若被改过，停止
  _hook_sha_now=$(sha "$HOOK")
  [ "$_hook_sha_now" = "$PLAN_HOOK_SHA" ] || die 6 "钩子在预览之后被改动，未写入任何文件。请重新运行 --dry-run。"

  mkdir -p "$BAKDIR" && chmod 700 "$BAKDIR" || die 7 "无法创建备份目录 $BAKDIR"
  BK="$BAKDIR/install_$(date '+%Y%m%d-%H%M%S')_$$"
  mkdir "$BK" && chmod 700 "$BK" || die 7 "无法创建 $BK"
  : > "$BK/SHA256SUMS"
  : > "$BK/ORIGINS"

  echo "-- 备份 → $BK"
  backup_one "$HOOK" "$HOOK_NAME" || die 7 "备份钩子失败"
  backup_one "$LIVE_SRC" "live_$(basename -- "$LIVE_SRC")" || die 7 "备份生效配置失败"
  if [ -n "$LIVE_RUN" ]; then
    backup_one "$LIVE_RUN" "run_$(basename -- "$LIVE_RUN")" || die 7 "备份运行时配置失败"
  fi
  for _f in $TOOLKIT_FILES config.yaml; do
    backup_one "$CFG_DIR/$_f" "$_f" || die 7 "备份 $_f 失败"
  done
  chmod 600 "$BK"/* 2>/dev/null
  sed 's/^/   /' "$BK/ORIGINS"
  echo "   校验：cd $BK && sha256sum -c SHA256SUMS"

  if [ "$NEED_ORIG" -eq 1 ]; then
    if [ -f "$HOOK_ORIG" ]; then
      mv -f "$HOOK_ORIG" "$BK/$HOOK_NAME.orig.prev" 2>/dev/null
    fi
    cp -p "$HOOK" "$HOOK_ORIG" || die 7 "写入原始钩子备份失败"
    [ "$(sha "$HOOK_ORIG")" = "$_hook_sha_now" ] || die 7 "原始钩子备份校验不符"
    md5 "$HOOK_ORIG" > "$HOOK_ORIG.md5"
    sha "$HOOK_ORIG" > "$HOOK_ORIG.sha256"
    chmod 600 "$HOOK_ORIG" "$HOOK_ORIG.md5" "$HOOK_ORIG.sha256" 2>/dev/null
    echo "   原始钩子 → $HOOK_ORIG  md5=$(cat "$HOOK_ORIG.md5")"
  fi

  echo "-- 安装"
  for _f in $TOOLKIT_FILES; do
    _m=755; [ "$_f" = load_config.sh ] && _m=644
    copy_verified "$SRC_DIR/$_f" "$CFG_DIR/$_f" "$_m" || die 8 "安装 $_f 失败；已备份在 $BK"
    echo "   ok $CFG_DIR/$_f"
  done
  copy_verified "$CLAUDE_CONFIG" "$CFG_DIR/config.yaml" 600 || die 8 "安装 config.yaml 失败；已备份在 $BK"
  echo "   ok $CFG_DIR/config.yaml"

  if [ "$(sha "$HOOK")" != "$_hook_sha_now" ]; then
    die 8 "钩子在预览后被改动，停止（脚本已安装，钩子未动）。请重新运行 --dry-run。"
  fi
  if ! copy_verified "$WORK/hook.new" "$HOOK" 755; then
    cp -p "$BK/$HOOK_NAME" "$HOOK" 2>/dev/null
    die 8 "写入钩子失败，已从 $BK 放回原钩子"
  fi
  echo "   ok $HOOK  sha256=$(sha "$HOOK")"

  # 清单（rollback 读取）
  {
    echo "version=1"
    echo "time=$(date '+%F %T')"
    echo "backup_dir=$BK"
    echo "hook=$HOOK"
    echo "hook_orig=$HOOK_ORIG"
    echo "hook_orig_md5=$(md5 "$HOOK_ORIG")"
    echo "hook_orig_sha256=$(sha "$HOOK_ORIG")"
    echo "hook_installed_sha256=$(sha "$HOOK")"
    echo "runtime_config=$RUN_FOR_ROLLBACK"
    for _f in $TOOLKIT_FILES config.yaml; do
      echo "installed $(sha "$CFG_DIR/$_f") $CFG_DIR/$_f"
    done
  } > "$MANIFEST.tmp.$$" && chmod 600 "$MANIFEST.tmp.$$" && mv -f "$MANIFEST.tmp.$$" "$MANIFEST" \
    || die 8 "写入清单失败：$MANIFEST"
  cp -p "$MANIFEST" "$BK/install.manifest" 2>/dev/null

  echo "-- 校验"
  _bad=0
  for _f in $TOOLKIT_FILES $HOOK_NAME; do
    if sh -n "$CFG_DIR/$_f" 2>/dev/null; then echo "   sh -n ok  $_f"; else echo "   sh -n FAIL $_f"; _bad=1; fi
  done
  grep -qF "$MARK_BEGIN" "$HOOK" || { echo "   钩子里没有注入段标记"; _bad=1; }
  [ "$(md5 "$HOOK_ORIG")" = "$(cat "$HOOK_ORIG.md5")" ] || { echo "   原始钩子备份 md5 不符"; _bad=1; }
  cp "$BASE_CFG" "$WORK/verify.yaml"
  if CLAUDE_CONFIG="$CFG_DIR/config.yaml" CLAUDE_CFG_DIR="$CFG_DIR" CLAUDE_BACKUP_DIR="$WORK/bak" \
       CLAUDE_LOG="$WORK/verify.log" CLAUDE_VERIFY_CORE=0 \
       sh "$CFG_DIR/claude_inject.sh" --offline "$WORK/verify.yaml" > "$WORK/verify.out" 2>&1; then
    echo "   已安装的注入脚本对临时副本试跑：ok"
  else
    echo "   已安装的注入脚本对临时副本试跑：FAIL"
    sed 's/^/   | /' "$WORK/verify.out" | tail -n 5
    _bad=1
  fi
  if [ "$_bad" -ne 0 ]; then
    echo ""
    echo "校验未通过。没有重启任何服务。建议回滚："
    echo "  CLAUDE_RUN_CONFIG=$RUN_FOR_ROLLBACK sh $CFG_DIR/claude_rollback.sh"
    exit 9
  fi
  echo ""
  echo "安装完成。OpenClash 没有被重启，生效配置也没有被改动。"
  print_next
}

print_next() {
  echo ""
  echo "-- 下一步（你自己执行）"
  echo "   1. 内核在跑时先拉一次节点（可选，没有缓存时必须）："
  echo "        sh $CFG_DIR/claude_update.sh $RUN_FOR_ROLLBACK"
  echo "   2. 在维护窗口重启（会短暂断网）："
  echo "        $OC_INIT restart"
  echo "   3. 验证："
  echo "        tail -n 20 $CFG_DIR/claude_hook.log      # 期望 fetch=skipped(offline)、verify=OK、done level=L1"
  echo "        grep -c 'Claude专用' $RUN_FOR_ROLLBACK"
  echo "   4. 出问题回滚（先检查，再 --apply）："
  echo "        sh $CFG_DIR/claude_rollback.sh"
  echo "        sh $CFG_DIR/claude_rollback.sh --apply"
}

# ------------------------------------------------------------------ main
MODE=help
CONFIG=""
TARGET=""
ASSUME_YES=0
FETCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) MODE=help ;;
    --check) MODE=check ;;
    --dry-run) MODE=dryrun ;;
    --apply) MODE=apply ;;
    --yes|-y) ASSUME_YES=1 ;;
    --fetch) FETCH=1 ;;
    --config) [ $# -ge 2 ] || die 2 "--config 需要参数"; CONFIG="$2"; shift ;;
    --target) [ $# -ge 2 ] || die 2 "--target 需要参数"; TARGET="$2"; shift ;;
    --version) echo "install.sh $VERSION"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  help) usage; exit 0 ;;
  check) cmd_check; exit 0 ;;
  dryrun)
    load_settings
    plan
    echo ""
    echo "dry-run 结束：OpenClash 目录下没有写入任何文件。确认无误后运行："
    echo "  ./install.sh --apply --config $CLAUDE_CONFIG${TARGET:+ --target $TARGET}"
    [ "$PLAN_OK" -eq 1 ] || exit 4
    exit 0
    ;;
  apply)
    load_settings
    plan
    cmd_apply
    exit 0
    ;;
esac
