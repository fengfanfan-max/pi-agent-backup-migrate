#!/usr/bin/env bash
# ============================================================
# pi-agent-backup.sh — 一键备份/恢复 pi 的"灵魂"
#   (长期记忆 + 项目记忆 + 历史会话 + 技能 + 扩展 + 配置)
#
# 用法:
#   ./pi-agent-backup.sh backup              # 备份到 ~/pi-agent-backup-<日期>.tar.gz
#   ./pi-agent-backup.sh backup /path/x.tar.gz
#   ./pi-agent-backup.sh restore <tar.gz>    # 恢复到 ~/.pi/agent
#   ./pi-agent-backup.sh list <tar.gz>       # 查看包内容
#
# 安全设计:
#   - auth.json / *.env 密钥文件永不入包
#   - 备份时自动生成 pi-migration-checklist.md 打入包内，
#     列出未入包项和需要用户手动处理的事项，恢复时自动打印
#
# 适用: Windows(Git Bash) / macOS / Linux
# ============================================================
set -euo pipefail

PI_DIR="${HOME}/.pi/agent"
CHECKLIST="pi-migration-checklist.md"
ITEMS=(
  "pi-hermes-memory"   # 长期记忆 (USER.md / MEMORY.md / failures.md)
  "projects-memory"    # 项目级记忆
  "sessions"           # 历史会话存档（含隐私，只走私有传输）
  "skills"             # 技能包
  "extensions"         # 扩展
  "settings.json"      # 设置
  "models-store.json"  # 模型目录缓存
)

err() { echo "❌ $*" >&2; exit 1; }

gen_checklist() {
  local f="$1"
  {
    echo "Pi 迁移清单（由 pi-agent-backup 自动生成）"
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "【未入包项】需要在新机器上手动处理:"
    echo "【1】登录凭据（auth.json 已排除）"
    if [ -f "$PI_DIR/auth.json" ]; then
      echo "本机 auth.json 中包含以下 provider 的凭据（key 本身未导出）:"
      grep -E '^  "' "$PI_DIR/auth.json" 2>/dev/null \
        | sed -E 's/^  "([^"]+)".*/   - \1/' \
        || echo "   (无法解析 auth.json，请自行查看)"
      echo "→ 新机器操作: 启动 pi 后运行 /login 登录对应 provider，或设置 API key 环境变量"
    else
      echo "本机未发现 auth.json（未登录）"
    fi
    echo
    echo "【2】技能/扩展中的密钥文件（*.env 已排除）"
    local envs
    envs=$(find "$PI_DIR/skills" "$PI_DIR/extensions" -name ".env*" -not -name "*.example" 2>/dev/null || true)
    if [ -n "$envs" ]; then
      echo "以下 .env 文件存在于本机但未打包:"
      echo "$envs" | sed "s|$PI_DIR/|   ~/.pi/agent/|"
      echo "→ 新机器操作: 手动复制这些文件，或在对应服务后台重新生成 key"
    else
      echo "本机未发现 .env 密钥文件"
    fi
    echo
    echo "【3】平台相关（npm/、bin/ 不打包，重装 pi 后自动重建）"
    echo "   - 依赖本地二进制的技能（如 vision-tools 的 CLIs）需在新机器重新安装"
    echo "   - 若技能带安装脚本（install-*.sh），在新机器重新执行"
    echo
    echo "【4】本机独立配置（不迁移）"
    local proxy
    proxy=$(git config --global --get http.https://github.com.proxy 2>/dev/null || true)
    if [ -n "$proxy" ]; then
      echo "   - 检测到 git 代理配置: $proxy"
      echo "   - 新机器若需要，执行: git config --global http.https://github.com.proxy $proxy"
    else
      echo "   - 未检测到 git 代理配置"
    fi
    echo "   - shell 别名、终端环境变量等"
    echo
    echo "【已入包】"
    for i in "${ITEMS[@]}"; do
      [ -e "$PI_DIR/$i" ] && echo "   - $i"
    done
  } > "$f"
}

do_backup() {
  local dest="${1:-${HOME}/pi-agent-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
  local tmpd self
  [ -d "$PI_DIR" ] || err "找不到 $PI_DIR"
  self=$(readlink -f "$0" 2>/dev/null || echo "$0")
  tmpd=$(mktemp -d)
  gen_checklist "$tmpd/$CHECKLIST"
  cp "$self" "$tmpd/pi-agent-backup.sh"  # 把脚本自身也打进包，包即自包含
  tar czf "$dest" \
    --exclude=".pi/agent/auth.json" \
    --exclude=".pi/agent/*.env" \
    --exclude=".pi/agent/*.env.*" \
    -C "$HOME" $(for i in "${ITEMS[@]}"; do [ -e "$PI_DIR/$i" ] && echo ".pi/agent/$i"; done) \
    -C "$tmpd" "$CHECKLIST" "pi-agent-backup.sh"
  rm -rf "$tmpd"
  echo "✅ 备份完成: $dest ($(tar tzf "$dest" | wc -l | tr -d ' ') 个文件)"
  echo "🔒 已排除: auth.json、所有 *.env"
  echo "📋 包内含: 迁移清单 + 恢复脚本(自包含，解包即可用)"
  if tar tzf "$dest" | grep -qE "(^|/)\.env($|\.)"; then
    echo "⚠️  警告: 包内仍发现 .env 文件，请检查!"
  fi
  echo "⚠️  提醒: sessions/ 含对话隐私，只走 U盘/AirDrop/NAS 等私有传输"
}

do_restore() {
  local src="$1"
  [ -f "$src" ] || err "备份文件不存在: $src"
  [ -d "$PI_DIR" ] || mkdir -p "$PI_DIR"
  echo "ℹ️  恢复到 $PI_DIR (已有文件将被覆盖)"
  # 若目标机器还没有恢复脚本，先从包里取出来（包是自包含的）
  if [ ! -f "$HOME/pi-agent-backup.sh" ] && tar tzf "$src" | grep -q "^pi-agent-backup.sh$"; then
    tar xzf "$src" -C "$HOME" "pi-agent-backup.sh"
    chmod +x "$HOME/pi-agent-backup.sh"
    echo "📦 已从包内取出恢复脚本: $HOME/pi-agent-backup.sh"
  fi
  tar xzf "$src" -C "$HOME"
  rm -f "$PI_DIR/.pi-hermes-locks.sqlite"* 2>/dev/null || true
  echo "✅ 恢复完成"
  # 打印迁移清单
  if [ -f "$HOME/$CHECKLIST" ]; then
    echo "════════════════════════════════════════════"
    echo "📋 迁移清单（请逐项确认）: $HOME/$CHECKLIST"
    echo "════════════════════════════════════════════"
    cat "$HOME/$CHECKLIST"
  fi
  # 恢复后现场检查
  echo "════════════════════════════════════════════"
  echo "🔍 现场检查:"
  [ -f "$PI_DIR/auth.json" ] && echo "  ✅ auth.json 存在" \
    || echo "  🔑 auth.json 缺失 → 请运行 /login 登录（正常现象）"
  local missing_env
  missing_env=$(find "$PI_DIR/skills" "$PI_DIR/extensions" -name ".env*" -not -name "*.example" 2>/dev/null | head -3 || true)
  [ -n "$missing_env" ] && echo "  🔑 技能 .env 缺失 → 需手动复制（见清单第 2 节）" || echo "  ✅ 无 .env 依赖"
  [ -d "$PI_DIR/bin" ] && echo "  ✅ bin/ 存在" || echo "  ⚠️  bin/ 缺失 → 重装依赖二进制的技能（见清单第 3 节）"
  echo "════════════════════════════════════════════"
  echo "💡 启动 pi 后建议先问: 你知道我的工作经历吗？"
}

do_list() {
  [ -f "$1" ] || err "文件不存在: $1"
  tar tzf "$1"
}

case "${1:-}" in
  backup)  shift; do_backup "${1:-}" ;;
  restore) shift; [ $# -ge 1 ] || err "用法: $0 restore <tar.gz>"; do_restore "$1" ;;
  list)    shift; [ $# -ge 1 ] || err "用法: $0 list <tar.gz>"; do_list "$1" ;;
  *) echo "用法: $0 {backup [dest] | restore <tar.gz> | list <tar.gz>}"; exit 1 ;;
esac
