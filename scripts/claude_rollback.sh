#!/bin/sh
# claude_rollback.sh —— Claude 专属出口回滚
#
# 用法:
#   claude_rollback.sh                 只检查，不修改（默认）
#   claude_rollback.sh --apply         执行回滚
#   claude_rollback.sh --status        只报告当前状态
#
# 回滚对象（严格按此顺序，前一步失败即中止，不做后续破坏性清理）:
#   1. /etc/openclash/custom/openclash_custom_overwrite.sh  ← 从备份恢复并校验 MD5
#   2. $CLAUDE_RUN_CONFIG（若已提供真实路径）              ← 剥离注入的组、规则和节点
#   3. /etc/openclash/custom/claude_b.yaml                  ← 删除（订阅凭据）
#   4. /etc/openclash/custom/claude_cache/                  ← 删除（节点缓存）
#   5. /etc/openclash/custom/.claude_backup/                ← 保留最近，其余清理
#   6. install.sh 安装的脚本与 config.yaml                   ← 按 .claude_backup/install.manifest 删除（哈希一致才删）
#
# 若存在 install.sh 写下的 .claude_backup/install.manifest，原厂 MD5 与运行配置路径默认取自清单，
# 并额外核对原始钩子备份的 sha256。环境变量 CLAUDE_STOCK_MD5 / CLAUDE_RUN_CONFIG 仍可覆盖。
#
# 安全约束:
#   · 钩子未成功恢复到原厂 MD5 时，立即退出（exit 3），凭据/缓存/备份一律保留
#   · 备份文件 MD5 不等于原厂值时拒绝恢复，避免用被污染的备份覆盖
#
# 明确不做:
#   · 不重启 OpenClash、不重载内核、不碰 DNS / 防火墙 / crontab
#   · 不自动重新生成配置（会打印命令，由维护窗口人工执行）

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

VERSION="1.2"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=load_config.sh
[ -r "$SCRIPT_DIR/load_config.sh" ] && . "$SCRIPT_DIR/load_config.sh"
CFG_DIR="${CLAUDE_CFG_DIR:-/etc/openclash/custom}"
HOOK="$CFG_DIR/openclash_custom_overwrite.sh"
HOOK_BAK="$CFG_DIR/.claude_backup/openclash_custom_overwrite.sh.orig"
CRED="$CFG_DIR/claude_b.yaml"
CACHE="$CFG_DIR/claude_cache"
BAKDIR="$CFG_DIR/.claude_backup"
RUNCFG="${CLAUDE_RUN_CONFIG:-/etc/openclash/__PRIVATE_CONFIG__.yaml}"
STOCK_MD5="${CLAUDE_STOCK_MD5:-c6fb4a96c1e14ee24ba85682e2e3d367}"
# install.sh --apply 写下的清单：原始钩子哈希、运行配置路径、安装过的文件
MANIFEST="$BAKDIR/install.manifest"
mf_get() { [ -r "$MANIFEST" ] && sed -n "s/^$1=//p" "$MANIFEST" | head -n 1; }
ORIG_SHA=""
if [ -r "$MANIFEST" ]; then
  _m=$(mf_get hook_orig_md5)
  [ -z "${CLAUDE_STOCK_MD5:-}" ] && [ -n "$_m" ] && STOCK_MD5="$_m"
  _r=$(mf_get runtime_config)
  [ -z "${CLAUDE_RUN_CONFIG:-}" ] && [ -n "$_r" ] && RUNCFG="$_r"
  ORIG_SHA=$(mf_get hook_orig_sha256)
elif [ -z "${CLAUDE_STOCK_MD5:-}" ] && [ -r "$HOOK_BAK.md5" ]; then
  STOCK_MD5=$(cat "$HOOK_BAK.md5")
fi

MODE=check
case "${1:-}" in
  --apply)  MODE=apply ;;
  --status) MODE=status ;;
  --version) echo "claude_rollback $VERSION"; exit 0 ;;
  "") : ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac

md5of() { [ -f "$1" ] && md5sum "$1" 2>/dev/null | cut -d' ' -f1 || echo none; }

echo "== claude_rollback $VERSION  $(date '+%F %T')  mode=$MODE"
echo "   hook     : $HOOK"
echo "   hook_md5 : $(md5of "$HOOK")   (stock=$STOCK_MD5)"
echo "   hook_bak : $([ -f "$HOOK_BAK" ] && echo "$HOOK_BAK ($(md5of "$HOOK_BAK"))" || echo 无)"
echo "   cred     : $([ -f "$CRED" ] && echo 存在 || echo 无)"
echo "   cache    : $([ -d "$CACHE" ] && echo "存在 ($(ls -1 "$CACHE" 2>/dev/null | wc -l | tr -d ' ') 个文件)" || echo 无)"
echo "   runtime  : $RUNCFG"
echo "   manifest : $([ -r "$MANIFEST" ] && echo "$MANIFEST" || echo 无)"
if [ -f "$RUNCFG" ]; then
  N=$(grep -c 'Claude专用' "$RUNCFG" 2>/dev/null || echo 0)
  echo "   配置内 Claude 引用数: $N"
fi

[ "$MODE" = "status" ] && exit 0

HAS_HOOK_MOD=0
[ -f "$HOOK" ] && [ "$(md5of "$HOOK")" != "$STOCK_MD5" ] && HAS_HOOK_MOD=1

echo ""
echo "-- 计划动作"
if [ "$HAS_HOOK_MOD" -eq 1 ]; then
  echo "   1. 恢复钩子（当前已非原厂 MD5）"
  if [ ! -f "$HOOK_BAK" ]; then echo "      [注意] 备份缺失，恢复将失败"; fi
else
  echo "   1. 钩子未改动，跳过"
fi
if [ -n "${RUNCFG:-}" ] && [ -f "$RUNCFG" ]; then
  case "$RUNCFG" in
    *__PRIVATE_CONFIG__*) echo "   2. 跳过配置剥离：路径仍是占位符" ;;
    *) echo "   2. 从运行配置剥离 Claude 相关组、规则和注入节点：$RUNCFG" ;;
  esac
else
  echo "   2. 未提供可写的运行配置（CLAUDE_RUN_CONFIG），跳过文件内剥离"
fi
[ -f "$CRED" ] && echo "   3. 删除凭据 $CRED" || echo "   3. 凭据不存在，跳过"
[ -d "$CACHE" ] && echo "   4. 删除缓存目录 $CACHE" || echo "   4. 缓存不存在，跳过"
if [ -r "$MANIFEST" ]; then
  echo "   5. 移除 install.sh 安装的文件（哈希与清单一致的才删，改过的保留）："
  grep '^installed ' "$MANIFEST" | while read -r _k _s _p; do echo "      $_p"; done
else
  echo "   5. 没有 install.sh 清单，跳过"
fi

if [ "$MODE" = "check" ]; then
  echo ""
  echo "以上为检查模式，未做任何修改。执行请加 --apply"
  exit 0
fi

echo ""
echo "-- 执行"

# ---------------------------------------------------------------- 1. 钩子
# 顺序要求：必须先确认钩子回到原厂，才允许清理凭据与缓存。
# 否则会出现「钩子仍指向已删除的注入脚本 / 凭据」的半残状态，
# 下一次 OpenClash 启动会走应急路径，且没有凭据可以恢复。
HOOK_OK=0
if [ "$HAS_HOOK_MOD" -eq 1 ]; then
  if [ ! -f "$HOOK_BAK" ]; then
    echo "   [ERROR] 备份不存在，拒绝盲改钩子。请手工从 OpenClash 安装包取回原厂文件。"
  else
    BAK_MD5=$(md5of "$HOOK_BAK")
    BAK_SHA=$(sha256sum "$HOOK_BAK" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$ORIG_SHA" ] && [ "$BAK_SHA" != "$ORIG_SHA" ]; then
      echo "   [ERROR] 备份 sha256 与清单记录不符（$BAK_SHA != $ORIG_SHA），拒绝恢复。"
    elif [ "$BAK_MD5" != "$STOCK_MD5" ]; then
      echo "   [ERROR] 备份 MD5 与预期原厂值不符（$BAK_MD5 != $STOCK_MD5），拒绝恢复。"
      echo "           备份可能已被污染，请人工核对后再操作。"
    elif cp "$HOOK_BAK" "$HOOK.rollback.$$" && chmod 755 "$HOOK.rollback.$$" \
         && mv -f "$HOOK.rollback.$$" "$HOOK"; then
      NOW_MD5=$(md5of "$HOOK")
      if [ "$NOW_MD5" = "$STOCK_MD5" ]; then
        echo "   钩子已恢复 -> $NOW_MD5（与原厂一致）"
        HOOK_OK=1
      else
        echo "   [ERROR] 钩子恢复后 MD5 不符（$NOW_MD5），恢复失败"
      fi
    else
      rm -f "$HOOK.rollback.$$" 2>/dev/null
      echo "   [ERROR] 钩子恢复失败（写入或替换失败）"
    fi
  fi
else
  echo "   钩子无需恢复（已是原厂 MD5）"
  HOOK_OK=1
fi

if [ "$HOOK_OK" -ne 1 ]; then
  echo ""
  echo "-- 中止：钩子未能恢复为原厂版本"
  echo "   已停止后续清理，以下内容全部保留："
  echo "     · 凭据 $CRED"
  echo "     · 缓存 $CACHE"
  echo "     · 备份 $BAKDIR"
  echo "   处理建议：核对 $HOOK_BAK 是否为原厂文件（期望 MD5 $STOCK_MD5），"
  echo "             手工执行 cp 恢复后重新运行本脚本。"
  exit 3
fi

# ---------------------------------------------------------------- 2. 从运行配置里剥离本方案注入的组、规则和节点
# 不依赖 OpenClash 重启。路径必须来自这次的 CLAUDE_RUN_CONFIG / 实机配置，不是仓库占位符。
if [ -n "${RUNCFG:-}" ] && [ -f "$RUNCFG" ]; then
  case "$RUNCFG" in
    *__PRIVATE_CONFIG__*) echo "   跳过配置剥离：路径仍是占位符 $RUNCFG" ;;
    *)
      toolkit_load_config >/dev/null 2>&1 || true
      _ruby="${CLAUDE_RUBY:-ruby}"
      if "$_ruby" -ryaml -E UTF-8 -e '
path = ARGV[0]
alias_name = ENV["CLAUDE_ALIAS"].to_s
suffix = %w[claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com]
apns_g = "APNs推送"
apns_rule = "DOMAIN-SUFFIX,push.apple.com,#{apns_g}"
cidr = "IP-CIDR,160.79.104.0/21,Claude专用,no-resolve"
def yload(p)
  Psych.safe_load(File.read(p), permitted_classes: [], permitted_symbols: [], aliases: true)
end
d = yload(path)
unless d.is_a?(Hash)
  warn "E_NOT_HASH"
  exit 1
end
ours = ->(n) { n.to_s.start_with?("B-") || (!alias_name.empty? && n.to_s == alias_name) }
d["proxies"].reject! { |p| p.is_a?(Hash) && ours.call(p["name"]) } if d["proxies"].is_a?(Array)
if d["proxy-groups"].is_a?(Array)
  d["proxy-groups"].reject! { |g| g.is_a?(Hash) && (%w[ClaudeAuto Claude专用] + [apns_g]).include?(g["name"]) }
end
if d["rules"].is_a?(Array)
  d["rules"].reject! { |r| r.is_a?(String) && (r.end_with?(",Claude专用") || r.strip == apns_rule || r.strip == cidr) }
  d["rules"].reject! { |r| r.is_a?(String) && r.end_with?(",REJECT") && suffix.any? { |s| r == "DOMAIN-SUFFIX,#{s},REJECT" } }
end
tmp = "#{path}.rollback.#{$$}"
mode = (File.stat(path).mode & 0o777)
File.open(tmp, "w") { |f| YAML.dump(d, f) }
File.chmod(mode, tmp)
File.rename(tmp, path)
puts "stripped"
' "$RUNCFG"; then
        echo "   已从配置剥离 Claude 相关组、规则和注入节点：$RUNCFG"
      else
        echo "   [ERROR] 从配置剥离失败，凭据与缓存将保留，便于排查。"
        exit 3
      fi
      ;;
  esac
else
  echo "   未提供可写的运行配置（CLAUDE_RUN_CONFIG），跳过文件内剥离"
fi

# ---------------------------------------------------------------- 3. 凭据
[ -f "$CRED" ] && rm -f "$CRED" && echo "   凭据已删除"
[ -d "$CACHE" ] && rm -rf "$CACHE" && echo "   缓存已删除"

if [ -d "$BAKDIR" ]; then
  ls -1t "$BAKDIR"/pre_inject_*.yaml 2>/dev/null | tail -n +2 | while read -r f; do
    rm -f "$f"
  done
  echo "   保留最新一份 pre_inject 备份"
fi

# ---------------------------------------------------------------- 5. install.sh 安装的文件
if [ -r "$MANIFEST" ]; then
  grep '^installed ' "$MANIFEST" | while read -r _k _s _p; do
    [ -f "$_p" ] || continue
    if [ "$(sha256sum "$_p" 2>/dev/null | cut -d' ' -f1)" = "$_s" ]; then
      rm -f "$_p" && echo "   已移除 $_p"
    else
      echo "   保留 $_p（安装后被改过）"
    fi
  done
  mv -f "$MANIFEST" "$MANIFEST.rolledback.$(date '+%Y%m%d-%H%M%S')" 2>/dev/null
  echo "   清单已归档；安装前的完整备份仍在 $BAKDIR/install_*"
fi

echo ""
echo "-- 剩余动作（需人工，在维护窗口执行）"
echo "   若内核仍在运行旧配置，需要一次重启才能让剥离后的文件生效："
echo "     /etc/init.d/openclash restart        # 会短暂中断代理"
echo "   本脚本不执行重启。"
echo ""
echo "-- 回滚后自检命令"
echo "     md5sum $HOOK                       # 期望 $STOCK_MD5"
echo "     grep -c 'Claude专用' $RUNCFG        # 期望 0（已剥离之后）"
exit 0
