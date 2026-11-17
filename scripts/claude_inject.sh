#!/bin/sh
# claude_inject.sh —— Claude 专属出口配置注入
#
# 用法:
#   claude_inject.sh <target_config>        注入并原子替换目标文件
#   claude_inject.sh --offline <target>     钩子专用：只读缓存，不发起任何网络请求
#   claude_inject.sh --check <target>       只拉取/比对，不写目标文件
#   claude_inject.sh --dry-run <target>     完整构建+校验，产出到 /tmp，不写目标
#   claude_inject.sh --version
#
# 环境变量:
#   CLAUDE_VERIFY_CORE=1        启用内核校验（默认关闭）
#   CLAUDE_MIN_MEM_MB=220       内核校验所需最低 MemAvailable
#   CLAUDE_CFG_DIR / CLAUDE_CACHE_DIR / CLAUDE_BACKUP_DIR / CLAUDE_LOG
#   CLAUDE_FETCH_VIA             指定下载代理，如 socks5h://127.0.0.1:7891
#   CLAUDE_TEST_RAW              仅测试用：用本地文件代替订阅下载
#
# 为什么钩子必须用 --offline:
#   OpenClash 的 Step 3（配置生成）发生在 start_run_core 之前，旧内核已停止，
#   7890/7891 不监听。此时任何经代理的下载都不可能成功。
#   因此订阅拉取放在 claude_update.sh（内核运行时执行），钩子只消费缓存。
#
# 设计约束（对应任务书）:
#   · 订阅地址不硬编码、不进 argv、不进日志
#   · 只在 $TMP_CONFIG_FILE 的副本上构建，最后原子 rename
#   · 不使用 use: proxy-provider
#   · 订阅失败 → 旧缓存 → REJECT-only，绝不静默跳过
#   · 不写入 DIRECT / COMPATIBLE
#
# 退出码:
#   0  成功（含降级成功）
#   10 --check 发现节点有变化
#   11 订阅解析失败      12 节点为空        13 无有效节点
#   14 结构校验失败      15 原子写入失败
#   16 内核校验失败（含降级配置）
#   17 目标文件在构建期间被并发修改（拒绝写入，原文件保持不动）
#   2  参数/环境错误     3  临时目录失败
#   4  下载失败（且无缓存，已降级 REJECT-only 时仍返回 0）

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

VERSION="1.0"
PROG="claude_inject"
CFG_DIR="${CLAUDE_CFG_DIR:-/etc/openclash/custom}"
CRED_FILE="$CFG_DIR/claude_b.yaml"
CACHE_DIR="${CLAUDE_CACHE_DIR:-$CFG_DIR/claude_cache}"
CACHE_NODES="$CACHE_DIR/nodes.yaml"
CACHE_META="$CACHE_DIR/meta.txt"
BACKUP_DIR="${CLAUDE_BACKUP_DIR:-$CFG_DIR/.claude_backup}"
LOG="${CLAUDE_LOG:-/tmp/claude_inject.log}"

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$PROG" "$*" >> "$LOG" 2>/dev/null; }
say() { printf '%s\n' "$*"; log "$*"; }

MODE=inject
OFFLINE=0
case "${1:-}" in
  --version) echo "$PROG $VERSION"; exit 0 ;;
  --check)   MODE=check;   shift ;;
  --dry-run) MODE=dryrun;  shift ;;
  --sync)    MODE=sync;    shift ;;
  # 钩子专用：配置生成阶段旧内核已停止，7890/7891 不可用，禁止发起网络请求
  --offline) OFFLINE=1;    shift ;;
esac
TARGET="${1:-}"

[ -n "$TARGET" ] || { echo "usage: $PROG [--check|--dry-run] <target_config>" >&2; exit 2; }
[ -f "$TARGET" ] || { echo "target not found: $TARGET" >&2; exit 2; }
case "$TARGET" in
  "$CRED_FILE"|"$CACHE_DIR"/*) echo "refuse: target is a config artifact" >&2; exit 2 ;;
esac
[ "$(wc -c < "$TARGET" 2>/dev/null || echo 0)" -gt 1000 ] || { echo "target too small, refuse" >&2; exit 2; }

WORK=$(mktemp -d /tmp/claude_inject.XXXXXX) || { echo "mktemp failed" >&2; exit 3; }
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

RUBY="${CLAUDE_RUBY:-ruby} -ryaml -E UTF-8"
SHA() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

say "===== start mode=$MODE target=$TARGET"
SHA_BEFORE=$(SHA "$TARGET")
say "sha_before=$SHA_BEFORE size=$(wc -c < "$TARGET" | tr -d ' ')"

# ---------------------------------------------------------------- 1. 备份
mkdir -p "$BACKUP_DIR" 2>/dev/null
if [ -d "$BACKUP_DIR" ] && [ "$MODE" = "inject" ]; then
  cp "$TARGET" "$BACKUP_DIR/pre_inject_$SHA_BEFORE.yaml" 2>/dev/null
  chmod 600 "$BACKUP_DIR/pre_inject_$SHA_BEFORE.yaml" 2>/dev/null
  ls -1t "$BACKUP_DIR"/pre_inject_*.yaml 2>/dev/null | tail -n +4 | while read -r old; do
    rm -f "$old"
  done
fi
cp "$TARGET" "$WORK/base.yaml" || { say "ERROR copy base failed"; exit 3; }
[ "$(SHA "$WORK/base.yaml")" = "$SHA_BEFORE" ] || { say "ERROR copy mismatch"; exit 3; }

# ---------------------------------------------------------- 2. 取订阅原文
# 代理路径必须显式：只认 环境变量 / 已监听端口，失败不回退 DIRECT
pick_proxy() {
  if [ -n "${CLAUDE_FETCH_VIA:-}" ]; then printf '%s' "$CLAUDE_FETCH_VIA"; return 0; fi
  for cand in "socks5h://127.0.0.1:7891" "http://127.0.0.1:7890"; do
    lp=${cand##*://}
    # 注意：mihomo 绑定在 :: 上，netstat 显示为 ":::7891"，不能只匹配 127.0.0.1
    if netstat -ln 2>/dev/null | grep -qE "[:.]${lp##*:}[[:space:]]"; then
      printf '%s' "$cand"; return 0
    fi
  done
  return 1
}

fetch_sub() {
  out="$1"
  if [ -n "${CLAUDE_TEST_RAW:-}" ]; then
    [ -r "$CLAUDE_TEST_RAW" ] || return 2
    cp "$CLAUDE_TEST_RAW" "$out" && return 0 || return 2
  fi
  [ -r "$CRED_FILE" ] || { log "cred file missing: $CRED_FILE"; return 2; }
  url=$($RUBY -e 'd = (Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], aliases: true) rescue nil); u = (d.is_a?(Hash) ? d["url"] : nil); print(u.to_s)' "$CRED_FILE" 2>/dev/null)
  [ -n "$url" ] || { log "cred file has no url key"; return 2; }
  proxy=$(pick_proxy) || { log "no local proxy port available, refuse to fall back to DIRECT"; return 3; }
  esc=$(printf '%s' "$url" | sed 's/\\/\\\\/g; s/"/\\"/g')
  # 多数机场对非客户端 UA 返回 403，必须带客户端标识
  ua="${CLAUDE_SUB_UA:-clash.meta}"
  printf 'url = "%s"\nproxy = "%s"\nuser-agent = "%s"\nconnect-timeout = 10\nmax-time = 45\nlocation\nsilent\nfail\noutput = "%s"\n' \
    "$esc" "$proxy" "$ua" "$out" | curl -K - 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
    log "download failed rc=$rc via=$proxy"
    return 4
  fi
  return 0
}

say "--- fetch"
if [ "$OFFLINE" -eq 1 ]; then
  SRC=cache
  say "fetch=skipped(offline)"
elif fetch_sub "$WORK/raw.yaml"; then
  SRC=fresh
  say "fetch=ok bytes=$(wc -c < "$WORK/raw.yaml" | tr -d ' ')"
else
  SRC=cache
  say "fetch=failed"
fi

# --------------------------------------------------------- 3. 解析与校验
cat > "$WORK/validate.rb" <<'RUBY'
require 'yaml'
require 'digest'
raw, out, base, fpout = ARGV
ALLOWED = %w[ss ssr vmess vless trojan hysteria hysteria2 tuic snell http socks5 wireguard anytls]
PREFIX = 'B-'
# 本方案自己注入的节点名有两种形态：
#   B-<订阅原名>   —— 订阅节点原样加前缀
#   B Taiwan 01    —— 改名后的显示名（按任务要求不带连字符）
# 识别逻辑必须同时覆盖两者：只匹配 B- 会把别名当成机场 A 的节点，
# 于是「判为与 A 冲突」在每次重建时丢掉这个节点。
OURS = /\AB[- ]/
# 安全解析：只允许 YAML 原生标量与容器。
#   permitted_classes 为空 → 禁止 !ruby/object 等任意对象反序列化；
#   aliases: true        → 兼容订阅里常见的锚点引用（不引入反序列化面）。
def yload(path)
  Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
end
begin
  d = yload(raw)
rescue Psych::DisallowedClass => e
  warn "E_UNSAFE_TYPE #{e.message}"
  exit 11
rescue Exception => e
  warn "E_PARSE #{e.class}"
  exit 11
end
proxies = d.is_a?(Hash) ? d['proxies'] : nil
unless proxies.is_a?(Array) && proxies.size > 0
  warn 'E_EMPTY'
  exit 12
end
exnames = []
begin
  b = yload(base)
  # 只与机场 A 的节点比名。目标文件可能已包含上一轮注入的 B 节点
  # （B- 前缀与 B Taiwan 01 这类别名），那些会被 merge 阶段整体剥离，不构成冲突。
  exnames = (b['proxies'] || []).map { |p| p['name'].to_s }.reject { |n| n =~ OURS }
rescue Exception
end
seen = {}
res = []
skipped = { 'dup' => 0, 'collide' => 0, 'badtype' => 0, 'badfield' => 0, 'ad' => 0, 'privsrv' => 0 }
# 机场常把「邮箱客服 / 最新官网 / 支持AI」这类说明信息伪装成节点塞进订阅，
# 它们不是代理，参与 url-test 只会浪费探测并可能被选中。
AD_PAT  = /(@|官网|客服|订阅|到期|剩余|流量重置|加群|购买|续费|电报|telegram|www\.|https?:|[:：\/]|支持AI)/i
URLISH  = /[a-z0-9][a-z0-9-]*\.(com|net|org|work|xyz|top|cc|io|me|cn|vip|shop|site|club|link)\b/i
PRIVATE = /\A(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|0\.0\.0\.0|::1|fe80:|f[cd])/i
dropped = []
proxies.each do |p|
  next unless p.is_a?(Hash)
  name = p['name'].to_s.strip
  type = p['type'].to_s.strip.downcase
  srv  = p['server'].to_s.strip
  port = p['port'].to_i
  if name.empty? || srv.empty? || port <= 0 || port > 65535
    skipped['badfield'] += 1
    next
  end
  unless ALLOWED.include?(type)
    skipped['badtype'] += 1
    next
  end
  if name =~ AD_PAT || name =~ URLISH
    skipped['ad'] += 1
    dropped << "#{name}(ad)"
    next
  end
  if srv =~ PRIVATE
    skipped['privsrv'] += 1
    dropped << "#{name}(privsrv)"
    next
  end
  nn = PREFIX + name
  if seen.key?(nn)
    skipped['dup'] += 1
    next
  end
  if exnames.include?(nn)
    skipped['collide'] += 1
    next
  end
  seen[nn] = 1
  q = {}
  p.each { |k, v| q[k] = v }
  q['name'] = nn
  q['udp'] = true if q['udp'].nil?
  res << q
end
warn "SKIP #{skipped.map { |k, v| "#{k}=#{v}" }.join(' ')}"
dropped.each { |x| warn "DROPPED #{x}" }
if res.empty?
  warn 'E_NOVALID'
  exit 13
end
File.open(out, 'w') { |f| YAML.dump({ 'proxies' => res }, f) }
# 指纹必须排除每次请求都会变的字段。实测该机场有 31 个节点的
# client-fingerprint 每次下载都随机，若纳入指纹会导致「永远判定为有变化」。
VOLATILE = %w[client-fingerprint].freeze
canon = res.map { |p| p.reject { |k, _| VOLATILE.include?(k) }.sort.to_s }.sort.join("\n")
File.write(fpout, Digest::SHA256.hexdigest(canon)) if fpout
puts res.size
RUBY

HAVE_NODES=0
NODE_COUNT=0
if [ "$SRC" = "fresh" ]; then
  OUT=$($RUBY "$WORK/validate.rb" "$WORK/raw.yaml" "$WORK/nodes.yaml" "$WORK/base.yaml" "$WORK/fp.txt" 2>"$WORK/val.err")
  RC=$?
  if [ "$RC" -eq 0 ] && [ -n "$OUT" ]; then
    HAVE_NODES=1; NODE_COUNT=$OUT
    cp "$WORK/nodes.yaml" "$WORK/valid_nodes.yaml"
    say "parse=ok nodes=$NODE_COUNT $(cat "$WORK/val.err" 2>/dev/null | tr '\n' ' ')"
  else
    say "parse=failed rc=$RC $(cat "$WORK/val.err" 2>/dev/null | tr '\n' ' ')"
  fi
fi

if [ "$HAVE_NODES" -eq 0 ] && [ -s "$CACHE_NODES" ]; then
  cp "$CACHE_NODES" "$WORK/valid_nodes.yaml" && HAVE_NODES=1
  NODE_COUNT=$($RUBY -e 'd = Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], aliases: true); print(d.is_a?(Hash) ? (d["proxies"] || []).size : 0)' "$WORK/valid_nodes.yaml" 2>/dev/null)
  say "cache=used nodes=$NODE_COUNT"
fi

if [ "$MODE" = "check" ]; then
  NEWFP=$([ -s "$WORK/fp.txt" ] && cat "$WORK/fp.txt" 2>/dev/null || echo none)
  OLD=$([ -s "$CACHE_META" ] && cat "$CACHE_META" 2>/dev/null || echo none)
  say "check old=$OLD new=$NEWFP"
  if [ "$NEWFP" = "none" ]; then say "check=no_new_data"; exit 4; fi
  if [ "$NEWFP" = "$OLD" ]; then say "check=unchanged"; exit 0; fi
  say "check=changed"
  exit 10
fi

if [ "$MODE" = "sync" ] && [ "$HAVE_NODES" -eq 1 ]; then
  NEWFP=$([ -s "$WORK/fp.txt" ] && cat "$WORK/fp.txt" 2>/dev/null || echo none)
  OLD=$([ -s "$CACHE_META" ] && cat "$CACHE_META" 2>/dev/null || echo none)
  say "sync old=$OLD new=$NEWFP"
  if [ "$NEWFP" = "$OLD" ] && [ "$OLD" != "none" ]; then
    say "sync=unchanged, 不重建配置"
    exit 0
  fi
  say "sync=changed"
fi

# --------------------------------------------------------- 4. 生成配置
cat > "$WORK/merge.rb" <<'RUBY'
require 'yaml'
cfg, nodesf, out, mode = ARGV
SUFFIX = %w[claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com]
OURS_G = %w[ClaudeAuto Claude专用]
# 本方案自己注入的节点名（见 claude_inject.sh validate 段的 OURS 注释）
OURS = /\AB[- ]/
# 机场 B 目标节点的显示名映射。放在构建阶段而不是直接改配置文件：
# 订阅每次重拉都会带回原名，只有在这里改名才能对「每次重建」都成立。
# 匹配用锚定正则，且要求命中数恰好为 1；命中 0 个或 >1 个都只报告不猜。
B_RENAME = [
  { match: /台湾01\s*Home\z/u, to: 'B Taiwan 01', from_kind: '订阅原名' }
].freeze
# S7 起 Claude 专属出口有两条硬约束：
# · ALIAS 必须是 Claude专用 的首个成员。select 组的默认值就是首个成员，写进 YAML
#   才能保证「cache.db 被清空 / 配置重新生成 / 换配置文件」之后默认出口仍是台湾节点。
#   只靠运行时 API 选中值（store-selected）会被清缓存打回自动选优。
# · CLAUDE_CIDR 兜住「连接没有域名」的路径：客户端直连真实 IP 或收不到 SNI 时，
#   域名规则失效，连接会一路落到 rules 末尾的 MATCH 走机场 A。该网段是 Anthropic
#   自有分配（ARIN NET-160-79-104-0-1，Anthropic, PBC，160.79.104.0-160.79.111.255）。
#   no-resolve 让内核不为匹配该规则做反查。
ALIAS = 'B Taiwan 01'
CLAUDE_CIDR = 'IP-CIDR,160.79.104.0/21,Claude专用,no-resolve'
# WebRTC 的 STUN 反射地址必须和 Claude 页面看到的出口一致：页面用 HTTP 看到的
# 是台湾节点，而 STUN 默认落到 google.com / MATCH（机场 A 的 🚀节点选择），
# 两个出口不一致，IP 检测就会判成「真实网络已暴露」。STUN 主机分散在
# stun*.l.google.com、stun.cloudflare.com、stun.services.mozilla.com 等，
# 逐个枚举必漏，用 keyword 一次兜住；TURN 不在其列也不影响（TURN 不暴露本机地址）。
STUN_RULE = 'DOMAIN-KEYWORD,stun,Claude专用'
# APNs（iOS 推送）：
#   国内 Apple 专线对部分海外 App 的推送做了过滤，iOS 的推送又是全系统共用一条 TCP
#   长连接，因此只能把整个 push.apple.com 后缀交给节点，由节点侧远端解析并直连 Apple
#   海外网关，才能恢复 X / Telegram 这类 App 的通知。主机会是 courier.push.apple.com
#   与 N-courier.push.apple.com（编号发现机制），都在这个后缀内。
#   网络层无法按 App 拆分，代价是国内 App 的推送也一起绕海外 —— 所以用 fallback 组，
#   节点不可用时自动回落 DIRECT，避免「机场一抽风，所有通知一起失效」。
APNS_G = 'APNs推送'
APNS_RULE = "DOMAIN-SUFFIX,push.apple.com,#{APNS_G}"

def yload(path)
  Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
end

def apply_rename(nodes, report)
  renamed = {}
  B_RENAME.each do |rule|
    hits = nodes.each_index.select { |i| nodes[i]['name'].to_s =~ rule[:match] }
    # 订阅里可能已带别名（缓存或上一轮产物），此时命中本身就是目标名
    if hits.size == 1
      src = nodes[hits[0]]['name'].to_s
      renamed[hits[0]] = rule[:to]
      report << "rename=#{src} -> #{rule[:to]}"
    elsif hits.size > 1
      report << "rename_skipped reason=ambiguous to=#{rule[:to]} matches=#{hits.size}"
    else
      report << "rename_missing to=#{rule[:to]} （订阅中未找到匹配节点，未改动任何名字）"
    end
  end
  nodes.each_with_index.map do |n, i|
    next n unless renamed.key?(i)
    q = Marshal.load(Marshal.dump(n))
    q['name'] = renamed[i]
    q
  end
end

d = yload(cfg)
d['proxies'] ||= []
d['proxy-groups'] ||= []
d['rules'] ||= []
d['proxies'].reject! { |p| p.is_a?(Hash) && p['name'].to_s =~ OURS }
d['proxy-groups'].reject! { |g| g.is_a?(Hash) && OURS_G.include?(g['name']) }
# APNs 组/规则同样先清后加，保证重复注入不累积
d['proxy-groups'].reject! { |g| g.is_a?(Hash) && g['name'] == APNS_G }
d['rules'].reject! { |r| r.is_a?(String) && r.strip == APNS_RULE }
# 旧产物里的域名规则与 IP 规则一并清掉，保证重复注入不累积（幂等）。
d['rules'].reject! { |r| r.is_a?(String) && (r.end_with?(',Claude专用') || r.strip == CLAUDE_CIDR) }
# 同步清掉钩子 shell 级应急产物（6 条直接指向 REJECT 的规则）。
# 否则应急态留下的 REJECT 规则会一直压在头部，节点恢复后 Claude 仍然不通。
d['rules'].reject! do |r|
  r.is_a?(String) && r.end_with?(',REJECT') &&
    SUFFIX.any? { |s| r == "DOMAIN-SUFFIX,#{s},REJECT" }
end
RENAME_REPORT = []
if mode == 'normal'
  nodes = apply_rename(yload(nodesf)['proxies'], RENAME_REPORT)
  names = nodes.map { |n| n['name'] }
  # Anthropic 不向中国香港/澳门提供服务。这些节点一旦被 url-test 选中，
  # claude.ai 会直接跳到 /app-unavailable-in-region。保留节点定义（不影响
  # 机场 A），但不让它们参与 Claude 路由。
  UNSUPPORTED = /香港|HK|Hong\s*Kong|澳门|Macau/i
  usable = names.reject { |n| n =~ UNSUPPORTED }
  dropped = names.size - usable.size
  warn "region_excluded=#{dropped}" if dropped > 0
  usable = names if usable.empty?  # 防御：极端情况下保底可启动
  d['proxies'].concat(nodes)
  auto = { 'name' => 'ClaudeAuto', 'type' => 'url-test',
           'url' => 'http://cp.cloudflare.com/generate_204',
           'interval' => 300, 'tolerance' => 50, 'lazy' => false,
           'proxies' => usable }
  # 首个成员即 select 组的默认出口。别名在订阅里存在时钉死台湾节点，ClaudeAuto 退居
  # 第二位（只供人工主动切换；select 组本身不做故障接管，台湾不可用即连接失败）。
  # 别名缺失时退回旧顺序，避免改名规则未命中导致构建失败。
  head = usable.include?(ALIAS) ? [ALIAS, 'ClaudeAuto'] : ['ClaudeAuto']
  sel = { 'name' => 'Claude专用', 'type' => 'select',
          'proxies' => head + (usable - head) + ['REJECT'] }
  d['proxy-groups'].unshift(auto, sel)
else
  sel = { 'name' => 'Claude专用', 'type' => 'select', 'proxies' => ['REJECT'] }
  d['proxy-groups'].unshift(sel)
end
# APNs 推送组：优先走机场 A 的自动选优组，节点全灭时回落直连。
# 上游组名从基础配置里取（以「自动选择」结尾的那个 url-test 组），不硬编码 emoji：
# 名字里带 U+FE0F 变体，写死一旦不一致就成了悬空引用，verify 的 dangling 检查会
# 直接打回 reject-only，等于把 Claude 也一起停掉。
APNS_UP = d['proxy-groups'].map { |g| g.is_a?(Hash) ? g['name'].to_s : '' }
                             .find { |n| n.end_with?('自动选择') && n != APNS_G } || 'DIRECT'
apns = { 'name' => APNS_G, 'type' => 'fallback',
         'url' => 'http://cp.cloudflare.com/generate_204',
         'interval' => 300, 'lazy' => false,
         'proxies' => [APNS_UP, 'DIRECT'].uniq }
d['proxy-groups'].unshift(apns)
# 域名规则在前、Anthropic 网段紧跟其后、STUN 再跟一条、APNs 最后一条，
# 其余规则保持原顺序整体后移。
d['rules'] = SUFFIX.map { |s| "DOMAIN-SUFFIX,#{s},Claude专用" } + [CLAUDE_CIDR, STUN_RULE, APNS_RULE] + d['rules']
File.open(out, 'w') { |f| YAML.dump(d, f) }
# 改名结果进 stderr（钩子日志）与 stdout（dry-run 可见），便于事后核对
RENAME_REPORT.each { |l| warn l }
puts RENAME_REPORT.join("\n") unless RENAME_REPORT.empty?
RUBY

cat > "$WORK/verify.rb" <<'RUBY'
require 'yaml'
base, merged, mode = ARGV
# 机场 B 目标节点的统一显示名（与 merge 段 B_RENAME 的 to 值一致）
ALIAS = 'B Taiwan 01'
# Anthropic 自有网段规则（与 merge 段 CLAUDE_CIDR 必须逐字一致）
CLAUDE_CIDR = 'IP-CIDR,160.79.104.0/21,Claude专用,no-resolve'
# WebRTC/STUN 与 Claude 同出口（与 merge 段 STUN_RULE 必须逐字一致）
STUN_RULE = 'DOMAIN-KEYWORD,stun,Claude专用'
# iOS 推送（APNs）走机场节点（与 merge 段 APNS_G / APNS_RULE 必须逐字一致）
APNS_G = 'APNs推送'
APNS_RULE = "DOMAIN-SUFFIX,push.apple.com,#{APNS_G}"
def yload(path)
  Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
end
b = yload(base)
m = yload(merged)
errs = []
gnames = (m['proxy-groups'] || []).map { |g| g['name'] }
errs << 'dup_group' if gnames.size != gnames.uniq.size
sel = (m['proxy-groups'] || []).find { |g| g['name'] == 'Claude专用' }
auto = (m['proxy-groups'] || []).find { |g| g['name'] == 'ClaudeAuto' }
errs << 'no_sel' unless sel
if mode == 'normal'
  errs << 'no_auto' unless auto
  errs << 'reject_not_last' unless sel && sel['proxies'].is_a?(Array) && sel['proxies'].last == 'REJECT'
  errs << 'empty_auto' unless auto && auto['proxies'].is_a?(Array) && auto['proxies'].size > 0
  # 机场 B 目标节点的统一显示名：出现就必须唯一，且必须参与 Claude 路由
  # （台湾在 Anthropic 支持地区内，不进排除名单）。缺失只告警，不阻断构建。
  alias_nodes = (m['proxies'] || []).select { |p| p['name'].to_s == ALIAS }
  # S7：select 组的默认出口 = 首个成员。有别名就必须是别名（钉死台湾），
  # 无别名才退回旧的 ClaudeAuto 首位。ClaudeAuto 只允许排在第二位。
  want_head = alias_nodes.empty? ? 'ClaudeAuto' : ALIAS
  errs << 'pin_not_first' unless sel && sel['proxies'].is_a?(Array) && sel['proxies'][0] == want_head
  errs << 'sel_dup_member' if sel && sel['proxies'].is_a?(Array) && sel['proxies'].size != sel['proxies'].uniq.size
  if alias_nodes.empty?
    warn "alias_missing #{ALIAS}（改名规则未命中，配置仍可用）"
  else
    # 别名在时 ClaudeAuto 必须紧随其后（第二位），别名的自动兜底退居次要位置
    errs << 'auto_not_second' unless sel && sel['proxies'].is_a?(Array) && sel['proxies'][1] == 'ClaudeAuto'
    errs << 'alias_dup' if alias_nodes.size > 1
    errs << 'alias_not_in_auto' unless auto && auto['proxies'].is_a?(Array) && auto['proxies'].include?(ALIAS)
    errs << 'alias_not_in_sel' unless sel && sel['proxies'].is_a?(Array) && sel['proxies'].include?(ALIAS)
  end
else
  errs << 'reject_only_violated' unless sel && sel['proxies'] == ['REJECT']
  errs << 'auto_leaked' if auto
end
errs << 'has_use' if sel && sel.key?('use')
errs << 'has_use' if auto && auto.key?('use')
known = {}
(m['proxies'] || []).each { |p| known[p['name'].to_s] = 1 }
gnames.each { |n| known[n] = 1 }
%w[DIRECT REJECT REJECT-DROP PASS GLOBAL COMPATIBLE].each { |x| known[x] = 1 }
(m['proxy-groups'] || []).each do |g|
  (g['proxies'] || []).each { |x| errs << "dangling:#{g['name']}->#{x}" unless known[x.to_s] }
end
cr = (m['rules'] || []).select { |r| r.is_a?(String) && r.end_with?(',Claude专用') }
errs << 'rule_count' if cr.size != 7
# 6 条域名规则必须占据最前面 6 位（STUN 那条在网段规则之后，不在这个连块里）
errs << 'rule_not_head' if (m['rules'] || []).first(6) != cr[0, 6]
# S7：Anthropic 网段规则必须恰好一条，且紧跟在 6 条域名规则之后
_allr = m['rules'] || []
errs << 'cidr_count' if _allr.count { |r| r.to_s.strip == CLAUDE_CIDR } != 1
errs << 'cidr_pos' unless _allr[6].to_s.strip == CLAUDE_CIDR
# WebRTC/STUN 规则必须恰好一条，紧跟在网段规则之后
errs << 'stun_count' if _allr.count { |r| r.to_s.strip == STUN_RULE } != 1
errs << 'stun_pos' unless _allr[7].to_s.strip == STUN_RULE
# APNs 规则必须恰好一条，紧跟 STUN 之后（第 9 位）：位置错了就会落到
# DOMAIN-SUFFIX,apple.com,DIRECT 后面，等于没改。
errs << 'apns_count' if _allr.count { |r| r.to_s.strip == APNS_RULE } != 1
errs << 'apns_pos' unless _allr[8].to_s.strip == APNS_RULE
_apns = (m['proxy-groups'] || []).find { |g| g.is_a?(Hash) && g['name'] == APNS_G }
errs << 'no_apns_group' unless _apns
if _apns
  errs << 'apns_type' unless _apns['type'] == 'fallback'
  _pm = _apns['proxies']
  errs << 'apns_members' unless _pm.is_a?(Array) && _pm.size >= 2 && _pm.last == 'DIRECT'
end
b2 = Marshal.load(Marshal.dump(b))
# 双侧剥离我们的条目后再比对：输入本身可能已经是注入过的配置
SUF = %w[claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com]
def strip_ours!(x)
  x['proxies'].reject! { |p| p.is_a?(Hash) && p['name'].to_s =~ /\AB[- ]/ } if x['proxies'].is_a?(Array)
  if x['proxy-groups'].is_a?(Array)
    x['proxy-groups'].reject! { |g| g.is_a?(Hash) && (%w[ClaudeAuto Claude专用] + [APNS_G]).include?(g['name']) }
  end
  if x['rules'].is_a?(Array)
    x['rules'].reject! { |r| r.is_a?(String) && r.end_with?(',Claude专用') }
    # APNs 规则以组名结尾，单独剥离
    x['rules'].reject! { |r| r.is_a?(String) && r.strip == APNS_RULE }
    # S7 的 Anthropic 网段规则以 no-resolve 结尾，不属于上面那条，单独剥离
    x['rules'].reject! { |r| r.is_a?(String) && r.strip == CLAUDE_CIDR }
    # 钩子 shell 级应急留下的 6 条 → REJECT 规则也属于我方产物
    x['rules'].reject! do |r|
      r.is_a?(String) && r.end_with?(',REJECT') && SUF.any? { |s| r == "DOMAIN-SUFFIX,#{s},REJECT" }
    end
  end
  x
end
strip_ours!(b2)
strip_ours!(m)
errs << 'airport_a_changed' unless m == b2
if errs.empty?
  puts 'OK'
  exit 0
else
  puts "FAIL #{errs.join(',')}"
  exit 20
end
RUBY

BUILD_MODE=normal
[ "$HAVE_NODES" -eq 1 ] || BUILD_MODE=reject
say "--- build mode=$BUILD_MODE"

$RUBY "$WORK/merge.rb" "$WORK/base.yaml" "$WORK/valid_nodes.yaml" "$WORK/merged.yaml" "$BUILD_MODE" 2>"$WORK/merge.err" \
  || { say "ERROR merge failed: $(head -n 1 "$WORK/merge.err" 2>/dev/null | cut -c1-200)"; BUILD_MODE=reject
       $RUBY "$WORK/merge.rb" "$WORK/base.yaml" /dev/null "$WORK/merged.yaml" reject 2>>"$WORK/merge.err" \
         || { say "ERROR merge(reject) failed, target untouched"; exit 14; } }

CHECK=$($RUBY "$WORK/verify.rb" "$WORK/base.yaml" "$WORK/merged.yaml" "$BUILD_MODE" 2>"$WORK/verify.err")
VR=$?
say "verify=$CHECK"
if [ "$VR" -ne 0 ]; then
  # 结构校验失败：退回 REJECT-only 再试一次（不重试 normal）
  say "--- fallback to reject-only (structural check failed)"
  BUILD_MODE=reject
  $RUBY "$WORK/merge.rb" "$WORK/base.yaml" /dev/null "$WORK/merged.yaml" reject 2>>"$WORK/merge.err" \
    || { say "ERROR reject build failed, target untouched"; exit 14; }
  CHECK=$($RUBY "$WORK/verify.rb" "$WORK/base.yaml" "$WORK/merged.yaml" "$BUILD_MODE" 2>&1)
  VR=$?
  say "verify_fallback=$CHECK"
  [ "$VR" -eq 0 ] || { say "ERROR structural check failed even in reject-only, target untouched"; exit 14; }
fi

SHA_AFTER=$(SHA "$WORK/merged.yaml")
say "sha_built=$SHA_AFTER"

# --------------------------------------------- 4.5 内核校验（可选，带内存门槛）
# 默认关闭。启用条件：CLAUDE_VERIFY_CORE=1 且当前 MemAvailable >= CLAUDE_MIN_MEM_MB
# 说明：GOMEMLIMIT 只是 Go 的软提示，不作为 RSS 硬上限依赖；此处只设 GOGC 降峰值。
# 单次钩子运行最多调用两次内核：normal 失败后才校验 reject-only，不做循环重试。
CORE_BIN="${CLAUDE_CORE_BIN:-/etc/openclash/core/clash_meta}"
CORE_HOME="${CLAUDE_CORE_HOME:-/etc/openclash}"

verify_core() {
  cf="$1"
  [ "${CLAUDE_VERIFY_CORE:-0}" = "1" ] || return 2
  avail=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null); avail=${avail:-0}
  min=${CLAUDE_MIN_MEM_MB:-220}
  if [ "$avail" -lt "$min" ]; then
    log "core-verify skipped: avail=${avail}MB < ${min}MB"
    return 2
  fi
  vd="$WORK/vd"; mkdir -p "$vd"
  for g in Country.mmdb GeoSite.dat ASN.mmdb; do
    [ -f "$CORE_HOME/$g" ] && ln -sf "$CORE_HOME/$g" "$vd/$g"
  done
  : > "$WORK/core.log"
  if command -v timeout >/dev/null 2>&1; then
    GOGC=20 timeout 120 "$CORE_BIN" -t -d "$vd" -f "$cf" >> "$WORK/core.log" 2>&1
  else
    GOGC=20 "$CORE_BIN" -t -d "$vd" -f "$cf" >> "$WORK/core.log" 2>&1
  fi
  if grep -q 'test is successful' "$WORK/core.log"; then return 0; fi
  log "core-verify failed: $(tail -2 "$WORK/core.log" 2>/dev/null | tr '\n' ' ')"
  return 1
}

verify_core "$WORK/merged.yaml"
VRC=$?
case "$VRC" in
  0) say "core-verify=OK" ;;
  2) say "core-verify=skipped" ;;
  1) say "core-verify=FAIL (build=$BUILD_MODE)，退回 REJECT-only"
     BUILD_MODE=reject
     $RUBY "$WORK/merge.rb" "$WORK/base.yaml" /dev/null "$WORK/merged.yaml" reject 2>>"$WORK/merge.err" \
       || { say "ERROR reject build failed, target untouched"; exit 14; }
     CHECK=$($RUBY "$WORK/verify.rb" "$WORK/base.yaml" "$WORK/merged.yaml" "$BUILD_MODE" 2>&1); VR=$?
     say "verify_fallback=$CHECK"
     [ "$VR" -eq 0 ] || { say "ERROR reject-only structural check failed, target untouched"; exit 14; }
     verify_core "$WORK/merged.yaml"
     if [ "$?" -eq 1 ]; then
       say "ERROR 内核校验对降级配置同样失败，拒绝写入（目标未改动）"
       exit 16
     fi
     say "core-verify=OK(reject-only)"
     SHA_AFTER=$(SHA "$WORK/merged.yaml"); say "sha_built=$SHA_AFTER" ;;
esac

if [ "$MODE" = "dryrun" ] || [ "$MODE" = "check" ]; then
  cp "$WORK/merged.yaml" /tmp/claude_inject_dryrun.yaml 2>/dev/null
  say "dry-run: 输出 /tmp/claude_inject_dryrun.yaml（目标未改动）"
  exit 0
fi

# --------------------------------------------------------- 5. 原子写入
DIR=$(dirname "$TARGET")
TMPF="$DIR/.claude_new.$$"
cp "$WORK/merged.yaml" "$TMPF" || { say "ERROR stage failed"; exit 15; }
case "$(ls -l "$TARGET" 2>/dev/null | cut -c1-10)" in
  -rw-------) chmod 600 "$TMPF" 2>/dev/null ;;
  *)          chmod 644 "$TMPF" 2>/dev/null ;;
esac
sync

# 并发保护：构建期间目标文件可能被其他进程（另一次注入、OpenClash 自身）改写。
# 只有最终内容仍基于同一份基线时才允许替换，否则放弃并保留原文件。
TARGET_NOW=$(SHA "$TARGET")
if [ "$TARGET_NOW" != "$SHA_BEFORE" ]; then
  rm -f "$TMPF"
  say "ERROR concurrent modification: expect=$SHA_BEFORE actual=$TARGET_NOW ；已放弃写入，目标保持原样"
  exit 17
fi

mv -f "$TMPF" "$TARGET" || { rm -f "$TMPF"; say "ERROR rename failed"; exit 15; }

SHA_FINAL=$(SHA "$TARGET")
if [ "$SHA_FINAL" != "$SHA_AFTER" ]; then
  say "ERROR post-write sha mismatch final=$SHA_FINAL expect=$SHA_AFTER"
  exit 15
fi
say "===== done sha_after=$SHA_FINAL nodes=$NODE_COUNT mode=$BUILD_MODE"

# 只有真正落到目标文件、且是正常构建时才更新缓存
if [ "$BUILD_MODE" = "normal" ] && [ "$SRC" = "fresh" ]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null
  if cp "$WORK/valid_nodes.yaml" "$CACHE_NODES.tmp" 2>/dev/null && mv -f "$CACHE_NODES.tmp" "$CACHE_NODES" 2>/dev/null; then
    chmod 600 "$CACHE_NODES" 2>/dev/null
    cp "$WORK/fp.txt" "$CACHE_META" 2>/dev/null
    say "cache=updated nodes=$NODE_COUNT"
  else
    say "WARN cache update failed"
  fi
fi
exit 0
