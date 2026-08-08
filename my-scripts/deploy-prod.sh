#!/bin/bash
# deploy-prod.sh — 将本地构建的 grok CLI 部署到生产环境（/usr/local/bin/grok）
#
# 背景：start-dev-cli.sh 只构建本地 debug 产物（target/debug/xai-grok-pager），
#       不影响生产。本脚本负责把该产物安全部署到生产路径，带备份与回滚。
#
# 用法：
#   ./my-scripts/deploy-prod.sh              # 部署现有 debug 产物（不重新构建）
#   ./my-scripts/deploy-prod.sh --build      # 先重新构建再部署
#   ./my-scripts/deploy-prod.sh --rollback   # 回滚到最近一次备份
#   ./my-scripts/deploy-prod.sh --list       # 列出所有备份
#
# 安全特性：
#   - 部署前自动备份现有生产 grok（带时间戳，保留最近 5 份）
#   - 安装前自检产物 --version 可运行
#   - 安装后自检生产 --version 可运行
#   - 全部操作在 sudo 下执行（生产路径属 root）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BIN_NAME="grok"                       # 生产命令名
SRC_BIN="target/debug/xai-grok-pager" # 本地构建产物
PROD_BIN="/usr/local/bin/$BIN_NAME"
BACKUP_DIR="/usr/local/var/grok-backups"
KEEP_BACKUPS=5

# ---- 工具函数 ----
log()  { echo -e "$@"; }
die()  { echo -e "❌ $*" >&2; exit 1; }

sudo_exec() {
    # 若已具备权限直接跑，否则经 sudo（sudo 只在真正需要时提示密码）
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ---- 列出备份 ----
list_backups() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo "（暂无备份）"
    else
        ls -lh "$BACKUP_DIR" | grep -v "^total\|^d" | awk '{print $NF, "("$5")"}'
    fi
}

# ---- 回滚 ----
rollback() {
    local latest
    latest="$(ls -1t "$BACKUP_DIR"/grok.* 2>/dev/null | head -1 || true)"
    [ -n "$latest" ] || die "没有可回滚的备份"
    log "=== 回滚 ==="
    log "使用备份: $latest"
    sudo_exec cp "$latest" "$PROD_BIN"
    sudo_exec chmod +x "$PROD_BIN"
    log "✅ 已回滚。生产 grok 版本："
    "$PROD_BIN" --version
    exit 0
}

# ---- 参数解析 ----
ACTION="deploy"
FORCE_BUILD=0
for a in "$@"; do
    case "$a" in
        --build)    FORCE_BUILD=1 ;;
        --rollback) ACTION="rollback" ;;
        --list)     ACTION="list" ;;
        -h|--help)  sed -n '1,30p' "$0" | grep -E "^# ?[^!]" | sed 's/^# \?//'; exit 0 ;;
        *)          die "未知参数: $a（--build / --rollback / --list / --help）" ;;
    esac
done

case "$ACTION" in
    list)     list_backups; exit 0 ;;
    rollback) rollback ;;
esac

# ---- 平台检查 ----
[ "$(uname -s)" = "Darwin" ] || die "仅支持 macOS"

# ---- 构建（可选）----
if [ "$FORCE_BUILD" = "1" ]; then
    log "=== 重新构建（debug）==="
    cargo build -p xai-grok-pager-bin
else
    log "=== 使用现有 debug 产物（--build 可强制重建）==="
    cargo build -p xai-grok-pager-bin   # 新鲜度判断，有变更才编译
fi

# ---- 产物自检 ----
[ -x "$SRC_BIN" ] || die "未找到构建产物 $SRC_BIN，请先运行构建"
SRC_VERSION="$("./$SRC_BIN" --version 2>/dev/null || true)"
[ -n "$SRC_VERSION" ] || die "产物 --version 无输出，拒绝部署"

# ---- 展示部署计划 ----
log ""
log "=== 部署计划 ==="
log "  源:     ${SRC_BIN}（${SRC_VERSION}）"
log "  目标:   ${PROD_BIN}"
log "  当前:   $("$PROD_BIN" --version 2>/dev/null || echo '（不存在）')"
log ""

# ---- 部署前备份 ----
sudo_exec mkdir -p "$BACKUP_DIR"
if [ -f "$PROD_BIN" ]; then
    BACKUP_NAME="$BACKUP_DIR/grok.$(date +%Y%m%d-%H%M%S)"
    sudo_exec cp "$PROD_BIN" "$BACKUP_NAME"
    log "✅ 已备份旧版 → $BACKUP_NAME"
    # 清理旧备份，保留最近 KEEP_BACKUPS 份
    sudo_exec bash -c "ls -1t '$BACKUP_DIR'/grok.* 2>/dev/null | tail -n +$((KEEP_BACKUPS+1)) | xargs -r rm -f"
else
    log "ℹ️  生产路径尚无 grok，跳过备份"
fi

# ---- 部署 ----
log "=== 安装中（可能需要输入管理员密码）==="
sudo_exec cp "$SRC_BIN" "$PROD_BIN"
sudo_exec chmod +x "$PROD_BIN"
sudo_exec xattr -d com.apple.quarantine "$PROD_BIN" 2>/dev/null || true

# ---- 安装后自检 ----
NEW_VERSION="$("$PROD_BIN" --version 2>/dev/null || true)"
[ -n "$NEW_VERSION" ] || {
    log "❌ 安装后自检失败，尝试自动回滚…"
    "$0" --rollback || true
    exit 1
}

log ""
log "=== ✅ 部署完成 ==="
log "  生产 grok 版本: $NEW_VERSION"
log "  备份位置:       ${BACKUP_DIR}（保留最近 ${KEEP_BACKUPS} 份）"
log ""
log "  验证:  grok --version"
log "  回滚:  $0 --rollback"
