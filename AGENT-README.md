# AGENT-README: Grok Build

> **分析版本**: V1-20260724
> **分析框架**: [ANALYSIS-DIR-CODER-AGENT.md](../../../ANALYSIS-DIR-CODER-AGENT.md) (PV1-20260724)
> **项目路径**: `/Users/weikejia/CODE/my-agent-group/projects/coder-agent/grok-build/`

---

## 1. 身份与定位

| 指标 | 内容 |
|------|------|
| **名称** | Grok Build (命令行: `grok`) |
| **Tagline** | （官方文档: "Terminal-based AI coding agent"） |
| **定位语** | SpaceXAI 的终端 AI Coding Agent — xAI 官方出品, 对标 Claude Code / OpenCode |
| **设计哲学** | 工业级 Rust 实现, 性能与稳定性优先; 完整的 TUI/Headless/ACP 三元运行模式 |
| **许可证** | Apache 2.0 (一阶代码) + 第三方原始许可 |
| **运行时语言** | Rust |
| **构建系统** | Cargo (workspace, 生成式根 Cargo.toml) |
| **上游** | `github:xai-org/grok-build` (从 SpaceXAI monorepo 定期同步) |
| **发布方式** | curl/sh 安装脚本 (`https://x.ai/cli/install.sh`); 预编译二进制 |
| **社区** | x.ai 官方文档 (docs.x.ai/build/overview); 第三方贡献不接受 |

**核心权衡**: 企业级工程品质 vs 社区开放性 (不接受外部贡献); 官方产出的稳定性 vs 社区创新速度

---

## 2. 核心架构

| 指标 | 内容 |
|------|------|
| **运行时** | Rust 原生 (toolchain 由 `rust-toolchain.toml` 锁定) |
| **Crates 结构** | 核心在 `crates/codegen/` 下: `xai-grok-pager-bin` (二进制), `xai-grok-pager` (TUI), `xai-grok-shell` (Agent 运行时), `xai-grok-tools` (工具), `xai-grok-workspace` (文件+VCS+执行); 另有 `crates/common/`, `crates/build/`, `prod/mc/` |
| **核心包** | `xai-grok-pager` (TUI 滚动/提示/模态), `xai-grok-shell` (Agent + stdio/headless entry), `xai-grok-tools` (工具实现), `xai-grok-workspace` (VCS/检查点) |
| **Agent 主循环** | `xai-grok-shell` 中的 Agent runtime: 提示词构建 → LLM → 工具执行 → 状态更新 → 循环 |
| **系统提示词构建** | 待确认 (在 `xai-grok-shell` 中实现) |
| **上下文注入文件** | 待确认 (可能支持 CLAUDE.md 或类似文件) |
| **运行时架构** | 三种 entry: leader (交互式 TUI), stdio (headless), headless (CI/脚本) |
| **根 Cargo.toml** | **生成式** — 视为只读; 各 crate Cargo.toml 手动编辑 |

**架构亮点**: 企业级 Rust 工程 — protoc dotslash 管理, 锁定工具链, 生成式 workspace 配置; 仿照 OpenAI Codex/SST OpenCode 的工具实现 (有明确第三方属性标注)

---

## 3. Provider 与模型支持

| 指标 | 内容 |
|------|------|
| **原生 Provider** | xAI Grok (官方) |
| **鉴权方式** | OAuth (首次启动打开浏览器认证); `authentication.md` 文档 |
| **自定义 Provider** | 待确认 (可能通过配置) |
| **本地模型** | 待确认 |
| **Provider 特定优化** | xAI 官方 Grok 模型优化 |
| **模型选择** | 待确认 |

**Provider 丰富度**: ★★☆☆☆ (xAI Grok 官方为主; 第三方 Provider 支持待确认)

---

## 4. 工具系统

| 指标 | 内容 |
|------|------|
| **内置工具** | `xai-grok-tools` crate — 包含来自 OpenAI Codex 和 SST OpenCode 移植的工具实现 |
| **工具分类** | 终端, 文件编辑, 搜索, 等 (在 `xai-grok-tools` 中) |
| **工具注册机制** | 编译时注册 (Rust trait/struct) |
| **MCP 支持** | 有 MCP 相关配置支持 (在 crate closure 中) |
| **工具权限模型** | 待确认 (可能有 Sandbox 机制 — 文档提及 sandboxing) |
| **第三方工具** | MCP servers; Skills; Hooks; Plugins (用户指南中有章节) |
| **第三方声明** | 明确标注 OpenAI Codex / SST OpenCode 的代码移植, 附 License 变更声明 |

**工具生态成熟度**: ★★★★☆ (丰富的内置工具 + MCP/Skills/Plugins/Hooks, 但部分来自移植代码)

---

## 5. 用户界面与交互

| 指标 | 内容 |
|------|------|
| **TUI 技术栈** | 自研 Rust TUI (在 `xai-grok-pager` crate 中) |
| **交互模式** | 交互式 TUI / Headless (\(--script\)) / ACP (编辑器嵌入) |
| **编辑器功能** | 标准 CLI 编辑; 斜杠命令; 主题配置 |
| **快捷键系统** | 用户指南中 (键盘快捷键章节) |
| **主题系统** | 支持 (用户指南中的 theming 章节) |
| **ACP** | 支持 — Agent Client Protocol 编辑器集成 (Emacs/Vim/VSCode) |
| **Sandbox 模式** | 用户指南中的 sandboxing 章节 |

**TUI 亮点**: xAI 官方出品的企业级 TUI; 三种模式 (TUI/Headless/ACP) 完整; 但有 x.ai OAuth 认证墙

---

## 6. 会话管理

| 指标 | 内容 |
|------|------|
| **存储格式** | 待确认 (在 `xai-grok-workspace` 中) |
| **存储位置** | `~/.config/grok/` (推测) |
| **分支能力** | 待确认 |
| **Fork/Clone** | 待确认 |
| **Compaction** | 待确认 |
| **Checkpoints** | `xai-grok-workspace` crates 中有 checkpoints 支持 |
| **Session Resume** | 待确认 |

**会话管理成熟度**: ★★★☆☆ (Checkpoints 已知, 其他待确认; 企业级实现但文档有限)

---

## 7. 定制化与生态

| 指标 | 内容 |
|------|------|
| **Skills** | 支持 (用户指南章节) |
| **Prompt Templates** | 待确认 |
| **Extensions/Plugins** | Hooks + Plugins 系统 (用户指南) |
| **Themes** | 支持 |
| **包管理系统** | 无 — 通过 Hooks/Plugins 配置 |
| **自修改能力** | 待确认 |

**生态成熟度**: ★★★☆☆ (Hooks/Plugins/Skills 支持, 但无包管理或扩展 API; 不接受外部贡献也限制生态发展)

---

## 8. 记忆与上下文

| 指标 | 内容 |
|------|------|
| **长期记忆** | 待确认 (可能通过 Skills/Hooks 间接实现) |
| **项目上下文** | 待确认 (可能支持类似 CLAUDE.md 的文件) |
| **会话间复用** | 待确认 |
| **上下文窗口管理** | 待确认 |
| **记忆工具** | 待确认 |

**记忆能力**: ★★☆☆☆ (基于公开信息, 无显著记忆系统; 需进一步确认)

---

## 9. 差异化功能

| 功能 | 支持情况 | 说明 |
|------|---------|------|
| **多 Agent 编排** | ❌ 无 | — |
| **目标驱动工作流** | ❌ 无 | — |
| **Computer Use** | ❌ 无 | — |
| **浏览器自动化** | ❌ 无 | — |
| **语音模式** | ❌ 无 | — |
| **远程控制** | ❌ 无 | — |
| **制品托管** | ❌ 无 | — |
| **监控** | ❌ 无 | — |
| **xAI Grok 原生** | ✅ 核心 | 唯一官方 xAI Grok 模型的 Coding Agent |
| **企业级工程** | ✅ | 锁定工具链, dotslash, 生成式 workspace |
| **Sandboxing** | ⚠️ 文档提及 | 用户指南中有 sandboxing 章节 |
| **第三方代码声明** | ✅ 透明 | 明确标注所有移植代码的来源和许可变更 |

**差异化定位**: xAI 官方出品, 企业级 Rust 工程品质; 但功能丰富度远低于 Claude Code (CCB) 和 jcode

---

## 10. 性能

| 指标 | 数据 | 来源 |
|------|------|------|
| **启动耗时** | 待测量 | 未在公开数据中找到基准 |
| **内存 (1 会话)** | 待测量 | 未在公开数据中找到基准 |
| **构建方式** | Cargo (增量构建) | — |
| **二进制体积** | Rust 静态编译 (含 vendored 第三方) | — |

**性能评级**: ★★★★☆ (Rust 原生推测: 快于 Node/Bun; 但无公开性能数据)

---

## 11. 安全

| 指标 | 内容 |
|------|------|
| **权限模型** | 待确认 (可能通过 Sandbox 章节) |
| **沙箱支持** | 文档提及 sandboxing (用户指南) |
| **供应链安全** | Cargo.lock; vendored 第三方代码 (Apache 2.0 + 原许可声明) |
| **认证安全** | x.ai OAuth (首次启动浏览器认证) |

**安全评级**: ★★★☆☆ (企业级但沙箱/权限模型文档不完整; 第三方代码管理透明)

---

## 12. 开发与社区

| 指标 | 内容 |
|------|------|
| **测试框架** | Cargo test |
| **测试策略** | 按 crate 测试 (`cargo test -p <crate>`); clippy + rustfmt |
| **CI/CD** | GitHub Actions (推断) |
| **社区模式** | **不接受** 外部贡献 (CONTRIBUTING.md 明确声明); 从 monorepo 定期同步 |
| **代码质量** | Rust 工具链锁定; clippy.toml; rustfmt; 严格的 Apache 2.0 许可管理 |
| **发布工程** | GitHub Release + curl/sh 安装脚本; Source_REV 追踪 monorepo 版本 |

**社区活跃度**: ★☆☆☆☆ (明确不接受外部贡献; 仅 x.ai 内部开发; 但从 monorepo 同步保证版本追踪)

---

## 版本演进

### V1-20260724 — 初始分析
- **分析范围**: 基于 grok-build README + 源码结构 + 公开文档
- **数据来源**: README.md, Cargo.toml, 项目文档, 公开网站
- **关键发现**: xAI 官方出品, 企业级品质但功能清单在 5 个 Agent 中最不透明; 许多信息因文档不全而标记"待确认"
- **已知局限**: 无法访问内部用户指南; 大量技术细节无法从公开源码确定
- **分析框架**: 12 维度, PV1

---

## 横向对比摘要

| 核心维度 | Grok Build |
|---------|:----------:|
| 运行时 | Rust (原生) |
| 哲学 | xAI 官方 + 企业工程 |
| Provider 数 | 1 (xAI Grok) |
| 内置工具类型 | 中等 (移植自 Codex/OpenCode) |
| MCP | ✅ 支持 |
| 记忆系统 | ❌ (待确认) |
| Swarm | ❌ |
| 启动耗时 | 待测量 |
| 内存(1会话) | 待测量 |
| 生态成熟度 | ★★★☆☆ |
| 安全性 | ★★★☆☆ |
| 代码质量 | ★★★★★ |
