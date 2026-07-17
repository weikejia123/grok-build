# Grok Build CLI 二次开发深度代码审计报告

- 审计对象：`grok-build` workspace（二开分支 `wkj-dev`，基于 upstream `c68e39f Publish harness and TUI open-source`）
- 审计方式：全部结论来自实际源码阅读（文件+行号/函数名为证），并实测 `cargo check -p xai-grok-pager-bin` **1m25s 编译通过**
- 审计日期：2026-07-17
- 结论等级标注：【确定】= 有直接代码证据；【不确定】= 部分证据；【未验证】= 源码内无法确认

---

## 0. 总体结论速览

| 问题 | 结论 |
|---|---|
| 是否包含 CLI 全部源码 | **是**。76 个 crate 全量源码，离线可编译（已实测），无私有依赖。二开评级：**高度可控** |
| 是否有遥测/后门 | **无隐藏后门**，但存在完整的多层遥测体系（默认关、可被服务端远程打开）+ **自动更新默认开启且无签名校验（最高风险项）** |
| 自定义 LLM API | **零代码改动可行**：`GROK_MODELS_BASE_URL` + `XAI_API_KEY` 或 `[model.*]` TOML 配置即可指向自建 OpenAI 兼容网关；OAuth 不强制 |
| 第三方流式集成 | **三条可行路线**：ACP（`grok agent stdio` / `grok agent serve`，推荐）、headless JSONL（`grok -p --output-format streaming-json`，最快）、内嵌 crate 当库 |

---

## 1. CLI 源代码完整性与二开可控性

### 1.1 入口与调用链（完整闭合）【确定】

- 主二进制 crate：`crates/codegen/xai-grok-pager-bin`（产物名 `xai-grok-pager`，安装后命令为 `grok`），仅为**组合根**：链接 `xai-grok-pager` 库（全部 TUI 逻辑）+ `xai-grok-pager-minimal`。
- `ptyctl-cli` 是独立小工具（headless PTY 控制器），与主二进制无依赖关系，仅供测试 harness 使用。
- 调用链：`pager-bin/src/main.rs:1578 main()` → `async_main()` → 三条分发路径：
  - TUI：`xai_grok_pager::app::run()`（`xai-grok-pager/src/app/mod.rs:427`）
  - agent 子命令：`xai_grok_shell::agent::app::{run_stdio_agent, run_headless, run_leader}`（`xai-grok-shell/src/agent/app.rs:289/409/917`）
  - headless 单轮：`xai_grok_pager::headless::run_single_turn`（`main.rs:1937`）
- Turn 循环：`xai-grok-shell/src/session/acp_session_impl/sampler_turn.rs:860 run_turn_via_sampler()`
- LLM 调用：`xai-grok-sampler/src/client.rs`（reqwest + SSE，`/chat/completions` :865、`/responses` :1146、`/messages` :1477）
- 工具执行：`xai-tool-runtime/src/dispatch.rs` + `xai-grok-tools/src/implementations/`（全套本地实现）

### 1.2 核心链路本地化程度【确定】

| 链路 | 位置 | 本地化 |
|---|---|---|
| LLM 客户端 | `xai-grok-sampler`（OpenAI 兼容协议） | 代码本地；模型本体在云端 |
| 工具执行 | `xai-grok-tools`、`xai-tool-runtime` | 完全本地 |
| TUI 渲染 | `xai-grok-pager(-render/-minimal)`、`xai-ratatui-inline` | 完全本地 |
| 会话存储 | `xai-sqlite-journal`（WAL）、`xai-chat-state`、`~/.grok` | 完全本地 |
| MCP / 沙箱 / hooks / 子代理 | `xai-grok-mcp` / `xai-grok-sandbox` / `xai-grok-hooks` | 完全本地 |

### 1.3 构建依赖审计【确定】

- `.cargo/config.toml`：仅 rustflags/链接器加固，**无私有 registry、无源替换**。
- `Cargo.lock` 1270 个包：仅 crates.io 官方索引 + 一个公开 git 依赖 `github.com/helix-editor/nucleo.git@5b74652`。
- `bin/protoc`：dotslash wrapper，明文指向 GitHub protobuf v29.3 公开 release（含 sha256）。
- ripgrep 捆绑（`xai-grok-shell/build.rs`）：仅 release 构建触发，下载自 BurntSushi/ripgrep 公开 release，`GROK_SHELL_BUNDLE_RG_PATH` / `GROK_SHELL_RG_DOWNLOAD_BASE` 可离线覆盖。
- proto：全仓库仅 1 个 `.proto`（`xai-grok-tools-api/proto/grok-tools.proto`），随仓库提供；`xai-proto-build` 生成到 `OUT_DIR`，离线可构建。
- `third_party/`：mermaid→SVG 布局栈（`mermaid-to-svg`/`dagre_rust`/`graphlib_rust`/`ordered_hashmap`），仅用于渲染模型输出的 mermaid 图，非核心链路。

### 1.4 依赖 xAI 云端、本地无法替代的部分【确定】

- Grok 模型推理本身（可用自建 OpenAI 兼容网关替代，见 §3）
- `web_search` 工具：服务端托管工具（`xai-grok-tools/src/implementations/web_search/client.rs:136` POST `{base_url}/responses`），除非自建带搜索的代理否则不可用
- 会话云同步/分享：`xai-grok-shell/src/remote/` → `https://code.grok.com`
- workspace 云端暴露：`xai-grok-workspace` + `xai-computer-hub-sdk`（wss hub，服务端 feature flag 门控，`GROK_WORKSPACE_COMMAND` env 可本地绕过门控但 hub 服务端仍是 xAI 的）
- 语音 STT（`xai-grok-voice` → `api.x.ai/v1/stt`，其 `config.rs:44` 硬编码 `https://api.x.ai`）
- `prod/mc/cli-chat-proxy-types` 只有类型定义，**cli-chat-proxy 服务端源码不在仓库**

**可控性评级：高度可控** —— 构建层完全自主；运行层除 LLM API 外均可本地化或关闭；改任意环节无源码盲区。

---

## 2. 遥测、数据外发与安全审计

**总体结论**：存在完整的多层数据外发体系（产品事件 / Mixpanel / 内部 OTLP span / GCS trace 上传 / Sentry），均有门控设计，**未发现隐藏后门**（无硬编码可用凭证、无隐蔽外联地址）。三个必须处理的风险点见 2.6。

### 2.1 遥测管道【确定】

- **三级模式** `TelemetryMode`（`xai-grok-telemetry/src/config.rs:15-21`）：`Disabled`（**默认**）/ `SessionMetrics` / `Enabled`。
- **Mixpanel**：`xai-mixpanel/src/lib.rs:76` POST `api.mixpanel.com/track`，`:107` `/engage`。发送前经 `xai_grok_secrets::redact_json_string_values` 脱敏。
- **自建 events 端点**：无硬编码默认 URL，只能通过编译期 `GROK_TELEMETRY_BUILD_EVENTS_URL` 或运行时 env 注入。**官方发行版是否烘焙了这些值，源码无法判断【未验证】**。
- **收集字段**：`agent_id` 是**机器指纹**（macOS 硬件序列号/UUID 派生 + UUIDv5 哈希，`id.rs:34-67`），非匿名随机 ID；另有 user_id、team_id、国家、语言、版本、订阅层级。产品事件流**不发送 prompt 原文**（`prompt_text`/`file_path` 字段仅供企业自建的 external OTEL 流使用，默认关）。
- ⚠️ **服务端可通过 `/v1/settings` 远程设置把遥测远程打开**（`xai-grok-shell/src/agent/config.rs:2069-2077 resolve_telemetry_mode`），本地用户无感知。服务端对普通用户的默认值【未验证】——这是最大外部未知数。
- **关闭方式**：`GROK_TELEMETRY_ENABLED=0`、`DISABLE_TELEMETRY=1`、config.toml `[features] telemetry = false`。
- **内部 OTLP span**：默认端点 `https://cli-chat-proxy.grok.com/v1/traces`（`config.rs:347-363`），导出时双重门控（遥测 ≥ SessionMetrics 且有凭证），属性白名单过滤（`otel_layer/redact.rs:13`）。`OTEL_TRACES_EXPORTER=none` 可关。
- **GCS trace 上传是内容外发最大面**：遥测 Enabled 后会上传 `turn_messages.json`（**完整对话**）、工具定义、prompt 图片原图、repo changes（commits + worktree diff）（`xai-file-utils/src/upload/trace.rs:432-463`）。ZDR 团队硬禁（`auth/model.rs:168-179`）。

### 2.2 崩溃处理【确定】

- `xai-crash-handler`：**纯本地**（SIGSEGV/SIGBUS 捕获，写 `$GROK_HOME/crash/`，无网络代码），且默认关。
- Sentry：DSN 来自 `SENTRY_DSN` env，本仓库未烘焙（官方 CI 是否烘焙【未验证】）；1% traces 采样；`send_default_pii: false`；`before_send` 全量脱敏（secret 脱敏 + home→`~` + 用户名→`<user>`）。`DISABLE_ERROR_REPORTING` 可关。

### 2.3 自动更新【确定，最高风险项】

- **默认开启**（`xai-grok-update/src/auto_update.rs:486-487`，`None` 按 `true` 处理）。
- 更新源：`https://x.ai/cli`（主）、`https://storage.googleapis.com/grok-build-public-artifacts/cli`（备）。
- 流程：拉 channel pointer → 下载二进制 → `chmod 0o755` → smoke test 仅执行 `--version` → 替换激活。
- ⚠️ **全程无 checksum/签名/GPG 校验**（grep 无 sha256/ed25519 验证逻辑），完整性完全依赖 TLS 与 x.ai/GCS 基础设施可信。任何能控制更新源响应的一方都可投送可执行二进制。
- **二开必须关闭**：config.toml `[cli] auto_update = false`。

### 2.4 认证与 token【确定】

- OAuth 2.1 Auth Code + PKCE 或 RFC 8628 Device Grant，issuer 硬编码 `https://auth.x.ai`（`xai-grok-shell/src/auth/config.rs:128`）。
- token **明文 JSON** 存 `~/.grok/auth.json`（无 keychain 集成）。`xai-grok-secrets` 是脱敏库而非凭证库。
- token 发往：`auth.x.ai`、`cli-chat-proxy.grok.com`、`api.x.ai`、`wss://code.grok.com`。
- ⚠️ 注意：`GrokAuthCredentials::apply()`（`util/grok_auth_credentials.rs:119-134`）忽略 base_url，对带 middleware 的请求无条件附 `Authorization: Bearer`；域隔离依赖调用方纪律。proxy 专用头（`X-XAI-Token-Auth`）有 URL 白名单（`config.rs:4681-4696`），自建网关不会被塞 xAI 专用头。

### 2.5 其他外联通道

- **Relay**：登录 xAI session 后 leader 进程主动外连 `wss://code.grok.com/ws/code-agent` 并常驻重连（`agent/relay.rs`）——grok.com 网页端可远程驱动本地 agent（"Web 端续聊"设计功能）。出站连接，但构成服务端可下达指令的通道，信任模型上等同于信任 xAI 服务端。**自建网关场景此通道不激活**（仅 `is_xai_auth()` 时建立）。
- `obfstr` 字符串混淆仅 5 处，混淆的是 OAuth client_id、header 名、env 名等公开标识符，用途良性【确定】。
- plugin marketplace：`git clone` 第三方插件需用户显式安装，属用户行为。
- **未发现**把本地仓库自动上传到云端 workspace 的代码路径【确定】。

### 2.6 二开安全基线（必须做）

```toml
# ~/.grok/config.toml
[cli]
auto_update = false        # 关闭无签名校验的自动更新

[features]
telemetry = false          # 钉死遥测，防服务端远程打开

[diagnostics]
error_reporting = false    # 关闭 Sentry
```

并建议打包二开版本时不设置 `GROK_TELEMETRY_BUILD_*` 与 `SENTRY_DSN` 编译期变量（本仓库默认即未设置）。

### 2.7 外联域名风险分级

| 域名 | 用途 | 风险 |
|---|---|---|
| `api.x.ai` | LLM 推理/embeddings/STT | 低（核心功能） |
| `auth.x.ai` / `accounts.x.ai` | OAuth | 低 |
| `cli-chat-proxy.grok.com/v1` | settings/feedback/storage/traces | 中（遥测开启后收完整对话） |
| `api.mixpanel.com` | 产品分析 | 中（含机器指纹；默认关） |
| `x.ai/cli` + GCS artifacts | 更新二进制 | **高（无签名校验、默认开）** |
| `wss://code.grok.com/ws/code-agent` | Web 端远程驱动 relay | 中（登录后常驻） |
| `github.com/xai-org/plugin-marketplace.git` | 插件市场 | 中（第三方代码执行） |

---

## 3. 自定义 LLM API 可行性

**总体结论【确定】：原生完整支持自定义 OpenAI 兼容 endpoint，零代码改动。**

### 3.1 配置层

- 核心配置在 `xai-grok-shell/src/agent/config.rs`（**不在** `xai-grok-config-types`，后者只放服务端远程设置）：
  - `EndpointsConfig`（config.rs:143）：`cli_chat_proxy_base_url`（env `GROK_CLI_CHAT_PROXY_BASE_URL`）、`xai_api_base_url`（env `GROK_XAI_API_BASE_URL`）、**`models_base_url`（env `GROK_MODELS_BASE_URL`，自定义 endpoint 总开关）**、`models_list_url`（env `GROK_MODELS_LIST_URL`）
  - `has_custom_endpoint()`（config.rs:273）为真时：**跳过全部硬编码默认模型**，目录 = 自建 `/models` 返回 + `[model.*]` 条目（config.rs:3134-3139）
  - `ConfigModelOverride`（config.rs:3570）：`[model.<id>]` 支持 `model`（线上 slug）、`base_url`、`api_key`、`env_key`（支持数组）、`api_backend`、`extra_headers`、`context_window` 等
- 凭据解析顺序（config.rs:4305 `resolve_credentials`）：模型自有 key → session token → 全局 `XAI_API_KEY`

### 3.2 认证：OAuth 不强制【确定】

绕过登录路径：`XAI_API_KEY` env、任意 `[model.*]` 配 `api_key`/`env_key`（BYOK 一等公民，`auth_method.rs:63`）、`[auth] preferred_method = "api_key"`。token 本地只判 JWT exp **不验签**（`auth/jwt.rs:11-16` `insecure_decode`），有效性由服务端 401 判定。注意管理员 kill switch `GROK_DISABLE_API_KEY_AUTH` 仅对 first-party xAI URL 生效，自建网关不受影响。

### 3.3 协议层【确定】

- LLM 推理 **100% 走 HTTP (reqwest) + SSE，不走 gRPC**（tonic/gRPC 仅用于 OTLP 遥测与 workspace）。
- 三种 API 后端可切换（`ApiBackend`，`xai-grok-sampling-types/src/types.rs:1013`）：
  - `chat_completions`：自研 OpenAI 兼容请求（`POST {base}/chat/completions`）
  - `responses`：复用 `async-openai` 的 `CreateResponse`（`POST {base}/responses`）
  - `messages`：Anthropic 格式（`POST {base}/messages`）
- SSE 解析：`eventsource-stream`，`xai-grok-sampler/src/client.rs:1011/1388/1707`。
- 认证头：`AuthScheme` 支持 `Bearer` 与 `XApiKey`；`extra_headers` 透传。

### 3.4 模型目录与名称映射【确定】

- 三层来源：config > 远程预取（`GET {base}/models`，兼容 OpenAI `{data:[...]}` 格式）> 硬编码（`xai-grok-models/default_models.json`，仅 1 个 `grok-build`，`api_backend: "responses"`）。
- 别名映射：目录 key 是 `id`，线上发送 slug 是 `model` 字段 → `[model.my-gpt] model = "gpt-4o"` 后 `/model my-gpt` 即可。

### 3.5 接入自建网关的操作方案

**零代码改动（二选一）：**

```bash
# 方式一：环境变量
export GROK_MODELS_BASE_URL=https://gw.example.com/v1
export XAI_API_KEY=sk-...
```

```toml
# 方式二：~/.grok/config.toml
[models]
default = "my-model"

[model.my-model]
model = "gpt-4o"                        # 线上路由 slug
base_url = "https://gw.example.com/v1"
env_key = "MY_API_KEY"
api_backend = "chat_completions"        # 网关不支持 /v1/responses 时必须显式指定
context_window = 128000
```

**坑（均确定）：**

1. 自建网关若只实现 Chat Completions，**必须给每个模型显式写 `api_backend = "chat_completions"`**——内置默认模型走 Responses API。
2. `stream_tool_calls = true` 是 xAI 私有扩展，自建网关不要开。
3. xAI 私有功能在自建端点上自动失效属预期：`search_parameters`、`x_search`、服务端 web_search、doom-loop 检查。
4. Anthropic 风格 `x-api-key` 认证：`ConfigModelOverride` 未暴露 `auth_scheme` 字段，TOML 里需用 `extra_headers = { "x-api-key" = "..." }` 变通；干净支持需小改约 10 行（config.rs:3570 + `apply()` :3612）。

### 3.6 彻底"去 xAI 化"改造点（可选）

| 改造点 | 位置 | 改动量 |
|---|---|---|
| 遥测/trace | `config.rs:347` | 零代码，配置关 |
| feedback/远程设置/announcements | `config.rs:317/328` | 零代码，不可达时自然降级 |
| 会话同步/分享 | `remote/client.rs:381/526` | 开关【未验证】，否则小改禁用 |
| 自动更新 | `xai-grok-update` | 零代码，`[cli] auto_update = false` |
| 默认模型 JSON | `xai-grok-models/default_models.json` | 改 1 个 JSON |
| OAuth 登录 UI 入口 | `auth_method.rs:139 build_auth_methods` | 可选删除，小改 |

---

## 4. 第三方应用集成与流式输出

### 4.1 三条可行路线

**路线一：ACP（推荐）**【确定】

- 本仓库实现了完整的 ACP **agent 侧**（`xai-grok-shell/src/agent/mvp_agent/acp_agent.rs:7 impl acp::Agent for MvpAgent`），方法齐全：`initialize`/`authenticate`/`new_session`/`load_session`/`prompt`/`cancel`/`set_session_mode`/`set_session_model` + 大量 `x.ai/*` 扩展。
- 接入方式：
  - 本地 spawn：`grok agent stdio`（JSON-RPC 2.0 按行走 stdin/stdout）——Zed 类客户端的标准接法，grok-desktop 即如此 spawn（`agent/app.rs:306-307` 注释）
  - 网络服务：`grok agent serve [--bind 127.0.0.1:2419] [--secret]`（axum WebSocket，`agent/server.rs`）
  - Unix socket leader 模式：`grok agent leader`（带断线重放）
- 流式通知：标准 ACP `session/update`（`SessionNotification`），含文本增量、思考、**工具调用**、计划、权限请求。
- 限制：client 侧必须实现 `session/request_permission`（可选 `fs/*`、`terminal/*`），否则工具执行被卡或需 `--yolo`。
- 工作量：小-中（官方 `agent-client-protocol` crate 可用；其他语言按行 JSON-RPC 手写也不难）。

**路线二：Headless JSONL（最快接入）**【确定】

```bash
grok -p "你的 prompt" --output-format streaming-json
```

- stdout 输出 JSONL 事件流：`{"type":"text"|"thought"|"end"|"error"|...}`（`xai-grok-pager/src/headless.rs:373-473`），spawn 子进程逐行解析即可。
- `-p/--single` 兼容 Claude Code 的 `--print` 拼写；支持 `--resume/--continue` 续会话、`--max-turns`、`--yolo`、`--json-schema` 结构化输出。
- **重要限制【确定】**：streaming-json **不转发工具调用事件**——`handle_headless_acp_message`（headless.rs:1468）只匹配文本/思考 chunk，其余 `SessionUpdate`（ToolCall/Plan 等）落入 `_ => {}` 被丢弃（headless.rs:1507）。无 stdin 管道 prompt；单轮；权限只能全自动（`--yolo`）或全拒。
- 工作量：极小。适合 CI/脚本/简单服务端封装。

**路线三：内嵌 crate 当库**【确定】

- 在自己的 Rust 进程里依赖 `xai-grok-shell`（`MvpAgent`）+ `xai-acp-lib`，用 `acp_channels()` 内存通道直连，消费 `SessionNotification`。现成样板：`xai-grok-pager/src/acp/spawn.rs:36 spawn_grok_shell` + `headless.rs` 的 client 循环（headless 模式本身就是进程内 ACP client）。
- 工作量：中-大。限制：crate 未发布（path 依赖、API 无稳定性承诺）；agent 线程模型是 `Rc<MvpAgent>` + 单线程 `LocalSet`；需正确初始化认证/遥测/bootstrap。

**不推荐**：ptyctl 屏幕抓取（`ptyctl-cli`，HTTP/WS 的 PTY 控制，仅作兜底，非结构化接口）。

### 4.2 事件流内部抽象与最小改造点【确定】

- 内部统一事件抽象就是 ACP `SessionNotification`/`SessionUpdate`，唯一发射点：`xai-grok-shell/src/session/acp_session_impl/updates.rs:92-165 send_update/send_update_full`（meta 携带 totalTokens/eventId/promptId 等）。
- 若需自定义 JSONL/SSE 输出，**最小侵入点**是在 `send_update_full`（updates.rs:160-165）处 tap 一份序列化的 `SessionNotification` 旁路输出——所有会话的所有事件（含 ToolCall/Plan）都汇聚于此，比改 headless.rs 的 emitter 更全。

### 4.3 选型建议

| 需求 | 推荐 |
|---|---|
| 自有 IDE/编辑器深度集成 | ACP（`grok agent stdio`） |
| 服务端远程调用、多客户端 | ACP over WS（`grok agent serve --secret`） |
| CI/脚本/快速验证 | headless JSONL |
| 自家 Rust 应用深度嵌入 | 内嵌 crate |

---

## 5. 架构师视角补充分析

### 5.1 架构分层（二开心智模型）

```
xai-grok-pager-bin      组合根（main，参数解析，分发）
├── xai-grok-pager          TUI（ratatui）+ headless 模式 + ACP client 侧
├── xai-grok-shell          ★ 核心：agent 运行时（MvpAgent）、session actor、
│   │                       认证、配置、远程服务、relay、ACP agent 侧
│   ├── xai-grok-agent          prompt/配置/插件组装层（Agent 结构体）
│   ├── xai-grok-sampler        LLM 客户端（HTTP+SSE，三种 API 后端）
│   ├── xai-grok-sampling-types 请求/响应类型
│   ├── xai-grok-tools(+api)    工具实现与协议
│   ├── xai-tool-runtime        工具调度
│   ├── xai-grok-mcp            MCP 集成
│   └── xai-chat-state / xai-sqlite-journal  会话持久化（~/.grok）
└── xai-grok-telemetry / xai-mixpanel / xai-grok-update / ...  周边服务（可关）
```

**二开关键认知**：`xai-grok-shell` 是心脏（agent 运行时 + 配置 + 认证 + ACP 全在此），`xai-grok-pager` 只是它最大的 ACP client。要改行为先找 shell，要改 UI 才碰 pager。

### 5.2 二开推荐路线（基于以上审计）

1. **第一步（纯配置，当天可用）**：自建 OpenAI 兼容网关 + `GROK_MODELS_BASE_URL`/`XAI_API_KEY`（或 `[model.*]` TOML）+ 安全基线三件套（`auto_update=false`、`telemetry=false`、`error_reporting=false`）。注意显式指定 `api_backend = "chat_completions"`。
2. **第二步（小改，提升体验）**：`default_models.json` 换内置模型目录；`ConfigModelOverride` 补 `auth_scheme` 字段（约 10 行）。
3. **第三步（按需）**：headless.rs:1507 的 `_ => {}` 分支补工具事件转发（若走 JSONL 路线又需要工具可见性）；或在 `send_update_full` 加 JSONL tap。
4. **第四步（深度二开）**：删除/替换 OAuth 登录 UI、会话云同步、relay 等 xAI 专属模块；fork 后注意 upstream 是"periodic sync from monorepo"，合并策略需规划。

### 5.3 风险与注意事项汇总

- **必须关自动更新**（无签名校验的二进制下载执行，§2.3）。
- **遥测可被服务端远程打开**，本地配置钉死后优先级高于 remote settings（requirements > env > config > remote，§2.1），用 env/config 钉死即可防护。
- token 明文存 `~/.grok/auth.json`，多用户机器注意权限。
- 自建网关后 `web_search`、`x_search` 等 xAI 托管工具失效，若需要可在网关侧以 Responses API 的 hosted tool 形式自行实现。
- `xai-grok-voice` 硬编码 `https://api.x.ai`（其 config.rs:44），自建场景语音不可用。
- release 构建会从 GitHub 下载 ripgrep 捆绑，离线打包用 `GROK_SHELL_BUNDLE_RG_PATH` 指定本地 rg。

### 5.4 未能验证项（诚实声明）

1. 官方 CI 是否烘焙 `GROK_TELEMETRY_BUILD_*` / `SENTRY_DSN`（决定官方二进制的遥测实况；自行编译则必然为零）。
2. xAI 服务端 remote settings 对普通用户的 `telemetry_mode` 默认值。
3. 未实际以自建网关跑通端到端（本次仅源码审计 + `cargo check` 编译验证）。
4. Zed 等第三方 ACP client 的实际兼容性（取决于其对 client 方法与协议版本的最低要求）。
5. 会话云同步/分享的本地关闭开关位置。

---

## 附：验证记录

```bash
# 编译验证（2026-07-17，本机）
cargo check -p xai-grok-pager-bin
# Finished `dev` profile [unoptimized + debuginfo] target(s) in 1m 25s — 全绿
```
