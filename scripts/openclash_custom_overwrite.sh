#!/bin/sh
# OpenClash 原厂辅助函数：在路由器上存在时再加载；本地预览或测试时可缺省。
if [ -f /usr/share/openclash/ruby.sh ]; then
    # shellcheck disable=SC1091
    . /usr/share/openclash/ruby.sh
fi
if [ -f /usr/share/openclash/log.sh ]; then
    # shellcheck disable=SC1091
    . /usr/share/openclash/log.sh
fi
if [ -f /lib/functions.sh ]; then
    # shellcheck disable=SC1091
    . /lib/functions.sh
fi
# 本地没有 OpenClash 日志库时给一个不会报错的回退
if ! type LOG_OUT >/dev/null 2>&1; then
    LOG_OUT() { echo "$*"; }
fi

# This script is called by /etc/init.d/openclash
# Add your custom overwrite scripts here, they will be take effict after the OpenClash own srcipts

LOG_OUT "Tip: Start Running Custom Overwrite Scripts..."
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
LOG_FILE="/tmp/openclash.log"
#Config Path
CONFIG_FILE="$1"

    #Simple Demo:
    #Key Overwrite Demo
    #1--config path
    #2--key name
    #3--value
    #ruby_edit "$CONFIG_FILE" "['redir-port']" "7892"
    #ruby_edit "$CONFIG_FILE" "['secret']" "123456"
    #ruby_edit "$CONFIG_FILE" "['dns']['enable']" "true"
    #ruby_edit "$CONFIG_FILE" "['dns']['proxy-server-nameserver']" "['https://doh.pub/dns-query','https://223.5.5.5:443/dns-query']"

    #Hash Overwrite Demo
    #1--config path
    #2--key name
    #3--hash type value
    #ruby_edit "$CONFIG_FILE" "['dns']['nameserver-policy']" "{'+.msftconnecttest.com'=>'114.114.114.114', '+.msftncsi.com'=>'114.114.114.114', 'geosite:gfw'=>['https://dns.cloudflare.com/dns-query', 'https://dns.google/dns-query#ecs=1.1.1.1/24&ecs-override=true'], 'geosite:cn'=>['114.114.114.114'], 'geosite:geolocation-!cn'=>['https://dns.cloudflare.com/dns-query', 'https://dns.google/dns-query#ecs=1.1.1.1/24&ecs-override=true']}"
    #ruby_edit "$CONFIG_FILE" "['sniffer']" "{'enable'=>true, 'parse-pure-ip'=>true, 'force-domain'=>['+.netflix.com', '+.nflxvideo.net', '+.amazonaws.com', '+.media.dssott.com'], 'skip-domain'=>['+.apple.com', 'Mijia Cloud', 'dlg.io.mi.com', '+.oray.com', '+.sunlogin.net'], 'sniff'=>{'TLS'=>nil, 'HTTP'=>{'ports'=>[80, '8080-8880'], 'override-destination'=>true}}}"

    #Map Edit Demo
    #1--config path
    #2--map name
    #3--key name
    #4--sub key name
    #5--value
    #ruby_map_edit "$CONFIG_FILE" "['proxy-providers']" "HK" "['url']" "http://test.com"

    #Hash Merge Demo
    #1--config path
    #2--key name
    #3--hash
    #ruby_merge_hash "$CONFIG_FILE" "['proxy-providers']" "'TW'=>{'type'=>'http', 'path'=>'./proxy_provider/TW.yaml', 'url'=>'https://gist.githubusercontent.com/raw/tw_clash', 'interval'=>3600, 'health-check'=>{'enable'=>true, 'url'=>'http://cp.cloudflare.com/generate_204', 'interval'=>300}}"
    #ruby_merge_hash "$CONFIG_FILE" "['rule-providers']" "'Reject'=>{'type'=>'http', 'behavior'=>'classical', 'url'=>'https://testingcf.jsdelivr.net/gh/dler-io/Rules@main/Clash/Provider/Reject.yaml', 'path'=>'./rule_provider/Reject', 'interval'=>86400}"

    #Array Edit Demo
    #1--config path
    #2--key name
    #3--match key name
    #4--match key value
    #5--target key name
    #6--target key value
    #ruby_arr_edit "$CONFIG_FILE" "['proxy-groups']" "['name']" "Proxy" "['type']" "Smart"
    #ruby_arr_edit "$CONFIG_FILE" "['dns']['nameserver']" "" "114.114.114.114" "" "119.29.29.29"

    #Array Insert Value Demo:
    #1--config path
    #2--key name
    #3--position(start from 0, end with -1)
    #4--value
    #ruby_arr_insert "$CONFIG_FILE" "['dns']['nameserver']" "0" "114.114.114.114"

    #Array Insert Hash Demo:
    #1--config path
    #2--key name
    #3--position(start from 0, end with -1)
    #4--hash
    #ruby_arr_insert_hash "$CONFIG_FILE" "['proxy-groups']" "0" "{'name'=>'Disney', 'type'=>'select', 'disable-udp'=>false, 'use'=>['TW', 'SG', 'HK']}"
    #ruby_arr_insert_hash "$CONFIG_FILE" "['proxies']" "0" "{'name'=>'HKG 01', 'type'=>'ss', 'server'=>'cc.hd.abc', 'port'=>'12345', 'cipher'=>'aes-128-gcm', 'password'=>'123456', 'udp'=>true, 'plugin'=>'obfs', 'plugin-opts'=>{'mode'=>'http', 'host'=>'microsoft.com'}}"
    #ruby_arr_insert_hash "$CONFIG_FILE" "['listeners']" "0" "{'name'=>'name', 'type'=>'shadowsocks', 'port'=>'12345', 'listen'=>'0.0.0.0', 'rule'=>'sub-rule-1', 'proxy'=>'proxy'}"

    #Array Insert Other Array Demo:
    #1--config path
    #2--key name
    #3--position(start from 0, end with -1)
    #4--array
    #ruby_arr_insert_arr "$CONFIG_FILE" "['dns']['proxy-server-nameserver']" "0" "['https://doh.pub/dns-query','https://223.5.5.5:443/dns-query']"

    #Array Insert From Yaml File Demo:
    #1--config path
    #2--key name
    #3--position(start from 0, end with -1)
    #4--value file path
    #5--value key name in #4 file
    #ruby_arr_add_file "$CONFIG_FILE" "['dns']['fallback-filter']['ipcidr']" "0" "/etc/openclash/custom/openclash_custom_fallback_filter.yaml" "['fallback-filter']['ipcidr']"

    #Delete Array Value Demo:
    #1--config path
    #2--key name
    #3--value
    #ruby_delete "$CONFIG_FILE" "['dns']['nameserver']" "114.114.114.114"

    #Delete Key Demo:
    #1--config path
    #2--key name
    #3--key name
    #ruby_delete "$CONFIG_FILE" "['dns']" "nameserver"
    #ruby_delete "$CONFIG_FILE" "" "dns"

    #Ruby Script Demo:
    #ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e "
    #   begin
    #      Value = YAML.load_file('$CONFIG_FILE');
    #   rescue Exception => e
    #      puts '${LOGTIME} Error: Load File Failed,【' + e.message + '】';
    #   end;

        #General
    #   begin
    #   Thread.new{
    #      Value['redir-port']=7892;
    #      Value['tproxy-port']=7895;
    #      Value['port']=7890;
    #      Value['socks-port']=7891;
    #      Value['mixed-port']=7893;
    #   }.join;

    #   rescue Exception => e
    #      puts '${LOGTIME} Error: Set General Failed,【' + e.message + '】';
    #   ensure
    #      File.open('$CONFIG_FILE','w') {|f| YAML.dump(Value, f)};
    #   end" 2>/dev/null >> $LOG_FILE

# ============================================================================
# Claude 专属出口注入
# ============================================================================
# 说明：
#   本段追加在原厂模板之后，原厂内容（上方全部注释）未作任何改动。
#   原厂文件 MD5: c6fb4a96c1e14ee24ba85682e2e3d367
#   备份文件   : /etc/openclash/custom/openclash_custom_overwrite.sh.orig
#
# 执行时机：
#   /etc/init.d/openclash 第 3685 行，位于 start_run_core 之前。
#   此刻旧内核已停止，7890/7891 不在监听 —— 因此这里只读缓存，绝不联网。
#   订阅拉取由 claude_update.sh 在内核运行时完成，两者职责分离。
#
# 失败分级（逐级降级，任一级通过校验即停）：
#   L1  claude_inject.sh --offline    正常注入
#   L2  钩子内置 Ruby 应急写入        建立 Claude专用=[REJECT] + 6 条规则
#   L3  钩子内置 shell 应急写入      不依赖 Ruby，直接写 6 条 → REJECT 规则
#   L4  三级全败：写 .FAILED 标记 + CRITICAL 日志 + exit 1
#
# 设计约束：
#   1. 不写 /tmp/yaml_openclash_ruby_parse 队列（避免写回无校验）
#   2. 每一级结束后都必须通过结构校验，校验不过视为该级失败并继续降级
#   3. 正常情况退出码为 0，不改变 OpenClash 启动流程
# ============================================================================

CLAUDE_HOME="${CLAUDE_HOME_DIR:-/etc/openclash/custom}"
CLAUDE_INJECT="$CLAUDE_HOME/claude_inject.sh"
CLAUDE_HOOK_LOG="$CLAUDE_HOME/claude_hook.log"
CLAUDE_FAIL_MARK="$CLAUDE_HOME/claude_hook.FAILED"
CLAUDE_OC_LOG="${CLAUDE_HOOK_OCLOG:-$LOG_FILE}"
CLAUDE_LOCK="${CLAUDE_HOOK_LOCK:-/tmp/.claude_hook.lock}"
CLAUDE_TIMEOUT="${CLAUDE_HOOK_TIMEOUT:-180}"
CLAUDE_LOCK_WAIT="${CLAUDE_HOOK_LOCK_WAIT:-15}"
CLAUDE_RUBY_BIN="${CLAUDE_RUBY:-ruby}"
export CLAUDE_CFG_DIR="$CLAUDE_HOME"
# 若同目录有 load_config.sh，尽量带上 alias，便于剥离与注入
if [ -r "$CLAUDE_HOME/load_config.sh" ]; then
    # shellcheck source=load_config.sh
    . "$CLAUDE_HOME/load_config.sh"
    toolkit_load_config >/dev/null 2>&1 || true
elif [ -r "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/load_config.sh" ]; then
    # shellcheck source=load_config.sh
    . "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/load_config.sh"
    toolkit_load_config >/dev/null 2>&1 || true
fi

claude_log() {
    _t=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%s [claude] %s\n' "$_t" "$*" >> "$CLAUDE_HOOK_LOG" 2>/dev/null
    printf '%s [claude] %s\n' "$_t" "$*" >> "$CLAUDE_OC_LOG" 2>/dev/null
}

# 日志上限控制，防止长期运行撑爆 flash
if [ -f "$CLAUDE_HOOK_LOG" ]; then
    _lines=$(wc -l < "$CLAUDE_HOOK_LOG" 2>/dev/null)
    if [ "${_lines:-0}" -gt 400 ]; then
        tail -n 200 "$CLAUDE_HOOK_LOG" > "$CLAUDE_HOOK_LOG.tmp" 2>/dev/null && \
            mv -f "$CLAUDE_HOOK_LOG.tmp" "$CLAUDE_HOOK_LOG" 2>/dev/null
    fi
fi

# ---------------------------------------------------------------------------
# 前置检查
# ---------------------------------------------------------------------------
if [ -z "${CONFIG_FILE:-}" ] || [ ! -f "$CONFIG_FILE" ]; then
    claude_log "ABORT: 配置路径无效 (arg1='${CONFIG_FILE:-}')，跳过注入"
    exit 0
fi

# ---------------------------------------------------------------------------
# 结构校验
#   三种合法终态：
#     normal       Claude专用 = [ClaudeAuto, B-*, ..., REJECT]
#     reject-only  Claude专用 = [REJECT]
#     rules-reject 无 Claude 组，但头部 6 条规则直接指向 REJECT（L3 产物）
#   非法：组缺失/为空/含 DIRECT/COMPATIBLE/尾项不是 REJECT/头部规则不符
# ---------------------------------------------------------------------------
claude_verify() {
    # Ruby 整体不可用时（缺失或被替换），退回纯 shell 校验，
    # 否则 L3 的成果会被误判为失败，进而错误地进入 L4。
    if ! "$CLAUDE_RUBY_BIN" -e 'exit 0' >/dev/null 2>&1; then
        claude_verify_shell
        return $?
    fi
    _rb="/tmp/.claude_vf_$$.rb"
    cat > "$_rb" <<'RUBY'
require 'yaml'
cfg = ARGV[0]
SUFFIX = %w[claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com]
FORBID = %w[DIRECT COMPATIBLE PASS]
def yload(path)
  Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
end
begin
  d = yload(cfg)
rescue Exception => e
  puts "E_LOAD #{e.class}"
  exit 1
end
unless d.is_a?(Hash)
  puts 'E_NOT_HASH'
  exit 1
end
rules = d['rules']
unless rules.is_a?(Array) && rules.size >= SUFFIX.size
  puts 'E_NO_RULES'
  exit 1
end
head = rules.first(SUFFIX.size)
# 形态 2：直接指向 REJECT（L3 产物）
want_r = SUFFIX.each_with_index.map { |s, i| head[i].to_s == "DOMAIN-SUFFIX,#{s},REJECT" }
if want_r.all?
  puts 'verify=OK mode=rules-reject (无组，规则直指 REJECT)'
  exit 0
end
# 形态 1：指向 Claude专用 组
want_g = SUFFIX.each_with_index.map { |s, i| head[i].to_s == "DOMAIN-SUFFIX,#{s},Claude专用" }
unless want_g.all?
  bad = SUFFIX.each_index.reject { |i| want_g[i] }.map { |i| "pos=#{i} got=#{head[i].inspect}" }
  puts "E_RULE #{bad.join(' ')}"
  exit 1
end
g = (d['proxy-groups'] || []).find { |x| x.is_a?(Hash) && x['name'] == 'Claude专用' }
if g.nil?
  puts 'E_NO_GROUP'
  exit 1
end
mem = g['proxies']
if !mem.is_a?(Array) || mem.empty?
  puts 'E_GROUP_EMPTY'
  exit 1
end
bad = mem.select { |m| FORBID.include?(m.to_s) }
unless bad.empty?
  puts "E_FORBIDDEN_MEMBER #{bad.join(',')}"
  exit 1
end
unless mem.last.to_s == 'REJECT'
  puts "E_NO_REJECT_TAIL last=#{mem.last.inspect}"
  exit 1
end
alias_name = ENV['CLAUDE_ALIAS'].to_s
bnodes = (d['proxies'] || []).count { |p| p.is_a?(Hash) && (p['name'].to_s.start_with?('B-') || (!alias_name.empty? && p['name'].to_s == alias_name)) }
mode = (mem.size == 1 && mem.first.to_s == 'REJECT') ? 'reject-only' : 'normal'
puts "verify=OK mode=#{mode} bnodes=#{bnodes} members=#{mem.size} tail=#{mem.last}"
RUBY
    [ -s "$_rb" ] || { rm -f "$_rb"; echo "E_TMP_SCRIPT"; return 1; }
    "$CLAUDE_RUBY_BIN" -ryaml -E UTF-8 "$_rb" "$CONFIG_FILE" 2>&1
    _rc=$?
    rm -f "$_rb"
    return "$_rc"
}

# ---------------------------------------------------------------------------
# 纯 shell 结构校验：只在 Ruby 不可用时使用，覆盖 L3 产物形态
# ---------------------------------------------------------------------------
claude_verify_shell() {
    _ln=$(awk '/^rules:[[:space:]]*$/{print NR; exit}' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$_ln" ] || { echo "E_NO_RULES_ANCHOR"; return 1; }
    _i=1
    for _s in claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com; do
        _line=$(sed -n "$((_ln + _i))p" "$CONFIG_FILE" 2>/dev/null)
        if [ "$_line" != "- DOMAIN-SUFFIX,$_s,REJECT" ]; then
            echo "E_RULE_SHELL pos=$_i got=$_line"
            return 1
        fi
        _i=$((_i + 1))
    done
    echo "verify=OK mode=rules-reject (shell 校验)"
    return 0
}

# ---------------------------------------------------------------------------
# L2 应急：Ruby 写入，建立最小 Fail-Closed 组
# ---------------------------------------------------------------------------
claude_emergency_ruby() {
    _rb="/tmp/.claude_em_$$.rb"
    cat > "$_rb" <<'RUBY'
require 'yaml'
cfg = ARGV[0]
SUFFIX = %w[claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com]
def yload(path)
  Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
end
begin
  d = yload(cfg)
rescue Exception => e
  warn "E_LOAD #{e.class}: #{e.message}"
  exit 1
end
unless d.is_a?(Hash)
  warn 'E_NOT_HASH'
  exit 1
end
d['proxies'] ||= []
d['proxy-groups'] ||= []
d['rules'] ||= []
# 剥离本方案自己注入过的内容，保证幂等（含 L3 留下的 → REJECT 规则）
# 名字识别同时覆盖 B- 前缀与配置中的 claude.alias
ALIAS = ENV['CLAUDE_ALIAS'].to_s
d['proxies'].reject! { |p| p.is_a?(Hash) && (p['name'].to_s.start_with?('B-') || (!ALIAS.empty? && p['name'].to_s == ALIAS)) }
d['proxy-groups'].reject! { |g| g.is_a?(Hash) && %w[ClaudeAuto Claude专用].include?(g['name']) }
d['rules'].reject! { |r| r.is_a?(String) && r.end_with?(',Claude专用') }
d['rules'].reject! do |r|
  r.is_a?(String) && r.end_with?(',REJECT') && SUFFIX.any? { |s| r == "DOMAIN-SUFFIX,#{s},REJECT" }
end
# 只放 REJECT：不引用机场 A 的组，也不出现 DIRECT
d['proxy-groups'].unshift('name' => 'Claude专用', 'type' => 'select', 'proxies' => ['REJECT'])
d['rules'] = SUFFIX.map { |s| "DOMAIN-SUFFIX,#{s},Claude专用" } + d['rules']
tmp = "#{cfg}.claude_em_tmp"
begin
  mode = (File.stat(cfg).mode & 0o777)
  File.open(tmp, 'w') { |f| YAML.dump(d, f) }
  File.chmod(mode, tmp)
  File.rename(tmp, cfg)
rescue Exception => e
  File.delete(tmp) rescue nil
  warn "E_WRITE #{e.class}: #{e.message}"
  exit 1
end
puts 'emergency_ruby=written'
RUBY
    [ -s "$_rb" ] || { rm -f "$_rb"; echo "E_TMP_SCRIPT"; return 1; }
    "$CLAUDE_RUBY_BIN" -ryaml -E UTF-8 "$_rb" "$CONFIG_FILE" 2>&1
    _rc=$?
    rm -f "$_rb"
    return "$_rc"
}

# ---------------------------------------------------------------------------
# L3 应急：纯 shell 写入，不依赖 Ruby / Psych，只依赖 coreutils
#   直接在 rules: 之后插入 6 条 DOMAIN-SUFFIX,<域名>,REJECT
#   REJECT 是内核内置策略，不需要预先定义组，因此这份配置一定可加载
# ---------------------------------------------------------------------------
claude_emergency_shell() {
    _ln=$(awk '/^rules:[[:space:]]*$/{print NR; exit}' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$_ln" ] || { echo "shell_fallback=E_NO_RULES_ANCHOR"; return 1; }
    _tmp="${CONFIG_FILE}.claude_sf.$$"
    # 用子 shell 承载写入，失败只影响子 shell，不会把钩子整体 exit 掉
    (
        head -n "$_ln" "$CONFIG_FILE" || exit 1
        for _s in claude.ai claude.com anthropic.com claude.app claudeusercontent.com claudemcpcontent.com; do
            printf -- '- DOMAIN-SUFFIX,%s,REJECT\n' "$_s" || exit 1
        done
        tail -n "+$((_ln + 1))" "$CONFIG_FILE" || exit 1
    ) > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; echo "shell_fallback=E_WRITE"; return 1; }
    _c=$(grep -c ',REJECT$' "$_tmp" 2>/dev/null)
    if [ "${_c:-0}" -lt 6 ]; then
        rm -f "$_tmp"
        echo "shell_fallback=E_VERIFY count=${_c:-0}"
        return 1
    fi
    _pm=$(ls -l "$CONFIG_FILE" 2>/dev/null | cut -c1-10)
    case "$_pm" in
        -rw-------) chmod 600 "$_tmp" 2>/dev/null ;;
        *)          chmod 644 "$_tmp" 2>/dev/null ;;
    esac
    sync
    mv -f "$_tmp" "$CONFIG_FILE" || { rm -f "$_tmp"; echo "shell_fallback=E_RENAME"; return 1; }
    echo "shell_fallback=written"
    return 0
}

# ---------------------------------------------------------------------------
# 并发锁
#   原则：宁可本次不注入，也绝不与存活的持有者并发写入。
#   · 只有「确认已死」才允许清理僵尸锁；PID 缺失/异常一律保守退出
#   · 等待超时且持有者仍存活 → 退出，不接管、不写配置
#   · 锁文件记录 "pid starttime"，用 /proc/<pid>/stat 第 22 字段识别 PID 复用
# ---------------------------------------------------------------------------
claude_lock_probe() {
    # 输出：ABSENT / ALIVE / DEAD / UNKNOWN
    [ -d "$CLAUDE_LOCK" ] || { echo ABSENT; return 0; }
    [ -f "$CLAUDE_LOCK/pid" ] || { echo UNKNOWN; return 0; }
    _p=""; _st=""
    read -r _p _st < "$CLAUDE_LOCK/pid" 2>/dev/null
    case "${_p:-}" in ''|*[!0-9]*) echo UNKNOWN; return 0 ;; esac
    case "${_st:-}" in *[!0-9]*) echo UNKNOWN; return 0 ;; esac
    if ! kill -0 "$_p" 2>/dev/null; then
        echo DEAD
        return 0
    fi
    # 进程号存在：若记录了启动时刻，用它排除 PID 复用
    if [ -n "${_st:-}" ]; then
        _cur=$(awk '{print $22}' "/proc/$_p/stat" 2>/dev/null)
        if [ -z "$_cur" ]; then
            echo UNKNOWN
        elif [ "$_cur" = "$_st" ]; then
            echo ALIVE
        else
            # 同一 PID 但启动时刻不同 → 原持有者已退出，PID 被复用
            echo DEAD
        fi
        return 0
    fi
    echo ALIVE
    return 0
}

# 清理僵尸锁：删除前二次确认，用 mv 原子摘除后再核对
claude_lock_reap() {
    _snap=$(cat "$CLAUDE_LOCK/pid" 2>/dev/null)
    [ "$(claude_lock_probe)" = "DEAD" ] || return 1
    [ "$(cat "$CLAUDE_LOCK/pid" 2>/dev/null)" = "$_snap" ] || return 1
    _trash="$CLAUDE_LOCK.stale.$$"
    mv "$CLAUDE_LOCK" "$_trash" 2>/dev/null || return 1
    if [ "$(cat "$_trash/pid" 2>/dev/null)" != "$_snap" ]; then
        mv "$_trash" "$CLAUDE_LOCK" 2>/dev/null
        return 1
    fi
    rm -rf "$_trash" 2>/dev/null
    claude_log "已清理僵尸锁（原持有者 $_snap 确认退出）"
    return 0
}

# 返回值：0 拿到 / 1 活锁超时 / 2 僵尸锁清理失败 / 3 状态不可判定
claude_lock_acquire() {
    _i=0
    _absent=0
    while [ "$_i" -lt "$CLAUDE_LOCK_WAIT" ]; do
        if mkdir "$CLAUDE_LOCK" 2>/dev/null; then
            printf '%s %s\n' "$$" "$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null)" \
                > "$CLAUDE_LOCK/pid" 2>/dev/null
            return 0
        fi
        case "$(claude_lock_probe)" in
            ABSENT)
                # mkdir 失败但目录不存在：极小概率的竞态，限次重试防止空转
                _absent=$((_absent + 1))
                [ "$_absent" -le 5 ] || return 3
                continue ;;
            DEAD)
                claude_lock_reap || return 2
                continue ;;
            UNKNOWN)
                return 3 ;;
            *)
                sleep 1
                _i=$((_i + 1)) ;;
        esac
    done
    return 1
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
claude_lock_acquire
CLAUDE_LRC=$?
if [ "$CLAUDE_LRC" -ne 0 ]; then
    case "$CLAUDE_LRC" in
        1) claude_log "CRITICAL 锁被存活实例持有超过 ${CLAUDE_LOCK_WAIT}s，本次不注入、不写配置（避免并发写入）" ;;
        2) claude_log "CRITICAL 僵尸锁清理失败（复核不一致），本次不注入、不写配置" ;;
        3) claude_log "CRITICAL 锁状态无法判定（PID 文件缺失/为空/格式异常），保守退出，本次不注入、不写配置" ;;
        *) claude_log "CRITICAL 获取锁失败(rc=$CLAUDE_LRC)，本次不注入、不写配置" ;;
    esac
    exit 4
fi
# 只有拿到锁的实例才会登记清理，绝不删除他人的锁
trap 'rm -rf "$CLAUDE_LOCK" 2>/dev/null' 0

CLAUDE_SHA0=$(sha256sum "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1)
claude_log "===== start sha_before=${CLAUDE_SHA0:-?} size=$(wc -c < "$CONFIG_FILE" 2>/dev/null)"

# ---- L1：调用注入脚本（带看门狗，避免 Ruby 卡死拖住启动）
CLAUDE_RC=127
if [ ! -f "$CLAUDE_INJECT" ]; then
    claude_log "L1 跳过：注入脚本不存在 $CLAUDE_INJECT"
elif [ ! -r "$CLAUDE_INJECT" ]; then
    claude_log "L1 跳过：注入脚本不可读（权限问题）"
else
    CLAUDE_LOG="$CLAUDE_HOOK_LOG" sh "$CLAUDE_INJECT" --offline "$CONFIG_FILE" \
        >/dev/null 2>>"$CLAUDE_HOOK_LOG" &
    _pid=$!
    _w=0
    while kill -0 "$_pid" 2>/dev/null; do
        if [ "$_w" -ge "$CLAUDE_TIMEOUT" ]; then
            kill -9 "$_pid" 2>/dev/null
            claude_log "L1 超时（>${CLAUDE_TIMEOUT}s），已终止"
            break
        fi
        sleep 1
        _w=$((_w + 1))
    done
    wait "$_pid" 2>/dev/null
    CLAUDE_RC=$?
    claude_log "L1 inject rc=$CLAUDE_RC elapsed=${_w}s"
fi

# ---- 校验 L1 结果
if [ "$CLAUDE_RC" -eq 0 ]; then
    CLAUDE_VOUT=$(claude_verify)
    if [ "$?" -eq 0 ]; then
        claude_log "$CLAUDE_VOUT"
        rm -f "$CLAUDE_FAIL_MARK" 2>/dev/null
        CLAUDE_SHA1=$(sha256sum "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1)
        claude_log "===== done level=L1 sha_before=$CLAUDE_SHA0 sha_after=$CLAUDE_SHA1"
        exit 0
    fi
    claude_log "L1 结果校验失败：$CLAUDE_VOUT"
else
    claude_log "L1 未成功（rc=$CLAUDE_RC），进入 L2"
fi

# ---- L2：内置 Ruby 应急
CLAUDE_EOUT=$(claude_emergency_ruby)
CLAUDE_ERC=$?
if [ "$CLAUDE_ERC" -eq 0 ]; then
    claude_log "L2 $CLAUDE_EOUT"
    CLAUDE_VOUT=$(claude_verify)
    if [ "$?" -eq 0 ]; then
        claude_log "$CLAUDE_VOUT"
        rm -f "$CLAUDE_FAIL_MARK" 2>/dev/null
        CLAUDE_SHA1=$(sha256sum "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1)
        claude_log "===== done level=L2 sha_before=$CLAUDE_SHA0 sha_after=$CLAUDE_SHA1"
        exit 0
    fi
    claude_log "L2 结果校验失败：$CLAUDE_VOUT"
else
    claude_log "L2 失败（rc=$CLAUDE_ERC）：$CLAUDE_EOUT"
fi

# ---- L3：纯 shell 应急（Ruby 整体不可用时的最后一道）
CLAUDE_SOUT=$(claude_emergency_shell)
CLAUDE_SRC=$?
if [ "$CLAUDE_SRC" -eq 0 ]; then
    claude_log "L3 $CLAUDE_SOUT"
    CLAUDE_VOUT=$(claude_verify)
    if [ "$?" -eq 0 ]; then
        claude_log "$CLAUDE_VOUT"
        rm -f "$CLAUDE_FAIL_MARK" 2>/dev/null
        CLAUDE_SHA1=$(sha256sum "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1)
        claude_log "===== done level=L3 sha_before=$CLAUDE_SHA0 sha_after=$CLAUDE_SHA1"
        exit 0
    fi
    claude_log "L3 结果校验失败：$CLAUDE_VOUT"
else
    claude_log "L3 失败（rc=$CLAUDE_SRC）：$CLAUDE_SOUT"
fi

# ---- L4：三级全败。无法写入任何 Claude 规则，必须显著留痕
{
    echo "time=$(date '+%F %T')"
    echo "config=$CONFIG_FILE"
    echo "sha=$CLAUDE_SHA0"
    echo "reason=L1/L2/L3 all failed; Claude 规则未能写入，流量可能进入默认策略"
} > "$CLAUDE_FAIL_MARK" 2>/dev/null
claude_log "CRITICAL 三级注入全部失败，已写入 $CLAUDE_FAIL_MARK；Claude 相关流量可能落回默认策略，请立即人工处理"
claude_log "CRITICAL 排查顺序：1) $CLAUDE_HOME 写权限 2) /tmp 空间 3) ruby 可用性 4) 配置内是否存在 rules: 锚点"
exit 1
