#!/usr/bin/env bash
# ============================================================================
# deploy-local.sh — Grok Build 本地部署
#
# 将 wkj-dev 二开分支的 Rust 源码构建并安装到本地环境。
# 部署后 `grok` 命令指向本地二开分支编译的二进制。
#
# 用法:
#   ./deploy-local.sh                          # 完整部署（release 构建 + 复制到 PATH）
#   ./deploy-local.sh --debug                  # debug 构建（更快，适合迭代）
#   ./deploy-local.sh /custom/path/grok        # 安装到自定义路径
#   ./deploy-local.sh build                    # 仅构建（不安装）
#   ./deploy-local.sh verify                   # 仅验证
#   ./deploy-local.sh help                     # 显示帮助
#
# 前置条件:
#   - Rust toolchain（rust-toolchain.toml 自动管理版本）
#   - protoc（通过 bin/protoc dotslash 或 PATH 中的 protoc）
#   - dotslash（bin/protoc 依赖）：cargo install dotslash
#   - 当前在 wkj-dev 分支（或设置 GROK_ALLOW_BRANCH=1 跳过检查）
#
# 效果:
#   cargo build --release -p xai-grok-pager-bin
#   将 target/release/xai-grok-pager 复制为 grok 到 PATH
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

show_help() {
  sed -n '2,/^set -euo/p' "$0" | grep -E '^#' | sed 's/^# \?//'
  exit 0
}

# ─── 前置检查 ───
check_prereqs() {
  echo "━━━ 检查前置条件 ━━━"

  # Rust
  if ! command -v rustc &>/dev/null; then
    log_error "未找到 Rust。请安装: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
  fi
  log_info "Rust $(rustc --version | awk '{print $2}')"
  log_info "Cargo $(cargo --version | awk '{print $2}')"

  # dotslash（bin/protoc 需要）
  if ! command -v dotslash &>/dev/null; then
    log_warn "dotslash 未安装（bin/protoc 运行需要）"
    echo "   安装: cargo install dotslash"
    echo "   或确保 protoc 在 PATH 中"
  else
    log_info "dotslash $(dotslash --version 2>/dev/null || echo '已安装')"
  fi

  # 分支检查
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo '')"
  if [ "$branch" != "wkj-dev" ]; then
    log_warn "当前分支: $branch（期望: wkj-dev）"
    if [ "${GROK_ALLOW_BRANCH:-}" != "1" ]; then
      echo "   使用 git checkout wkj-dev 切换分支，或设置 GROK_ALLOW_BRANCH=1 跳过检查"
      exit 1
    fi
    log_warn "GROK_ALLOW_BRANCH=1 已设置，跳过分支检查"
  else
    log_info "当前分支: wkj-dev ✅"
  fi
}

# ─── 构建 ───
do_build() {
  local profile="${1:-release}"
  echo ""
  echo "━━━ 构建 Grok Build（$profile）━━━"
  local start
  start="$(date +%s)"

  if [ "$profile" = "release" ]; then
    cargo build --release -p xai-grok-pager-bin 2>&1 | sed 's/^/      /'
    BIN="target/release/xai-grok-pager"
  else
    cargo build -p xai-grok-pager-bin 2>&1 | sed 's/^/      /'
    BIN="target/debug/xai-grok-pager"
  fi

  local end
  end="$(date +%s)"
  log_info "构建完成（$((end - start))s）"

  # 验证产物
  if [ -f "$BIN" ]; then
    local ver
    ver="$("$BIN" --version 2>/dev/null || echo 'N/A')"
    log_info "产物验证: $BIN（$ver）"
  else
    log_error "构建失败: $BIN 未生成"
    exit 1
  fi
}

# ─── 安装到 PATH ───
do_install() {
  local profile="${1:-release}"
  local target="$2"
  local src

  if [ "$profile" = "release" ]; then
    src="target/release/xai-grok-pager"
  else
    src="target/debug/xai-grok-pager"
  fi

  if [ ! -f "$src" ]; then
    log_error "二进制未找到: $src，请先构建"
    exit 1
  fi

  echo ""
  echo "━━━ 安装 grok → $target ━━━"

  local target_dir
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"

  if [ ! -w "$target_dir" ]; then
    sudo cp -f "$src" "$target"
    sudo chmod +x "$target"
    log_info "已安装（sudo）: $target"
  else
    cp -f "$src" "$target"
    chmod +x "$target"
    log_info "已安装: $target"
  fi

  log_info "大小: $(ls -lh "$target" | awk '{print $5}')"
}

# ─── 确定安装目标 ───
resolve_target() {
  local custom="${1:-}"

  # 如果传入了自定义路径，直接使用
  if [ -n "$custom" ] && [ "$custom" != "build" ] && [ "$custom" != "verify" ] && [ "$custom" != "help" ]; then
    echo "$custom"
    return
  fi

  # 检测 PATH 中已存在的 grok
  if which grok &>/dev/null; then
    which grok
    return
  fi

  # 默认安装路径
  if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    echo "/usr/local/bin/grok"
  else
    echo "$HOME/.local/bin/grok"
  fi
}

# ─── 验证 ───
do_verify() {
  echo ""
  echo "━━━ 部署验证 ━━━"
  echo "  分支:     $(git branch --show-current)"
  echo "  grok 路径: $(which grok 2>/dev/null || echo '未安装')"
  echo "  Rust:     $(rustc --version | awk '{print $2}')"
  echo ""
  echo "  试运行: grok --version"
  echo "  或运行: grok 进入交互模式（首次需 x.ai OAuth 认证）"
}

# ─── 主流程 ───
main() {
  local profile="release"
  local args=()

  for a in "$@"; do
    case "$a" in
      --debug) profile="debug" ;;
      *) args+=("$a") ;;
    esac
  done

  set -- "${args[@]}"

  local cmd="${1:-full}"

  case "$cmd" in
    full)
      check_prereqs
      do_build "$profile"
      local target
      target="$(resolve_target "${2:-}")"
      do_install "$profile" "$target"
      do_verify
      ;;
    build)
      check_prereqs
      do_build "$profile"
      do_verify
      ;;
    verify)
      do_verify
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      check_prereqs
      do_build "$profile"
      do_install "$profile" "$cmd"
      do_verify
      ;;
  esac
}

main "$@"
