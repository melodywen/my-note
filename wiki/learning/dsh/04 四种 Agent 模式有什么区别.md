---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, agent-preset, 模式]
created: 2026-08-14
updated: 2026-08-14
---

# 04 四种 Agent 模式有什么区别

## 先说结论

dsh 内置了四种 Agent 模式（官方叫 **Agent Preset**，即 Agent 预设）。它们的区别就是：**模型能用什么工具、被赋予什么人设**。

| 模式 | 中文名 | 一句话 | 工具数 |
|---|---|---|---|
| **standard** | 标准模式 | 全功能编码 Agent | ~20 |
| **code** | PTC 模式 | 标准 + 用 TypeScript 程序批量调工具 | ~21 |
| **minimal** | 极简模式 | 只有 Bash + 文件编辑器 | 2 |
| **cordis** | 创造模式 | 标准 + 能检查和修改自己的运行时 | ~22 |

## 用一个比喻来理解

把 Agent 模式想象成给员工配的**工具箱**：

- **标准模式**：给员工一个完整的工具箱——锤子、螺丝刀、电钻、锯子、图纸……什么都有
- **PTC 模式**：标准工具箱 + 一个自动化机器——员工可以写个程序让机器自动跑多步操作
- **极简模式**：只给一把锤子和一把钳子——故意不给别的，用来测试员工在最小条件下的表现
- **创造模式**：标准工具箱 + 一把自己改造工具的焊枪——员工可以自己改工具箱里的东西

## 四种模式分别有什么

### 标准模式（Standard）

这是默认模式。模型拥有完整的编码能力：

```
工具箱：
├── Shell（Bash / PowerShell）
├── 文件读写 + 搜索
├── 后台任务管理
├── 技能加载（Skills）
├── 目标追踪
├── 计划模式
├── 上下文压缩
├── 子 Agent 委派（spawn + fork）
├── 工作流引擎
├── Ralph 循环（自动迭代）
├── 待办列表
├── 问用户问题
└── Web 搜索
```

人设：*"You are a coding agent powered by the {{model}} model. Your working directory is {{cwd}}."*

日常写代码用这个就够了。

### PTC 模式（Code Mode）

PTC = Programmatic Tool Calling。在标准模式的基础上，多了一个 `tool-presentation` 插件。

**它解决的问题是**：模型每次只能调一个工具，要调 5 个工具就得来来回回 5 次。

**PTC 模式的做法**：让模型写一个 TypeScript 程序，程序里一次性调用多个工具。`run_code` 执行这个程序，5 次往返变成 1 次。

```
标准模式：
  模型 → 调工具A → 结果 → 调工具B → 结果 → 调工具C → 结果
  （3 次往返，慢）

PTC 模式：
  模型 → 写一段 TS 程序，里面调了 A、B、C → run_code 一次执行完
  （1 次往返，快）
```

人设和标准模式一样，只是工具调用方式不同。

### 极简模式（Minimal）

**故意只给两个工具**：持久 Bash 和 str_replace_editor（文件编辑器）。

```
工具箱：
├── persistent-bash（持久的 Bash，状态保持）
└── str-replace-editor（文件编辑）
```

没有文件搜索、没有 Web 搜索、没有子 Agent、没有计划模式、没有压缩、没有技能系统。

**用途**：跑 Benchmark（基准测试）。当你想比较"模型 A 和模型 B 谁写代码更好"时，你需要把框架的影响降到最低。极简模式就像一个标准化的考试环境——所有人用同样的纸和笔，只看个人能力。

> 官方文档原文：*"Minimal mode keeps only a shell tool and a file editor for benchmarking models in a minimal environment."*

### 创造模式（Cordis）

在标准模式基础上，多了一个 `tool-cordis` 工具。这个工具允许模型：

- **查看运行时**：看到当前加载了哪些插件、注册了哪些服务
- **挂载临时插件**：实验性地加载自定义代码到运行时中
- **卸载插件**：移除不需要的能力
- **编写新的 Preset**：让 Agent 创作另一个 Agent 的配置

人设也变了，告诉模型它运行在两个"平面"上：

> *"Two planes decide where an edit belongs. The HOST composition holds the registries and anything shared across sessions. An AGENT PRESET holds what one session contributes to those registries: its tools, its persona, its prompt sections."*

> [!danger] 信任边界
> 创造模式的 `cordis_mount` 会**执行模型编写的 JavaScript 代码**，等同于 Shell 访问权限。只有在信任模型输出时使用。

**用途**：开发新的 Agent 配置。如果你想让 AI 帮你设计一个新的 Agent 预设，就用这个模式。

## 两个平面（Two Planes）

创造模式的人设里提到了"两个平面"，这是理解 dsh 架构的关键概念：

```
┌─────────────────────────────────────────┐
│         HOST 平面（宿主平面）              │
│  进程级，所有会话共享                       │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    │
│  │LLM   │ │沙箱   │ │持久化 │ │子Agent │    │
│  │注册表 │ │策略   │ │存储   │ │注册表  │    │
│  └──────┘ └──────┘ └──────┘ └──────┘    │
├─────────────────────────────────────────┤
│      AGENT PRESET 平面（预设平面）          │
│  每个会话独立挂载                           │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    │
│  │工具   │ │人设   │ │Prompt│ │压缩   │    │
│  │目录   │ │      │ │段    │ │策略   │    │
│  └──────┘ └──────┘ └──────┘ └──────┘    │
└─────────────────────────────────────────┘
```

| 平面 | 生命周期 | 包含什么 |
|---|---|---|
| **HOST** | 进程级，所有会话共享 | LLM 适配器、沙箱、持久化、子 Agent 注册表、模型路由 |
| **AGENT PRESET** | 会话级，每个会话独立 | 工具目录、人设、Prompt 段、压缩策略 |

**判断标准**：被多个会话共享的东西放 HOST 平面；只被单个会话使用的东西放 PRESET 平面。

这个概念官方文档写在 `agent-presets/` 的配置文件注释里，不是文档页面里。是我在读 preset 的 YAML 文件时发现的。

## 怎么切换模式

在 Web UI 里，新建会话时可以选择 Agent 模式。也可以在已有会话中通过设置切换。

每个模式对应一个配置文件，位于 dsh 的 `config/agent-presets/` 目录下。如果你想自定义模式，可以复制一个 preset 目录然后修改。

## 小结

| 模式 | 给谁用 | 工具多寡 | 核心差异 |
|---|---|---|---|
| 标准 | 日常写代码 | 丰富 | 默认选择 |
| PTC | 需要批量操作 | 标准+1 | 用代码批量调工具，减少往返 |
| 极简 | 跑 Benchmark | 极少 | 消除框架干扰，只测模型能力 |
| 创造 | 开发新 Agent | 标准+1 | 能检查和修改自己的运行时 |

## 官方文档参考

- Agent Preset 的概念来自 [architecture.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md) 的 "Where new behavior goes" 表格
- "两个平面"的概念来自 `agent-presets/cordis/` 配置文件中的注释
- 四种模式的描述来自 [deepseek.com/harness](https://deepseek.com/harness/en/) 官网

## 下一篇

- [[05 dsh 的安全机制——沙箱、权限和审批|05 dsh 的安全机制——沙箱、权限和审批]]
