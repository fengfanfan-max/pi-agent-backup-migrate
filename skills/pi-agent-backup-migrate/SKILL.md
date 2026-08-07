---
name: "pi-agent-backup-migrate"
description: "备份/恢复/迁移 pi 编码代理的完整状态（长期记忆、项目记忆、历史会话、技能、扩展、配置）到另一台机器。跨平台：Windows(Git Bash)/macOS/Linux 通用。"
version: 3
created: "2026-08-07"
updated: "2026-08-07"
---
## When to Use
用户要把 pi 迁移到新机器（如 Windows → Mac Studio）、定期备份 agent 状态、或恢复备份时使用。数据层（记忆/会话/技能）是纯文本，天然可移植；平台层（npm/、bin/ 二进制）不打包，新机器重装。

## Procedure
1. 确认目标机器：新机器先装 Node.js（nvm 或 Homebrew）和 pi（npm install -g --ignore-scripts @earendil-works/pi-coding-agent 或 curl -fsSL https://pi.dev/install.sh | sh）。
2. 在原机器上用下面的脚本做备份（脚本自包含，可现场写入 pi-agent-backup.sh 后执行）。备份包是自包含的：数据 + 迁移清单 + 恢复脚本都在一个 tar.gz 里：

```bash
#!/usr/bin/env bash
set -euo pipefail
PI_DIR="${HOME}/.pi/agent"
CHECKLIST="pi-migration-checklist.md"
ITEMS=(pi-hermes-memory projects-memory sessions skills extensions settings.json models-store.json)

gen_checklist() {
  local f="$1"
  {
    echo "Pi 迁移清单（由 pi-agent-backup 自动生成）"
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "【未入包项】需要在新机器上手动处理:"
    echo "【1】登录凭据（auth.json 已排除）"
    if [ -f "$PI_DIR/auth.json" ]; then
      echo "本机 auth.json 中包含以下 provider 的凭据（key 本身未导出）:"
      grep -E '^  "' "$PI_DIR/auth.json" 2>/dev/null | sed -E 's/^  "([^"]+)".*/   - \1/' || echo "   (无法解析)"
      echo "→ 新机器操作: 启动 pi 后运行 /login 登录对应 provider，或设置 API key 环境变量"
    else
      echo "本机未发现 auth.json（未登录）"
    fi
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
    echo "【3】平台相关（npm/、bin/ 不打包，重装 pi 后自动重建）"
    echo "   - 依赖本地二进制的技能（如 vision-tools CLIs）需在新机器重新安装"
    echo "【4】本机独立配置（不迁移）"
    local proxy
    proxy=$(git config --global --get http.https://github.com.proxy 2>/dev/null || true)
    [ -n "$proxy" ] && echo "   - 检测到 git 代理配置: $proxy → 新机器若需要: git config --global http.https://github.com.proxy $proxy" || echo "   - 未检测到 git 代理配置"
    echo "【已入包】"
    for i in "${ITEMS[@]}"; do [ -e "$PI_DIR/$i" ] && echo "   - $i"; done
  } > "$f"
}

case "${1:-}" in
  backup)
    dest="${2:-${HOME}/pi-agent-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
    [ -d "$PI_DIR" ] || { echo "❌ 找不到 $PI_DIR"; exit 1; }
    self=$(readlink -f "$0" 2>/dev/null || echo "$0")
    tmpd=$(mktemp -d) && gen_checklist "$tmpd/$CHECKLIST" && cp "$self" "$tmpd/pi-agent-backup.sh"
    tar czf "$dest" --exclude=".pi/agent/auth.json" --exclude=".pi/agent/*.env" --exclude=".pi/agent/*.env.*" \
      -C "$HOME" $(for i in "${ITEMS[@]}"; do [ -e "$PI_DIR/$i" ] && echo ".pi/agent/$i"; done) \
      -C "$tmpd" "$CHECKLIST" "pi-agent-backup.sh"
    rm -rf "$tmpd"
    echo "✅ 备份完成: $dest; 🔒 已排除 auth.json 和 *.env; 📋 含迁移清单+恢复脚本(自包含)" ;;
  restore)
    [ -f "${2:-}" ] || { echo "用法: $0 restore <tar.gz>"; exit 1; }
    mkdir -p "$PI_DIR"
    if [ ! -f "$HOME/pi-agent-backup.sh" ] && tar tzf "$2" | grep -q "^pi-agent-backup.sh$"; then
      tar xzf "$2" -C "$HOME" "pi-agent-backup.sh" && chmod +x "$HOME/pi-agent-backup.sh"
      echo "📦 已从包内取出恢复脚本: $HOME/pi-agent-backup.sh"
    fi
    tar xzf "$2" -C "$HOME"
    rm -f "$PI_DIR/.pi-hermes-locks.sqlite"* 2>/dev/null || true
    echo "✅ 恢复完成"
    [ -f "$HOME/$CHECKLIST" ] && { echo "📋 迁移清单:"; cat "$HOME/$CHECKLIST"; }
    [ -f "$PI_DIR/auth.json" ] && echo "✅ auth.json 存在" || echo "🔑 auth.json 缺失 → 请运行 /login 登录（正常现象）"
    [ -d "$PI_DIR/bin" ] && echo "✅ bin/ 存在" || echo "⚠️ bin/ 缺失 → 重装依赖二进制的技能（见清单【3】）"
    echo "💡 启动 pi 后建议先问: 你知道我的工作经历吗？" ;;
  list) tar tzf "${2:-}" ;;
  *) echo "用法: $0 {backup [dest] | restore <tar.gz> | list <tar.gz>}"; exit 1 ;;
esac
```
3. 传输备份包：只用私有介质（U盘/AirDrop/自建NAS/SSH/scp），禁止公有网盘和公有 GitHub。
4. 新机器恢复（包是自包含的，无需单独带脚本）：先解包取得脚本 tar xzf 备份.tar.gz，再执行 bash ~/pi-agent-backup.sh restore 备份.tar.gz；脚本会自动打印《迁移清单》并现场检查（auth.json 缺失→提示 /login；bin/ 缺失→提示重装技能二进制）。
5. 按清单逐项处理未入包内容：① /login 登录各 provider；② 手动复制技能 .env 或在服务后台重新生成 key；③ 重装依赖二进制的技能（如 vision-tools）；④ 按需重配 git 代理。
6. 验证：新机器启动 pi 后询问'你知道我的工作经历吗'，能答出即迁移成功；确认技能（anysearch/vision-tools 等）已加载。
## Pitfalls
- 不要打包 ~/.pi/agent/npm/ 和 bin/（平台依赖，新机器重装 pi 后自动重建）。
- auth.json 含明文 API key，永远排除（每台机器各自 /login）；技能目录的 .env 同理排除。
- sessions/ 含对话隐私（手机号/邮箱/代码片段），只能走私有传输介质，绝不推公有云。
- 不要用坚果云/Syncthing 等对 ~/.pi/agent 整目录做双向实时同步：记忆扩展用 SQLite(WAL)，双机并发会锁冲突。
- 恢复后需删除 .pi-hermes-locks.sqlite* 锁文件（会自动重建），避免与旧机器状态冲突。
- Windows 上 bash 为 Git Bash/MSYS2；备份/恢复命令中的 ~ 路径会自动映射，无需额外处理。

## Verification
1. 备份包生成后用 list 命令检查：不含 auth.json、*.env，包含 pi-hermes-memory/ 和 sessions/。
2. 恢复后 ~/.pi/agent 下出现 pi-hermes-memory、projects-memory、sessions、skills 目录。
3. 新机器 pi 中 session_search 能搜到旧会话、memory_search 能搜到旧记忆条目。
4. 问'你知道我的工作经历吗'能正确回答（记忆验证）。