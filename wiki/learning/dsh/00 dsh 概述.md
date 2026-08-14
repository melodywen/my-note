---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, agent-harness, cordis]
created: 2026-08-14
updated: 2026-08-14
---

# DeepSeek Harness (dsh) 概述

## 一句话定义

DeepSeek Harness（`dsh`）是 [DeepSeek AI](https://deepseek.com) 开源的 **Agent Harness**（智能体框架），核心理念是 **"Everything is a Plugin"（一切皆插件）**。

> [!info] 项目信息
> - **仓库**: https://github.com/deepseek-ai/deepseek-harness
> - **官网**: https://deepseek.com/harness
> - **Stars**: 75.6k+（截至 2026-08）
> - **状态**: Developer Preview（迭代中，会有 Breaking Changes）
> - **License**: MIT

## 为什么叫 "Harness"

"Harness" 原意是"马具 / 线束"，在 AI 领域指的是把大模型"套上"一套工具、记忆、规划等外围能力，让它从"只会聊天"变成"能做事"的 Agent。`dsh` 就是 DeepSeek 提供的这套"马具"。

## 核心特性

### 1. Everything is a Plugin（一切皆插件）

这是 `dsh` 最核心的设计哲学：
- 不像传统框架把功能硬编码进核心，`dsh` 把所有能力都做成插件
- 插件可以热插拔、可组合、可替换
- 你可以只用核心 + 几个插件，也可以构建复杂的 Agent 流水线

### 2. 基于 Cordis 框架

`dsh` 底层由 [Cordis](https://github.com/cordiverse/cordis) 驱动。Cordis 的设计理念来自论文 [*A Programming Paradigm for Spatiotemporal Composability*](https://github.com/cordiverse/paper)，强调的是"时空可组合性"——让组件可以在不同时间、不同空间维度上灵活组合。

### 3. Web UI 开箱即用

```bash
npx @deepseek-ai/dsh web
```

一行命令启动 Web UI，默认在 `http://127.0.0.1:3080` 提供服务。

## 命令行用法

```bash
dsh [options] [command] [args...]

# 常用命令
dsh web                              # 启动 Web Profile（等同于 --profile web）
dsh --profile headless "run tests"  # 无头模式：执行单个任务后退出
dsh --profile tui --patch ./extra.yml  # 自定义 Profile + 额外覆盖层
dsh plugin --profile tui add <pkg>   # 为 Profile 安装插件

# 调试命令
dsh --dump-config                    # 打印合成后的 Profile 配置树
dsh --dump-default-config            # 打印不含用户层的默认配置树
```

## 技术栈速览

从仓库结构可以快速看出技术选型：

| 目录 / 文件 | 用途 |
|---|---|
| `package.json` + `pnpm-workspace.yaml` | pnpm monorepo 管理 |
| `packages/` | 核心包 |
| `apps/` | 应用层（含 Web UI） |
| `native/` | 原生模块 |
| `python/` | Python 端组件 |
| `tsdown.config.ts` | TS 构建工具 |
| `vitest.*.config.ts` | 多套测试配置（单元 / E2E / 快照 / Web 压力 / 性能） |
| `lefthook.yml` | Git hooks 管理 |
| `.agents/` + `.claude/` | AI Agent 配置 |
| `docs/` | 官方文档 |

## 快速上手

### 方式一：npx 临时运行（无需安装，推荐初次体验）

```bash
npx @deepseek-ai/dsh web
```

`npx` 的本质是"用完即走"——它把包下载到 `~/.npm/_npx/` 的临时缓存里，执行完**不会注册全局的 `dsh` 命令**。所以你在终端里直接敲 `dsh` 会提示找不到命令。

每次运行都要带 `npx @deepseek-ai/dsh` 前缀。

### 方式二：全局安装（推荐日常使用）

```bash
npm install -g @deepseek-ai/dsh
```

安装后直接用 `dsh` 命令：

```bash
dsh web                              # 启动 Web UI
dsh --profile headless "跑测试"      # Headless 模式
dsh --help                           # 查看帮助
```

> [!note] npx vs 全局安装的区别
> - **npx**：不注册全局命令，每次都要带前缀 `npx @deepseek-ai/dsh`，包缓存在 `~/.npm/_npx/`
> - **全局安装**：注册 `dsh` 命令，直接用 `dsh web`，包装在 `~/.nvm/versions/node/vXX/lib/node_modules/`
> - 两种方式的运行时配置和数据都存在同一个 `~/.dsh/` 目录下，互不影响

### 方式三：从源码构建（适合开发者）

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness
pnpm install
pnpm run build
pnpm dsh web
```

## `npx` 执行后，代码和配置都在哪里

执行 `npx @deepseek-ai/dsh web` 后，dsh 会在本地创建一套完整的运行时环境。以下是文件分布的全景图：

### 整体架构图

```
npx @deepseek-ai/dsh web
        │
        ├── 1. npm 包下载缓存 ──→ ~/.npm/_npx/<hash>/
        │                          (347MB，含全部 197 个 dsh 子包)
        │
        ├── 2. Profile 工作目录 ──→ ~/.dsh/profiles/web/
        │   ├── package.json          ← 声明用哪些插件包(bundle)
        │   ├── pnpm-workspace.yaml   ← pnpm workspace 配置
        │   ├── cordis.yml             ← Profile 根配置(空壳，勿编辑)
        │   ├── cordis.patch.yml       ← 用户覆盖层(自定义入口)
        │   └── node_modules/          ← 符号链接到 npx 缓存
        │
        ├── 3. 用户设置 ──→ ~/.dsh/settings.yaml
        │
        ├── 4. 会话数据 ──→ ~/.dsh/sessions/
        │   └── <工作目录路径编码>/
        │       └── session-<uuid>/
        │           └── session.jsonl.zstd   ← zstd 压缩的 JSONL 对话记录
        │
        └── 5. 持久化存储 ──→ ~/.dsh/storages/
            ├── workspace.json          ← 工作区注册表
            └── session_projcache.json  ← 会话投影缓存
```

> [!tip] 体积分布
> `~/.dsh/` 目录本身只有 **44KB**，而 347MB 的代码全在 `~/.npm/_npx/` 中通过符号链接引用。

### 1. npm 包缓存：`~/.npm/_npx/<hash>/`（347MB）

这是 `npx` 下载的 `@deepseek-ai/dsh` 包及其全部依赖。其中 `@deepseek-ai/` 下有 **197 个子包**，全是 dsh 的插件：

```
~/.npm/_npx/1e7f6d9597241db0/
└── node_modules/
    └── @deepseek-ai/
        ├── dsh                  ← 主入口包
        ├── cordis                ← Cordis 框架核心
        ├── dsh-agent             ← Agent 逻辑
        ├── dsh-agent-loop        ← Agent 循环
        ├── dsh-llm               ← LLM 抽象层
        ├── dsh-llm-deepseek      ← DeepSeek 模型适配
        ├── dsh-tool-bash         ← Bash 工具
        ├── dsh-tool-fs           ← 文件系统工具
        ├── dsh-tool-web          ← Web 搜索工具
        ├── dsh-sandbox           ← 沙箱
        ├── dsh-session           ← 会话管理
        ├── dsh-web-app            ← Web 应用
        ├── ... (共 197 个包)
        └── schemastery           ← 配置 schema 框架
```

### 2. Profile 目录：`~/.dsh/profiles/web/`

**这是 dsh 的核心配置目录。** `dsh` 采用 "Profile" 概念——每个 Profile 是一组插件层的有序叠加。

#### `package.json` — 声明用哪些 bundle

```json
{
  "name": "dsh-profile-web",
  "private": true,
  "dependencies": {},
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",      // 基础层：LLM、Session、工具、沙箱等
        "@deepseek-ai/dsh-web-app"    // Web 层：Web UI、前端、WebServer 等
      ]
    }
  }
}
```

两个 bundle 的含义：
- **`dsh-base`**：提供 Agent 核心能力（LLM 调用、会话管理、文件系统、Bash 执行、沙箱安全、技能系统等）
- **`dsh-web-app`**：在 base 之上叠加 Web UI 能力（Web 服务器、前端 React 应用、WebSocket 通信等），同时禁用了一些不需要的命令行工具

#### `cordis.yml` — Profile 根配置（空壳，勿编辑）

```yaml
# dsh profile root — an empty entry list. The tree is composed as patches:
# each bundle in package.json's dsh.profile.bundles, then cordis.patch.yml, then any
# --patch overlays. Edit cordis.patch.yml, not this file.
[]
```

这个文件**是空的**，你不需要也不应该编辑它。它只是一个入口占位符。

#### `cordis.patch.yml` — 你的用户覆盖层（自定义入口）

```yaml
# Your patch layer for this dsh profile, applied after every bundle layer:
# a top-level YAML array of loader patch entries (id-targeted config
# overrides, disables, and insert lists; `!!js` expressions allowed).
[]
```

**这是你唯一应该编辑的配置文件。** 在这里你可以：
- 覆盖任何插件的配置
- 禁用某个插件
- 插入自定义插件

**配置叠加顺序**（后者覆盖前者）：
```
dsh-base bundle → dsh-web-app bundle → cordis.patch.yml → --patch 参数
```

#### `pnpm-workspace.yaml` — pnpm workspace 配置

```yaml
packages:
  - .
nodeLinker: hoisted
autoInstallPeers: false
```

#### `node_modules/` — 符号链接到 npx 缓存

全是符号链接，指向 `~/.npm/_npx/<hash>/node_modules/` 中的实际包。`dsh` 启动时会在 `~/.dsh/profiles/web/` 下执行 `pnpm install`，把这些符号链接建好。

### 3. 用户设置：`~/.dsh/settings.yaml`

```yaml
ui-onboarding:
  welcomeNoticeVersion: 2026-08-13.1    # 引导提示版本
agent-presets:
  default: standard                      # 默认 Agent 预设
ui-theme:
  preference: dark                      # 暗色主题
```

通过 Web UI 设置产生的用户偏好文件。

### 4. 会话数据：`~/.dsh/sessions/`

```
~/.dsh/sessions/
└── --Users-melodycchen-ai-work-dsh--/          ← 工作目录路径编码为目录名
    └── session-d7992a84-f0ed-4ef1-8afc-27aefa6e6cc1/
        └── session.jsonl.zstd               ← zstd 压缩的 JSONL 对话记录
```

- 目录名是**工作目录路径**（`/` 替换为 `-`）
- 每个会话一个 UUID 子目录
- 对话内容以 **JSONL（每行一个 JSON 对象）+ zstd 压缩**存储

### 5. 持久化存储：`~/.dsh/storages/`

#### `workspace.json` — 工作区注册表

```json
{
  "tables": {
    "workspaces": {
      "cb4bbdbb-491d-4988-9e90-13135386a055": {
        "path": "/Users/melodycchen/ai-work/dsh",   // 工作目录
        "title": "dsh",
        "sessionIds": ["session-d7992a84-..."]      // 关联的会话
      }
    }
  }
}
```

#### `session_projcache.json` — 会话投影缓存

存储每个会话的运行时状态：

| 字段 | 作用 |
|---|---|
| `sessionStats` | 对话轮次、步数、LLM 耗时 |
| `title` | 会话标题（自动生成） |
| `tokenUsage` | Token 用量统计 |
| `contextPressure` | 上下文压力（已用 / 总量 1,000,000） |
| `permissions` | 权限模式（`workspace-write` / `ask`） |
| `todos` | 待办事项 |
| `plan` | 计划模式状态 |

## 默认插件清单

通过 `dsh --dump-default-config --profile web` 可查看完整的插件加载列表（约 490 行，**80+ 个插件**），按功能分类：

| 分类         | 代表插件                                                                                           | 作用                               |
| ---------- | ---------------------------------------------------------------------------------------------- | -------------------------------- |
| **LLM**    | `dsh-llm`, `dsh-llm-deepseek`, `dsh-llm-retry`                                                 | 模型调用、DeepSeek 适配、重试              |
| **会话**     | `dsh-session`, `dsh-session-persistence-jsonl`, `dsh-session-title-llm`                        | 会话生命周期、持久化、自动标题                  |
| **工具**     | `dsh-tool-bash`, `dsh-tool-fs`, `dsh-tool-web`, `dsh-tool-todo`, `dsh-tool-str-replace-editor` | Bash 执行、文件读写、Web 搜索、待办、编辑器       |
| **沙箱**     | `dsh-sandbox`, `dsh-sandbox-policy`, `dsh-bash-sandbox`                                        | 安全隔离、权限策略                        |
| **Agent**  | `dsh-agent`, `dsh-agent-loop`, `dsh-agent-default-model`, `dsh-agent-presets`                  | Agent 循环、默认模型(deepseek-v4-flash) |
| **Web UI** | `dsh-web`, `dsh-host-webserver`, `dsh-client-ui-*` (30+个)                                      | Web 服务器、前端 React 组件              |
| **存储**     | `dsh-storage-json`, `dsh-storage-domain`                                                       | JSON 文件存储后端                      |
| **遥测**     | `dsh-session-telemetry-otel`                                                                   | OpenTelemetry 遥测（默认关闭）           |

> [!note] 默认模型
> `dsh-agent-default-model` 插件配置了默认模型为 `deepseek-v4-flash`，提供商为 `deepseek-official`。

## 关键环境变量

| 环境变量 | 默认值 | 作用 |
|---|---|---|
| `DSH_HOME` | `~/.dsh` | 主目录路径 |
| `DSH_PERMISSION_MODE` | `workspace-write` | 权限模式（可选 `read-only` / `workspace-write` / `danger-full-access`） |
| `DSH_TELEMETRY_MODE` | `DISABLED` | 遥测模式 |
| `DSH_TELEMETRY_OTLP_URL` | `https://harness-telemetry.deepseeksvc.com/v1/logs` | 遥测上报地址 |
| `DSH_TOOLS_MODE` | (未设置) | 工具模式 |
| `DEEPSEEK_API_KEY` | — | DeepSeek API 密钥 |

## 权限体系

dsh 的权限分两个层面，由 `DSH_PERMISSION_MODE` 环境变量控制：

| 权限模式 | 沙箱 | 审批策略 | 说明 |
|---|---|---|---|
| `read-only` | `read-only` | `ask` | 只读，任何写操作都需确认 |
| `workspace-write` | `workspace-write` | `ask` | 工作区内可写，仍需确认（**默认**） |
| `danger-full-access` | `danger-full-access` | `never` | 完全开放，无需确认 |

## 一句话总结

> `npx @deepseek-ai/dsh web` 把 npm 包缓存在 `~/.npm/_npx/`，把**运行时配置**放在 `~/.dsh/profiles/web/`（其中 `cordis.patch.yml` 是你的自定义入口），把**用户设置**放在 `~/.dsh/settings.yaml`，把**会话和存储**放在 `~/.dsh/sessions/` 和 `~/.dsh/storages/`。整个 `~/.dsh/` 目录只有 44KB，因为 347MB 的代码全在 npx 缓存里通过符号链接引用。

## 学习路线规划

以下是我学习 `dsh` 的计划路线：

- [x] 00 — dsh 概述（本页）
- [ ] 01 — 项目架构与 monorepo 结构分析
- [ ] 02 — Cordis 框架核心概念
- [ ] 03 — 插件系统设计原理
- [ ] 04 — 核心包源码阅读
- [ ] 05 — Web UI 架构分析
- [ ] 06 — 编写自定义插件
- [ ] 07 — 实战：用 dsh 构建 Agent

## 相关链接

- [[大模型微调概述]] — 微调是改模型参数，dsh 是给模型套外壳，互补关系
- [[Qwen]] — 阿里通义千问，可作为 dsh 接入的模型之一
