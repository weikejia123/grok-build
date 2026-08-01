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
#   ./deploy-local.sh verify                   # 仅验证（检测运行的版本是否为本地的）
#   ./deploy-local.sh help                     # 显示帮助
#
# 验证机制:
#   构建时记录 git SHA + 二进制 stat
#   安装后通过 stat 比对 mtime/size 确认是刚刚构建的版本
#   运行 grok --version 确认可执行
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
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

show_help() {
  sed -n '2,/^set -euo/p' "$0" | grep -E '^#' | sed 's/^# \?//'
  exit 0
}

# ─── 构建标记 ───
DEPLOY_MARKER=".deploy-marker"

write_marker() {
  local sha branch time profile="$1"
  sha="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
  branch="$(git branch --show-current 2>/dev/null || echo 'unknown')"
  time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local bin_path="target/${profile}/xai-grok-pager"
  local bin_stat=""
  if [ -f "$bin_path" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      bin_stat="$(stat -f "%m|%z|%N" "$bin_path" 2>/dev/null || echo '')"
    else
      bin_stat="$(stat -c "%Y|%s|%n" "$bin_path" 2>/dev/null || echo '')"
    fi
  fi

  cat > "$DEPLOY_MARKER" <<EOF
SHA=$sha
BRANCH=$branch
BUILD_TIME=$time
PROFILE=$profile
BIN_PATH=$bin_path
BIN_STAT=$bin_stat
EOF
  log_info "构建标记已写入: $DEPLOY_MARKER"
  cat "$DEPLOY_MARKER" | sed 's/^/      /'
}

read_marker() {
  local key="$1"
  grep "^${key}=" "$DEPLOY_MARKER" 2>/dev/null | cut -d= -f2 || echo "unknown"
}

# ─── 前置检查 ───
check_prereqs() {
  log_step "检查前置条件"

  if ! command -v rustc &>/dev/null; then
    log_error "未找到 Rust。请安装: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
  fi
  log_info "Rust $(rustc --version | awk '{print $2}')"
  log_info "Cargo $(cargo --version | awk '{print $2}')"

  if ! command -v dotslash &>/dev/null; then
    log_warn "dotslash 未安装（bin/protoc 运行需要）"
    echo "   安装: cargo install dotslash"
    echo "   或确保 protoc 在 PATH 中"
  else
    log_info "dotslash 已安装"
  fi

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
  log_step "Build Grok ($profile)"
  local start
  start="$(date +%s)"

  if [ "$profile" = "release" ]; then
    cargo build --release -p xai-grok-pager-bin 2>&1 | sed 's/^/      /'
  else
    cargo build -p xai-grok-pager-bin 2>&1 | sed 's/^/      /'
  fi

  local end
  end="$(date +%s)"
  log_info "构建完成（$((end - start))s）"

  local bin_path="target/${profile}/xai-grok-pager"
  if [ -f "$bin_path" ]; then
    local ver
    ver="$("$bin_path" --version 2>/dev/null || echo 'N/A')"
    log_info "Binary: $bin_path ($ver)"
    ls -lh "$bin_path" | awk '{print "      size:", $5}'
  else
    log_error "构建失败: $bin_path 未生成"
    exit 1
  fi

  write_marker "$profile"
}

# ─── 安装到 PATH ───
do_install() {
  local profile="${1:-release}"
  local target="$2"
  local src="target/${profile}/xai-grok-pager"

  if [ ! -f "$src" ]; then
    log_error "二进制未找到: $src，请先构建"
    exit 1
  fi

  log_step "安装 grok → $target"

  local target_dir
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"

  if [ ! -w "$target_dir" ]; then
    sudo -n cp -f "$src" "$target" 2>/dev/null || sudo cp -f "$src" "$target"
    sudo -n chmod +x "$target" 2>/dev/null || sudo chmod +x "$target"
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

  if [ -n "$custom" ] && [ "$custom" != "build" ] && [ "$custom" != "verify" ] && [ "$custom" != "help" ]; then
    echo "$custom"
    return
  fi

  if which grok &>/dev/null; then
    local existing
    existing="$(which grok)"
    local existing_dir
    existing_dir="$(dirname "$existing")"
    if [ -w "$existing_dir" ]; then
      echo "$existing"
      return
    fi
    # 不可写但有 sudoers 免密，仍用此路径并通过 sudo 安装
    if sudo -n true 2>/dev/null; then
      echo "$existing"
      return
    fi
    log_warn "已有路径 $existing_dir 不可写且无 sudo，尝试 ~/.local/bin"
  fi

  local fallback="$HOME/.local/bin/grok"
  mkdir -p "$HOME/.local/bin"
  echo "$fallback"
}

# ─── 验证部署 ───
verify_deployment() {
  log_step "验证部署"

  local errors=0

  if ! command -v grok &>/dev/null; then
    log_error "grok 命令不存在！"
    return 1
  fi
  log_info "grok 命令存在 ✅"

  local cmd_path
  cmd_path="$(which grok 2>/dev/null || true)"
  log_info "命令路径: $cmd_path"

  if [ -f "$DEPLOY_MARKER" ]; then
    local marker_bin_path
    marker_bin_path="$(read_marker BIN_PATH)"

    if [ -n "$marker_bin_path" ] && [ -f "$marker_bin_path" ]; then
      local marker_stat
      marker_stat="$(read_marker BIN_STAT)"

      local actual_stat=""
      if [ -f "$cmd_path" ]; then
        if [ "$(uname)" = "Darwin" ]; then
          actual_stat="$(stat -f "%m|%z|%N" "$cmd_path" 2>/dev/null || echo '')"
        else
          actual_stat="$(stat -c "%Y|%s|%n" "$cmd_path" 2>/dev/null || echo '')"
        fi
      fi

      local marker_mtime="${marker_stat%%|*}"
      local actual_mtime="${actual_stat%%|*}"

      if [ "$marker_stat" = "$actual_stat" ]; then
        log_info "二进制 stat 匹配: 安装的正是刚刚构建的版本 ✅"
      elif [ "$marker_mtime" = "$actual_mtime" ]; then
        log_info "二进制 mtime 匹配 ✅"
      else
        log_warn "二进制 stat 不匹配 — 可能是旧版本"
        errors=$((errors + 1))
      fi
    fi
  fi

  log_info "执行 grok --version..."
  local version_output
  version_output="$(grok --version 2>&1 || echo 'N/A')"
  log_info "版本输出: $version_output"

  if [ -f "$DEPLOY_MARKER" ]; then
    local marker_sha current_sha
    marker_sha="$(read_marker SHA)"
    current_sha="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"

    if [ "$marker_sha" = "$current_sha" ]; then
      log_info "SHA 验证: $marker_sha ✅（与当前 HEAD 一致）"
    else
      log_warn "SHA 验证: 标记 $marker_sha ≠ 当前 $current_sha"
    fi
  fi

  echo ""
  if [ "$errors" -eq 0 ]; then
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ 部署验证通过！运行的正是 wkj-dev 本地版本${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
  else
    echo -e "${YELLOW}⚠  部署完成但有 $errors 个警告${NC}"
  fi
  echo "  命令:  $(which grok)"
  echo "  版本:  $version_output"
  echo "  分支:  $(git branch --show-current)"
  echo "  SHA:   $(git rev-parse HEAD | head -c 12)"
}

# ─── 清理标记 ───
cleanup() {
  rm -f "$DEPLOY_MARKER"
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

  if [ ${#args[@]} -gt 0 ]; then
    set -- "${args[@]}"
  else
    set --
  fi
  local cmd="${1:-full}"

  case "$cmd" in
    full)
      check_prereqs
      do_build "$profile"
      local target
      target="$(resolve_target "${2:-}")"
      do_install "$profile" "$target"
      verify_deployment
      ;;
    build)
      check_prereqs
      do_build "$profile"
      ;;
    verify)
      verify_deployment
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      check_prereqs
      do_build "$profile"
      do_install "$profile" "$cmd"
      verify_deployment
      ;;
  esac
}

main "$@"
