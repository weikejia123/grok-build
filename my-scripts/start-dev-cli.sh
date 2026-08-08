#!/bin/bash
# Grok Build CLI 启动脚本 — start-dev-cli.sh
# 用途：构建并运行 grok CLI（TUI 交互式 / headless 单轮 / 透传任意参数）
# 依赖：Rust 1.94.0（由 rust-toolchain.toml 自动切换，无需手动安装）
#
# 用法：
#   ./my-scripts/start-dev-cli.sh              # 构建并启动 TUI
#   ./my-scripts/start-dev-cli.sh --yolo       # 透传 grok 参数（全自动审批）
#   ./my-scripts/start-dev-cli.sh -p "你好"     # headless 单轮对话
#   ./my-scripts/start-dev-cli.sh --build -p x # 强制重建后运行
#
# 环境变量（可选）：
#   GROK_DEFAULT_MODEL    模型名（默认 qwen3.6:27b）
#   GROK_MODELS_BASE_URL  端点（默认 http://localhost:11434/v1）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

BIN="target/debug/xai-grok-pager"
PKG="xai-grok-pager-bin"

echo "=== Grok Build CLI ==="
echo "工作目录: $SCRIPT_DIR"
echo "toolchain: $(rustc --version 2>/dev/null || echo '未找到 rustc，请先安装 rustup')"
echo ""

# 是否强制重建
FORCE_BUILD=0
for a in "$@"; do [ "$a" = "--build" ] && FORCE_BUILD=1; done

# 构建：只保留 debug 一套产物，增量构建，无变更秒过
if [ "$FORCE_BUILD" = "1" ]; then
    echo "=== 强制重建（debug）==="
    cargo build -p "$PKG"
else
    echo "=== 构建检查（cargo 自动判断新鲜度）==="
    cargo build -p "$PKG"
fi
echo "✅ $BIN（$("./$BIN" --version 2>/dev/null)）"
echo ""

# 过滤 --build 参数后透传
ARGS=()
for a in "$@"; do [ "$a" != "--build" ] && ARGS+=("$a"); done

echo "=== 启动（退出: Ctrl+C / Ctrl+Q）==="
exec "./$BIN" "${ARGS[@]}"
