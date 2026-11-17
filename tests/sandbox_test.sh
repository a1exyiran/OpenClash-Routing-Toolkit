#!/bin/sh
# 离线沙盒测试：伪造一棵 /etc/openclash 目录，跑 install.sh / 钩子 / rollback 的完整流程。
# 不碰真实 /etc/openclash，不联网，不需要 root。
#
# 用法：
#   sh tests/sandbox_test.sh                  # 用假的 clash 内核（只打印 test is successful）
#   MIHOMO_BIN=/path/to/mihomo sh tests/sandbox_test.sh   # 用真实 Mihomo 做 -t 校验
#   RUN_SH="busybox ash" sh tests/sandbox_test.sh          # 用 BusyBox ash 跑 install.sh 与 rollback
#
# 依赖：ruby、sha256sum、md5sum。所有地址都是文档保留网段（RFC 5737）。

set -u
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
RUN_SH="${RUN_SH:-sh}"
SB=$(mktemp -d /tmp/octk_sandbox.XXXXXX)
trap 'rm -rf "$SB"' 0
OC="$SB/etc/openclash"
CD="$OC/custom"
mkdir -p "$CD/claude_cache" "$OC/config" "$OC/core" "$SB/etc/init.d"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS  $*"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $*"; }
t()   { _d="$1"; shift; if "$@"; then ok "$_d"; else bad "$_d"; fi; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
snap() { (cd "$SB" && find . -type f -o -type l -o -type d | LC_ALL=C sort | while read -r f; do
           if [ -f "$f" ]; then echo "$f $(sha256sum "$f" | cut -d' ' -f1)"; else echo "$f"; fi
         done); }

# ---- 假 init 脚本
printf '#!/bin/sh\necho "fake openclash $*"\n' > "$SB/etc/init.d/openclash"
chmod 755 "$SB/etc/init.d/openclash"

# ---- 内核
if [ -n "${MIHOMO_BIN:-}" ] && [ -x "$MIHOMO_BIN" ]; then
  cp "$MIHOMO_BIN" "$OC/core/clash_meta"
  echo "core: real mihomo ($("$MIHOMO_BIN" -v | head -n 1))"
else
  cat > "$OC/core/clash_meta" <<'FAKE'
#!/bin/sh
# 假内核：只认 -t -d DIR -f FILE，能被 ruby 解析就算通过
f=""
while [ $# -gt 0 ]; do [ "$1" = "-f" ] && f="$2"; shift; done
ruby -ryaml -e 'Psych.safe_load(File.read(ARGV[0]), aliases: true)' "$f" 2>/dev/null \
  && echo "configuration file $f test is successful" || { echo "test failed"; exit 1; }
FAKE
  echo "core: fake"
fi
chmod 755 "$OC/core/clash_meta"

# ---- 原厂样式钩子（仓库钩子里原厂模板那一段 + exit 0）
_n=$(grep -n 'Claude 专属出口注入' "$REPO/scripts/openclash_custom_overwrite.sh" | head -n 1 | cut -d: -f1)
head -n $((_n - 2)) "$REPO/scripts/openclash_custom_overwrite.sh" > "$CD/openclash_custom_overwrite.sh"
echo "exit 0" >> "$CD/openclash_custom_overwrite.sh"
chmod 755 "$CD/openclash_custom_overwrite.sh"
STOCK_SHA=$(sha "$CD/openclash_custom_overwrite.sh")

# ---- 生效配置（机场 A）
cat > "$OC/config/demo.yaml" <<'YAML'
mixed-port: 7893
allow-lan: true
mode: rule
log-level: info
proxies:
  - {name: "A-HK-01", type: ss, server: 192.0.2.10, port: 8388, cipher: aes-128-gcm, password: placeholder}
  - {name: "A-SG-01", type: ss, server: 192.0.2.11, port: 8388, cipher: aes-128-gcm, password: placeholder}
  - {name: "A-JP-01", type: ss, server: 192.0.2.12, port: 8388, cipher: aes-128-gcm, password: placeholder}
proxy-groups:
  - {name: "节点选择", type: select, proxies: ["自动选择", "A-HK-01", "A-SG-01", "A-JP-01", DIRECT]}
  - {name: "自动选择", type: url-test, url: "http://cp.cloudflare.com/generate_204", interval: 300, proxies: ["A-HK-01", "A-SG-01", "A-JP-01"]}
rules:
  - DOMAIN-SUFFIX,example.com,节点选择
  - DOMAIN-SUFFIX,example.net,节点选择
  - DOMAIN-SUFFIX,example.org,节点选择
  - DOMAIN-KEYWORD,examplekeyword,节点选择
  - DOMAIN,host1.example.com,DIRECT
  - DOMAIN,host2.example.com,DIRECT
  - DOMAIN,host3.example.com,DIRECT
  - DOMAIN-SUFFIX,apple.com,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - MATCH,节点选择
YAML
cp "$OC/config/demo.yaml" "$OC/demo.yaml"
SRC_SHA=$(sha "$OC/config/demo.yaml")

# ---- 节点缓存（机场 B，已校验过的形态）
cat > "$CD/claude_cache/nodes.yaml" <<'YAML'
proxies:
  - {name: "B-美国01", type: ss, server: 198.51.100.20, port: 8388, cipher: aes-128-gcm, password: placeholder, udp: true}
  - {name: "B-日本01", type: ss, server: 198.51.100.21, port: 8388, cipher: aes-128-gcm, password: placeholder, udp: true}
YAML
echo "0000" > "$CD/claude_cache/meta.txt"

# ---- 用户配置
cat > "$SB/config.yaml" <<YAML
claude:
  node_match: "美国01"
  alias: "Claude-Node"
openclash:
  config_path: $OC/config/demo.yaml
  custom_dir: $CD
  core_path: $OC/core/clash_meta
deploy:
  min_mem_available_mb: 1
YAML

export OPENCLASH_ROOT="$OC" OPENCLASH_INIT="$SB/etc/init.d/openclash"
INST() { $RUN_SH "$REPO/install.sh" "$@"; }

echo "== 1. --check"
S0=$(snap)
INST --check --config "$SB/config.yaml" > "$SB/../octk_check.out" 2>&1; rc=$?
t "check exit 0" [ "$rc" -eq 0 ]
t "check wrote nothing" [ "$S0" = "$(snap)" ]
grep -q 'ok: ' "$SB/../octk_check.out" && ok "check parsed config" || bad "check parsed config"
rm -f "$SB/../octk_check.out"

echo "== 2. --dry-run"
INST --dry-run --config "$SB/config.yaml" > "$SB/dry.out" 2>&1; rc=$?
mv "$SB/dry.out" /tmp/octk_dry.out
t "dry-run exit 0" [ "$rc" -eq 0 ]
t "dry-run wrote nothing" [ "$S0" = "$(snap)" ]
grep -q 'clash -t: PASS' /tmp/octk_dry.out && ok "dry-run clash -t PASS" || bad "dry-run clash -t PASS"
grep -q 'build=normal' /tmp/octk_dry.out && ok "dry-run build=normal" || bad "dry-run build=normal"
grep -q 'Claude专用 = Claude-Node' /tmp/octk_dry.out && ok "dry-run alias pinned first" || bad "dry-run alias pinned first"
t "no /tmp work dir left" [ -z "$(ls -d /tmp/octk_install.* 2>/dev/null)" ]

echo "== 3. --apply without --yes (non-interactive)"
INST --apply --config "$SB/config.yaml" < /dev/null > /tmp/octk_noyes.out 2>&1; rc=$?
t "apply w/o --yes exit 5" [ "$rc" -eq 5 ]
t "apply w/o --yes wrote nothing" [ "$S0" = "$(snap)" ]

echo "== 4. --apply --yes"
INST --apply --yes --config "$SB/config.yaml" > /tmp/octk_apply.out 2>&1; rc=$?
t "apply exit 0" [ "$rc" -eq 0 ]
for f in load_config.sh claude_inject.sh claude_update.sh claude_rollback.sh; do
  t "installed $f matches repo" [ "$(sha "$CD/$f")" = "$(sha "$REPO/scripts/$f")" ]
done
t "config.yaml installed 600" [ "$(ls -l "$CD/config.yaml" | cut -c1-10)" = "-rw-------" ]
t "hook has marker" grep -qF '# >>> openclash-routing-toolkit (install.sh) >>>' "$CD/openclash_custom_overwrite.sh"
t "hook syntax ok" sh -n "$CD/openclash_custom_overwrite.sh"
t "orig backup = stock" [ "$(sha "$CD/.claude_backup/openclash_custom_overwrite.sh.orig")" = "$STOCK_SHA" ]
t "orig .md5 recorded" [ "$(cat "$CD/.claude_backup/openclash_custom_overwrite.sh.orig.md5")" = "$(md5sum "$CD/.claude_backup/openclash_custom_overwrite.sh.orig" | cut -d' ' -f1)" ]
t "manifest exists" [ -f "$CD/.claude_backup/install.manifest" ]
BK=$(sed -n 's/^backup_dir=//p' "$CD/.claude_backup/install.manifest")
t "backup SHA256SUMS verifies" sh -c "cd '$BK' && sha256sum -c SHA256SUMS >/dev/null"
t "backup has live config" [ -f "$BK/live_demo.yaml" ] && t "backup has runtime config" [ -f "$BK/run_demo.yaml" ]
t "live source config untouched" [ "$(sha "$OC/config/demo.yaml")" = "$SRC_SHA" ]
t "runtime config untouched by apply" [ "$(sha "$OC/demo.yaml")" = "$SRC_SHA" ]
grep -q 'restart' /tmp/octk_apply.out && ok "prints restart command" || bad "prints restart command"
grep -q 'fake openclash' /tmp/octk_apply.out && bad "did not call init" || ok "did not call init"

echo "== 5. idempotent re-apply"
S1=$(snap)
INST --apply --yes --config "$SB/config.yaml" > /tmp/octk_reapply.out 2>&1; rc=$?
t "re-apply exit 0" [ "$rc" -eq 0 ]
t "re-apply changed nothing" [ "$S1" = "$(snap)" ]
grep -q '无需写入' /tmp/octk_reapply.out && ok "re-apply reports nothing to do" || bad "re-apply reports nothing to do"

echo "== 6. simulated OpenClash start (hook runs offline)"
CLAUDE_HOME_DIR="$CD" CLAUDE_HOOK_OCLOG="$SB/oc.log" CLAUDE_HOOK_LOCK="$SB/hook.lock" \
  sh "$CD/openclash_custom_overwrite.sh" "$OC/demo.yaml" > /dev/null 2>&1; rc=$?
t "hook exit 0" [ "$rc" -eq 0 ]
grep -q 'done level=L1' "$CD/claude_hook.log" && ok "hook level=L1" || bad "hook level=L1"
grep -q 'fetch=skipped(offline)' "$CD/claude_hook.log" "/tmp/claude_inject.log" 2>/dev/null && ok "hook offline" || bad "hook offline"
t "runtime config now has Claude专用" grep -q 'Claude专用' "$OC/demo.yaml"
if "$OC/core/clash_meta" -t -d "$SB" -f "$OC/demo.yaml" 2>&1 | grep -q 'test is successful'; then ok "core -t on injected runtime config"; else bad "core -t on injected runtime config"; fi
CLAUDE_HOME_DIR="$CD" CLAUDE_HOOK_OCLOG="$SB/oc.log" CLAUDE_HOOK_LOCK="$SB/hook.lock" \
  sh "$CD/openclash_custom_overwrite.sh" "$OC/demo.yaml" > /dev/null 2>&1
t "hook re-run keeps one copy of rules" [ "$(grep -c 'claude.ai,Claude专用' "$OC/demo.yaml")" -eq 1 ]

echo "== 7. rollback"
CLAUDE_CFG_DIR="$CD" $RUN_SH "$CD/claude_rollback.sh" > /tmp/octk_rbcheck.out 2>&1; rc=$?
t "rollback check exit 0" [ "$rc" -eq 0 ]
t "rollback check uses manifest md5" grep -q "stock=$(cat "$CD/.claude_backup/openclash_custom_overwrite.sh.orig.md5")" /tmp/octk_rbcheck.out
t "rollback check changed nothing (hook)" grep -qF '# >>> openclash-routing-toolkit' "$CD/openclash_custom_overwrite.sh"
# 直接运行已安装的那份（回滚会删掉它自己，shell 已打开文件，不影响执行）
CLAUDE_CFG_DIR="$CD" $RUN_SH "$CD/claude_rollback.sh" --apply > /tmp/octk_rb.out 2>&1; rc=$?
t "rollback --apply exit 0" [ "$rc" -eq 0 ]
t "hook restored to stock sha256" [ "$(sha "$CD/openclash_custom_overwrite.sh")" = "$STOCK_SHA" ]
t "runtime config stripped" [ "$(grep -c 'Claude专用' "$OC/demo.yaml")" -eq 0 ]
t "airport A groups kept" grep -q '节点选择' "$OC/demo.yaml"
for f in load_config.sh claude_inject.sh claude_update.sh claude_rollback.sh config.yaml; do
  t "removed $f" [ ! -e "$CD/$f" ]
done
t "manifest archived" [ ! -e "$CD/.claude_backup/install.manifest" ]
t "pre-install backup kept" [ -f "$BK/openclash_custom_overwrite.sh" ]
t "live source config still untouched" [ "$(sha "$OC/config/demo.yaml")" = "$SRC_SHA" ]
grep -q 'fake openclash' /tmp/octk_rb.out && bad "rollback did not restart" || ok "rollback did not restart"

echo "== 8. apply again after rollback"
mkdir -p "$CD/claude_cache"
cat > "$CD/claude_cache/nodes.yaml" <<'YAML'
proxies:
  - {name: "B-美国01", type: ss, server: 198.51.100.20, port: 8388, cipher: aes-128-gcm, password: placeholder, udp: true}
YAML
INST --apply --yes --config "$SB/config.yaml" > /tmp/octk_apply2.out 2>&1; rc=$?
t "second apply exit 0" [ "$rc" -eq 0 ]
t "orig still = stock" [ "$(sha "$CD/.claude_backup/openclash_custom_overwrite.sh.orig")" = "$STOCK_SHA" ]

echo "== 9. refuses when hook has toolkit block but no original backup"
rm -f "$CD/.claude_backup/openclash_custom_overwrite.sh.orig"
INST --dry-run --config "$SB/config.yaml" > /tmp/octk_noorig.out 2>&1; rc=$?
t "dry-run refuses without orig backup" [ "$rc" -ne 0 ]

echo "== 10. bad config is refused"
printf 'claude:\n  node_match: ""\n  alias: "X"\n' > "$SB/bad.yaml"
INST --dry-run --config "$SB/bad.yaml" --target "$OC/config/demo.yaml" > /tmp/octk_bad.out 2>&1; rc=$?
t "missing node_match refused" [ "$rc" -ne 0 ]

[ -n "${KEEP_OUT:-}" ] || rm -f /tmp/octk_*.out
echo ""
echo "RESULT PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
