#!/bin/bash
# Grok Build 本地优先裁剪版 — start-dev.sh
# 用途：一键启动本地裁剪版 TUI，进行交互式对话测试
# 依赖：Rust toolchain；模型端点（默认本地 Ollama qwen3.6:27b）的可用性在对话时验证，启动前不探测
#
# 使用方式：
#   ./my-scripts/start-dev.sh              # 启动 TUI（每次启动前 cargo 自动判断新鲜度，需构建才构建）
#   ./my-scripts/start-dev.sh --build      # 强制重新构建后启动
#   ./my-scripts/start-dev.sh --yolo       # 透传任意 grok 参数（如 --yolo 全自动审批）
#   ./my-scripts/start-dev.sh -p "你好"     # 单轮 headless 模式
#
# 环境变量（可选）：
#   GROK_DEFAULT_MODEL     换 Ollama 模型（默认 qwen3.6:27b）
#   GROK_MODELS_BASE_URL   换端点（默认 http://localhost:11434/v1）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

BIN="target/debug/xai-grok-pager"
MODEL="${GROK_DEFAULT_MODEL:-qwen3.6:27b}"
BASE_URL="${GROK_MODELS_BASE_URL:-http://localhost:11434/v1}"

echo "=== Grok Build（本地裁剪版）==="
echo "工作目录: $SCRIPT_DIR"
echo ""

# ---- 检查 Rust ----
if ! command -v rustup &>/dev/null; then
    echo "❌ rustup 未安装"
    echo "   安装: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi
echo "✅ Rust $(rustc --version | awk '{print $2}')"

# ---- 模型端点（仅展示，不做可用性校验）----
# 是否可用在对话时自然验证：端点不可达时 agent 会重试并报错，无需启动前探测。
# 未把 Ollama 配为默认模型时，这里不会对它做任何检查。
echo "ℹ️  默认模型 ${MODEL}（${BASE_URL}）"
echo "   可用性在对话时验证；换模型/端点用 GROK_DEFAULT_MODEL / GROK_MODELS_BASE_URL"

# ---- 构建 ----
FORCE_BUILD=0
for a in "$@"; do [ "$a" = "--build" ] && FORCE_BUILD=1; done

# 始终交给 cargo 做新鲜度判断：无源码变更时秒过（约 1-2 秒），
# 有变更（含 .rs / Cargo.toml / default_models.json 等）自动增量构建。
if [ "$FORCE_BUILD" = "1" ]; then
    echo ""
    echo "=== 强制重新构建（debug）==="
    cargo build -p xai-grok-pager-bin
else
    echo ""
    echo "=== 构建检查（cargo 自动判断新鲜度，无变更秒过）==="
    cargo build -p xai-grok-pager-bin
fi
echo "✅ 二进制 $BIN（$("./$BIN" --version 2>/dev/null)）"

# 过滤掉自定义的 --build 参数
ARGS=()
for a in "$@"; do [ "$a" != "--build" ] && ARGS+=("$a"); done

echo ""
echo "=== 启动（免登录、无遥测、无更新检查）==="
echo "退出: Ctrl+C 或 Ctrl+Q"
echo ""

exec "./$BIN" "${ARGS[@]}"
