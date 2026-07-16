# Grok Build — x.ai 命令行 AI Coding Agent

## 用途
SpaceXAI 的终端 AI 编程 Agent，基于 Rust TUI，支持三种运行模式（交互式/无头脚本/CI）、编辑器嵌入（ACP 协议），与 Claude Code / OpenCode 同类竞品。

## 应用场景
- 终端内全屏 TUI 编程（类似 Claude Code CLI）
- 脚本/CI 无人值守自动化
- 编辑器嵌入（Emacs/Vim/VSCode 通过 ACP 协议）
- 代码库理解、文件编辑、Shell 命令执行、Web 搜索

## 标签
AI编程Agent|Rust|TUI|命令行|编辑器集成|ACP协议|x.ai

## 技术栈
Rust|Cargo|Protocol Buffers|dotslash|macOS|Linux

## 内部版本
V1-20260716

## 依赖
- Rust toolchain（rust-toolchain.toml 自动管理）
- protoc（bin/protoc dotslash launcher 或 PATH 中的 protoc）
- macOS / Linux（Windows 构建未测试）

## 关联
- 官方仓库：`https://github.com/xai-org/grok-build`
- GitHub fork：`https://github.com/weikejia123/grok-build`
- 本地路径：`projects/coder-agent/grok-build/`
- 本地 Gitea：`http://localhost:3000/dzsoft/grok-build`
- 官方文档：https://docs.x.ai/build/overview
- 官方安装：`curl -fsSL https://x.ai/cli/install.sh | bash`
- 官方二进制名：`xai-grok-pager`（安装后命令为 `grok`）
- 对标产品：Claude Code、OpenCode、DeepSeek-Coder

## 深度分析

### 架构亮点
- **Rust 原生**：性能优先，内存安全，编译产物为单二进制
- **三种运行模式**：交互式 TUI（`cargo run -p xai-grok-pager-bin`）、无头脚本（`--script`）、CI 模式
- **ACP（Agent Client Protocol）**：编辑器集成协议，支持 Emacs/Vim/VSCode 等主流编辑器嵌入
- **dotslash launcher**：内置 `bin/protoc` 自动下载器，解决 protoc 依赖管理问题
- **periodic sync**：README 明确说明从 SpaceXAI monorepo 定期同步，版本可能落后上游
- **Rust toolchain pinning**：`rust-toolchain.toml` 锁定工具链版本，保证构建一致性

### 目录结构
- `crates/` — 核心代码包（按功能模块划分）
- `bin/` — 辅助二进制（protoc launcher 等）
- `prod/` — 生产配置/发布产物
- `third_party/` — 第三方依赖
- `.cargo/` — Cargo 配置
- `Cargo.toml` — workspace 根配置

### Fork 策略
**Add-only 模式** — 参考源码，学习 Rust TUI / Agent 架构，不修改上游代码。
