#!/bin/bash
# Grok Build — start-dev.sh
# 用途：直接运行源码开发模式（cargo run），无需安装二进制
# 依赖：Rust toolchain（rustup 自动安装）、protoc
#
# 使用方式：
#   ./my-scripts/start-dev.sh          # 开发模式 TUI
#   ./my-scripts/start-dev.sh --help   # 查看 grok 命令行参数

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== Grok Build — start-dev.sh ==="
echo "工作目录: $SCRIPT_DIR"
echo ""

# Check Rust
if ! command -v rustup &>/dev/null; then
    echo "❌ rustup 未安装"
    echo "   安装方式: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

# rust-toolchain.toml 会自动触发 rustup 安装指定版本
echo "✅ Rust $(rustc --version | awk '{print $2}')"

# Check protoc
PROTOC_BIN="$SCRIPT_DIR/bin/protoc"
if command -v protoc &>/dev/null; then
    echo "✅ protoc $(protoc --version | awk '{print $2}') (system)"
elif [ -f "$PROTOC_BIN" ]; then
    echo "✅ protoc (dotslash launcher)"
else
    echo "⚠️  protoc 未找到，bin/protoc 会自动下载"
fi

echo ""
echo "=== 构建 + 启动 TUI ==="
echo "首次运行会打开浏览器进行认证 (http://localhost:8080/auth)"
echo "按 Ctrl+C 退出"
echo ""

cargo run -p xai-grok-pager-bin "$@"
