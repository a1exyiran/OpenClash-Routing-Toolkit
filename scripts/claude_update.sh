#!/bin/sh
# claude_update.sh —— 机场 B 节点更新机制
#
# 用法:
#   claude_update.sh [--check-only] [target_config]
#
# 行为:
#   · 拉取订阅 → 解析校验 → 与缓存指纹比对
#   · 无变化：直接退出 0，不重建配置、不重载
#   · 有变化：重建配置并原子写入目标；缓存同步更新
#   · 拉取失败：保留旧缓存与旧配置，退出非 0
#
# 明确不做:
#   · 不调用 /etc/init.d/openclash restart / reload
#   · 不改 crontab
#   · 不启动第二个 Mihomo 进程
#
# 关于运行期更新（研究结论，未在本阶段执行）:
#   Mihomo 的 PUT /providers/proxies/<name> 只能刷新 proxy-provider，
#   无法修改「内联 proxies」。本方案节点是内联的，因此 API 无法原地换节点。
#   可行的运行期路径是 PUT /configs {"path": "<新配置路径>"}，
#   但该调用会让内核重新加载整份配置，内存峰值与重启相当，
#   在 485MB / 已多次 OOM 的机器上不建议常规使用。
#   因此更新策略定为：改文件 + 由 OpenClash 下次启动自然生效，
#   或由人工在维护窗口执行重启。本脚本只负责把文件改对。

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

VERSION="1.0"
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
INJECT="$SELF_DIR/claude_inject.sh"
CFG_DIR="${CLAUDE_CFG_DIR:-/etc/openclash/custom}"
TARGET="${2:-${1:-}}"

CHECK_ONLY=0
case "${1:-}" in
  --check-only) CHECK_ONLY=1; TARGET="${2:-}" ;;
  --version) echo "claude_update $VERSION"; exit 0 ;;
esac

[ -x "$INJECT" ] || { echo "claude_inject.sh not executable: $INJECT" >&2; exit 2; }
[ -n "$TARGET" ] || { echo "usage: $0 [--check-only] <target_config>" >&2; exit 2; }
[ -f "$TARGET" ] || { echo "target not found: $TARGET" >&2; exit 2; }

echo "== claude_update $VERSION  $(date '+%F %T')"
echo "   target : $TARGET"
echo "   cfgdir : $CFG_DIR"

if [ ! -r "$CFG_DIR/claude_b.yaml" ] && [ -z "${CLAUDE_TEST_RAW:-}" ]; then
  echo "   [WARN] 未找到凭据文件 $CFG_DIR/claude_b.yaml，将只能使用缓存"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  "$INJECT" --check "$TARGET"
  RC=$?
  case "$RC" in
    0)  echo "   结果: 节点无变化" ;;
    10) echo "   结果: 节点有变化（未写入）" ;;
    4)  echo "   结果: 拉取失败，保留旧缓存" ;;
    *)  echo "   结果: 异常 rc=$RC" ;;
  esac
  exit $RC
fi

"$INJECT" --sync "$TARGET"
RC=$?
case "$RC" in
  0)  echo "   结果: 完成（无变化或已更新）" ;;
  4)  echo "   结果: 拉取失败，配置与缓存均保持不变" ;;
  14) echo "   结果: 结构校验失败，目标文件未改动" ;;
  15) echo "   结果: 原子写入失败，目标文件未改动" ;;
  *)  echo "   结果: 异常 rc=$RC" ;;
esac
echo "   提示: 本脚本不改动运行中的内核。配置将在 OpenClash 下次启动时生效。"
exit $RC
