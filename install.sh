#!/bin/sh
# OpenClash Routing Toolkit — install outline
#
# 当前状态：提纲 + 有限的只读检测。写入、安装、重启均为「待实现」。
# 不要把本脚本当成已完成的安装器。完整门禁见 AGENTS.md。
#
# 用法：
#   ./install.sh --help
#   ./install.sh --check              # 只读探测本机（若在路由器上运行）
#   ./install.sh --dry-run --config FILE   # 待实现
#   ./install.sh --apply              # 明确拒绝：尚未实现

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

usage() {
  cat <<'EOF'
OpenClash Routing Toolkit installer (outline)

  --help              显示说明
  --check             只读探测：系统、内存、OpenClash 目录、内核二进制、Ruby
  --dry-run --config FILE
                      待实现：按用户配置在临时目录构建并校验，不写生效配置
  --apply             待实现：本版本会拒绝执行

在实现完成前，请让 AI 助手阅读 AGENTS.md，先做检查并征求你的同意。
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

cmd_check() {
  echo "== only-read probe  $(date '+%F %T' 2>/dev/null || true)"
  echo "-- os"
  if [ -f /etc/openwrt_release ]; then
    # 不把整个文件里可能存在的设备描述以外的内容扩展出去；这里只读发行版标识
    grep -E '^(DISTRIB_ID|DISTRIB_RELEASE|DISTRIB_REVISION)=' /etc/openwrt_release 2>/dev/null || cat /etc/openwrt_release
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
  if [ -x /etc/init.d/openclash ]; then
    echo "init: /etc/init.d/openclash exists"
  else
    echo "unconfirmed: /etc/init.d/openclash not found (maybe not on the router)"
  fi
  if [ -d /etc/openclash ]; then
    echo "dir: /etc/openclash exists"
  else
    echo "unconfirmed: /etc/openclash not found"
  fi
  if [ -x /etc/openclash/core/clash_meta ] || [ -x /etc/openclash/clash ]; then
    echo "core: binary present"
    # 待实现：以只读、不加载用户配置的方式打印内核版本
  else
    echo "unconfirmed: Mihomo/clash binary not found at common paths"
  fi
  echo "-- ruby"
  if have ruby; then
    ruby -v
  else
    echo "unconfirmed: ruby not in PATH"
  fi
  echo "-- config file for this toolkit"
  echo "not checked here; pass --dry-run --config FILE when that command is implemented"
  echo
  echo "check finished. no files were written."
  echo "next: read AGENTS.md; do not run --apply (not implemented)."
}

MODE=help
CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) MODE=help ;;
    --check) MODE=check ;;
    --dry-run) MODE=dryrun ;;
    --apply) MODE=apply ;;
    --config) CONFIG="${2:-}"; shift ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  help) usage; exit 0 ;;
  check) cmd_check; exit 0 ;;
  dryrun)
    echo "待实现: --dry-run"
    echo "计划中的行为：读取 ${CONFIG:-MISSING_CONFIG}，在临时目录构建配置，不覆盖 /etc/openclash 下的生效文件，必要时调用 clash -t。"
    echo "通用配置解析尚未落地，拒绝假装执行。"
    exit 3
    ;;
  apply)
    echo "待实现: --apply 尚未实现，已拒绝执行。"
    echo "不要把 scripts/ 下的工作脚本当成已经完成的一键安装器。"
    exit 3
    ;;
esac
