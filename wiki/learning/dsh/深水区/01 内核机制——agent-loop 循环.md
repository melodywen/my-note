---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, 内核, agent-loop, core, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 01 内核机制——agent-loop 循环

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**07 篇（事件系统）**——本篇的 `agent/*` 事件是那套框架的具体应用；回顾 05 篇（Fiber/effect）
> - **本篇是深水区第 ① 块（内核机制）**——地基
> - 写法说明：本系列采用**完整重讲式**；本篇**讲透机制为主**（练习留待之后），**每段标出处**

> [!abstract] 本章是什么 / 该记住什么
> **性质**：**dsh 内核 agent-loop 的「解剖课」**——打开黑盒，讲清"dsh 内部怎么跑一个 agent"。
> 前三块（阶段一~三）你都在**外围绕**（写插件、配 profile、做集成）——**本篇第一次进入内核**。
>
> **本章干三件事**：
> 1. **讲理论**：agent-loop 是什么、为什么需要、vs ReAct
> 2. **介绍组件**：core 六包怎么协作、`ctx.agents`、`Agent` 句柄、`agent/*` 事件
> 3. **介绍钩子**：它暴露哪些扩展点（`agent/pre-step` / `request-error`）——**这是你以后能用的东西**
>
> **读完该记住 4 点**：
> 1. **agent-loop 是 dsh 自带的循环**（模型→工具→结果→再模型，直到模型说"够了"）——**你写不出、也不用写**
> 2. **它由 6 个包协作**（session / system-prompt / tools / agent / agent-loop / scope）
> 3. **它暴露钩子**（`agent/pre-step` 等 waterfall）——**你以后能在这些点"插话"**
> 4. **创建 Agent 用 YAML 配置**（`agents: [...]`），**不写 TS**
>
> ⚠️ **动手部分只是"装仪表盘"观测它**——不是"造 loop"。**loop 在内核里。**

## 这一篇在讲什么

前面你写插件、配 profile、做集成——但**始终没打开"dsh 到底怎么跑一个 agent"这个黑盒**。本篇打开它：**agent-loop 循环**。

> **出处**：`docs/subsystems/core.zh.md:9`（逐字）——*"一个轮次按同一条循环流经六个包"*

**本篇核心**：理解 **core 子系统**——一个"用户提问 → 模型回答 → 工具执行 → 再回答"的**完整循环**是怎么被 6 个包协作驱动出来的。

---

## 零、先搞懂：agent-loop 到底是什么

⚠️ **这一节先讲"是什么、为什么"，再进"怎么实现"**——否则容易一上来就懵。

> [!important] 先划清一件事（不模糊）
> **agent-loop 是 dsh 自带的能力**——由 `dsh-agent-loop` 包提供。
> **你写不出它，也不需要写它**——它开箱就转（起 dsh 问一句，它自己就会"调工具→看结果→再调→直到干完"）。
> **你能做的，是"挂钩子"旁观它**（`agent/pre-step` 等）——就像给自带引擎**装个仪表盘**。

### 一句话：agent-loop = "让 LLM 自主干多步活"的循环

**对比"普通调 LLM"**：

```
【普通调 LLM（一问一答）】
  用户提问 → LLM 回答 → 结束

【agent-loop（自主多步）】
  用户提问
    → LLM 说"我要调工具 A"          ← 第 1 步
    → 执行工具 A，结果给 LLM
    → LLM 说"我要调工具 B"          ← 第 2 步
    → 执行工具 B，结果给 LLM
    → LLM 说"我干完了"             ← 模型不再要工具 → 结束
```

**关键**：循环"**LLM 决定用工具 → 执行 → 结果回给 LLM → 再决定**"，**直到模型不再要工具**。

> **源码印证**（`packages/core/agent-loop/src/agent.ts`）：
> - `:228` — `while (await this.turn()) {}` ← **外层：轮次循环**
> - `:287` — `while (true) { preStep → 请求 → 工具 }` ← **内层：步骤循环**
> - **终止**：模型不再返回 `tool-calls`（回扣 01 篇的 `FinishReason`）

### Go 类比：agent-loop ≈ 一段 `for` 循环

```go
// agent-loop 的本质，就是这段逻辑：
for {
    resp := callLLM(history)               // 调模型
    if resp.NoToolCalls() { break }        // 模型说"不用工具了" → 停
    for _, call := range resp.ToolCalls {  // 模型要调工具
        result := executeTool(call)        // 执行
        history = append(history, result)  // 结果进历史（下次给模型看）
    }
}
```

**`agent-loop` 就是这段 `for`**——只不过加上了：
- **session 日志**（每步追加，真源）
- **权限/审批**（工具执行前检查）
- **拦截点**（`agent/pre-step` 等，见第四节）

### agent-loop vs ReAct（常见混淆）

> ⚠️ 如果你没见过 ReAct，可跳过（它是 LLM agent 的经典范式：**Thought → Action → Observation**）。

| | **ReAct** | **agent-loop** |
|---|---|---|
| 是什么 | 一种**范式/方法**（教模型怎么"想") | 一个**运行时机制**（管循环怎么跑） |
| 关注 | LLM **输出格式**：Thought→Action→Observation | **循环控制**：何时调工具、何时停 |
| 层级 | **Prompt 层面** | **工程层面** |
| 关系 | ReAct 的思想**可**用 agent-loop 实现 | agent-loop **可**用 ReAct、也可不用 |

**一句话**：**ReAct 是"套路"，agent-loop 是"跑套路的引擎"。**
- ReAct 管"**让模型先想再做、看结果再想**"（**提示词工程**）
- agent-loop 管"**拿到工具调用后怎么执行/回喂/判断停**"（**运行时工程**）

**dsh 的 agent-loop 是通用引擎**：模型"想不想"是模型/prompt 的事，循环只管"**你要调工具?我调；调完把结果给你；你说不用了?我停**"。

### ⚠️ 澄清：创建 Agent **不需要**写 TS 文件

**这是最容易搞混的点**：

| 你想做的事 | 要写 TS 吗 | 怎么做 |
|---|---|---|
| **创建一个 Agent**（人设/模型/工具集） | ❌ **改 YAML 配置** | `cordis.patch.yml` 里填 `agents: [...]` |
| **写一个插件**（给 Agent 加能力） | ✅ 写 TS | 如 `hello-plugin`、`mock-adapter` |
| **换 agent-loop 实现**（进阶，很少做） | ✅ 写 TS | 实现 `Agent` 约定 |

> **出处**：`core.zh.md:26`（逐字）——*"消费方通过 `ctx.agents` 创建 agent……**或者通过循环的声明式配置条目创建**。"*
> **默认配置**：`agents: []`（`packages/bundle/base/cordis.patch.yml:493`、`sdk-minimal:124`）——**一个配置数组**，往里填即可。

**Go 类比**：
- **Agent** ≈ **一个服务实例**（`server := NewServer(cfg)`）——**配置驱动**，不写新代码
- **插件** ≈ **给服务注册的 handler**——**写代码**
- **agent-loop** ≈ **HTTP server 本身**（`http.ListenAndServe`）——**用现成的**

---

## 一、core 子系统：一个轮次的流水线

### 六个核心包

> **出处**：`core.zh.md:11-18`（表格，逐字）

| 包 | 服务（`ctx.xxx`） | 职责 |
|---|---|---|
| `session/` | `ctx.sessions` | append-only `SessionEvent` 日志（**唯一真源**） |
| `system-prompt/` | `ctx.systemPrompt` | 提示词段落 + 工具 schema 组装 |
| `tools/` | `ctx.tools` | 带作用域的工具注册表 + 执行流水线 |
| `agent/` | `ctx.agents` | `Agent` 接口、注册表、`agent/*` 事件词汇 |
| `agent-loop/` | `ctx.agentLoop` | **具体 driver**（默认产品循环） |
| `scope/` | （非服务，库） | 按 agent 作用域的注册原语 |

> ⚠️ **注意**：这是文档"**主干逐包速览**"聚焦的 **6 个**——**实际 `packages/core/` 有 9 个**（另有 `agent-default-model`、`agent-tool-presentation`，见 01 篇的默认模型）。**别把"6 个"当成 core 全部。**

### 一个轮次的流向

> **出处**：`core.zh.md:9`（逐字）——*"`agent-loop` 中的 driver 认领一条排队的提示词，在会话日志上开启轮次，通过 `system-prompt` 组装请求前缀并从日志派生历史，经 LLM seam 流式获取模型响应，经工具注册表分发工具调用，并把每个模型可见的事实追加回日志，供下一步派生。"*

```
用户提问
  → agent-loop（driver 认领提示词，在 session 上开轮次）
  → system-prompt（组装前缀 + 从日志派生历史）
  → LLM（流式取模型响应）
  → tools（分发工具调用）
  → 追加回 session 日志（供下一步派生）
  → （循环，直到模型不再调工具）
```

**这就是"agent 干一件事"的全过程**——回扣 07 篇的 `turn/step/tool` 事件（那些事件就是这个循环一步步追加的）。

> **Go 类比**：像**一个 `for` 循环**——每轮：组请求 → 调模型 → 若模型要调工具就执行 → 结果入档 → 再循环。`agent-loop` 就是那个 `for`。

---

## 二、创建与所有权（`ctx.agents`）

**怎么造出一个 agent**：

> **出处**：`core.zh.md:24-26`（逐字）

```ts
ctx.agents.create(ownerCtx, options) → Promise<AgentHandle>   // 新建会话 + agent
ctx.agents.resume(ownerCtx, options) → Promise<AgentHandle>   // 加载持久会话
ctx.agents.get(id)                   → Agent                  // 裸句柄
```

### `AgentHandle`：owned agent + disposer

> **出处**：`core.zh.md:33-34`（逐字）

```ts
interface AgentHandle {
  agent: Agent
  dispose(): Promise<void>
}
```

> **关键语义**（文档逐字）——*"The disposer is a **CAPABILITY**: among consumers, **only the holder** can tear this agent down."*

**disposer 是"能力"**——**只有持有句柄的那个消费者**能拆掉这个 agent。**不是"谁都能 dispose"**。

**`dispose()` 做什么**（文档逐字）：停止循环 → 等它退出 → 反注册 agent → 从 store 移除其会话 → 解绑其作用域世界。

**配置创建的 agent**（loop 自己启动的）由 **loop fiber 拥有**，不需要句柄。

> **Go 类比**：像 `context.CancelFunc`——**只有拿到 cancel 的人才取消得了**（能力封装）；别人拿到 `ctx` 也取消不了。

### ⭐ 关键设计：`agent/`（接口）≠ `agent-loop/`（实现）

> **出处**：`core.zh.md:20`（逐字）——*"扩展插件依赖 `agent`——包括需要发起 Agent 时——而**绝不直接依赖 `agent-loop`**，因此循环保持可替换。"*

**这是 seam 思想**（回扣 08 篇！）：
- `agent/` = **Definition**（`Agent` 接口）
- `agent-loop/` = **Provider**（具体 driver）
- 扩展插件 = Consumer（**只依赖接口**）

**所以循环可替换**——你可以换一个 driver 实现，扩展插件不受影响。

---

## 三、`Agent` 句柄：编程接口

`Agent` 是**每个插件（UI/钩子/orchestrator）面向编程的 surface**。

> **出处**：`core.zh.md:57` + `runtime-types.ts`（方法逐条实读）

```ts
interface Agent {
  readonly id: SessionId
  readonly options: AgentOptions
  readonly session: Session      // 会话日志（真源）
  readonly inbox: Inbox          // 待处理队列
  readonly status: AgentStatus   // 'idle' | 'running'
  readonly ctx: Context          // agent 作用域

  send(message, target, wakeup)  // 通用投递（暴露 target + wakeup 路由）
  followup(message)              // 别名预设
  steer(message)                 // 中途引导
  inject(message)                // 注入
  cancel(cause, options)         // 取消
  whenIdle(): Promise<void>      // 等静默
}
```

> **出处**：方法签名 `runtime-types.ts:191,215,222,231,241`；`AgentStatus` 定义 `:109`

**四个投递方法**（文档逐字）：*"统一的 `send` 方法直接暴露 target 与 wakeup 路由；`followup`、`steer` 与 `inject` 是**固定预设的别名方法**。"*

> **出处**：`core.zh.md:59`

**`AgentStatus` 只有两态**：`'idle' | 'running'`（`runtime-types.ts:109`）——**极简**。

> **Go 类比**：`Agent` ≈ 一个**可投递消息、可取消、可等待的 worker 句柄**（像 `errgroup.Group` + 消息队列）。

---

## 四、⭐ 拦截决策：agent-loop 的精髓

**循环的关键扩展点**——两个 `waterfall`（**回扣 07 篇**：waterfall = 瀑布式，必须调 `next()`）。

### `agent/pre-step`（步骤开始前）

> **出处**：`core.zh.md:345`（逐字）——*"`agent/pre-step` 是**请求推导前唯一的 waterfall 监听器链**。"*

```ts
'agent/pre-step'(payload: { agent, messages, turn, step, signal }, next)
  → Promise<PreStepDecision>                      // runtime-types.ts:320
```

**返回 `PreStepDecision`**：
> **出处**：`core.zh.md:322-330`（逐字）
```ts
type PreStepDecision =
  | { kind: 'reject' }                            // 不进入步骤
  | { kind: 'enter'; messages: UserMessage[]; startsRequestSeries?: true }
```

| 决策 | 含义 |
|---|---|
| `reject` | **不打开**步骤 |
| `enter` | 提供**进入步骤的完整消息批次**（`step/start` 后追加） |

**典型用途**：钩子（hooks）在这里**拦截/改写**用户消息（如注入上下文、做安全审查）。

> **出处**：`core.zh.md:322`——*"hooks 桥接层把其原生决策字段映射到这一类型化结果上"*

### `agent/request-error`（请求失败后）

> **出处**：`core.zh.md:338`（逐字）——*"`agent/request-error` 在失败的模型步骤关闭之后、其轮次关闭之前运行。"*

```ts
'agent/request-error'(payload: { agent, turn, step, provider, failure, retryPolicy, signal }, next)
  → Promise<RequestErrorAction>                    // runtime-types.ts:353
```

```ts
type RequestErrorAction = { kind: 'retry' } | undefined
```

| 返回 | 含义 |
|---|---|
| `{ kind: 'retry' }`（**且不调 `next()`**） | **重试** |
| `undefined`（默认） | 失败保持**终态** |

**这就是"错误恢复/重试"的扩展点**——listener 可以在失败轮次的 signal 仍存活时**修状态或重试**。

> **Go 类比**：
> - `pre-step` ≈ **HTTP 中间件**（可拦截/改写请求）——`next()` 像洋葱模型
> - `request-error` ≈ **错误恢复中间件**（判断是否重试）

---

## 五、`agent/*` 事件词汇（一大系列）

`core.zh.md` 后半段（`:914` 起）**全是 `agent/*` 事件**——这就是 07 篇说的"**事件生产方/消费方矩阵**"的具体体现。

代表事件（各有分发模式）：

| 事件                       | 模式            | 含义                 |
| ------------------------ | ------------- | ------------------ |
| `agent/created`          | serial        | agent 创建           |
| `agent/disposed`         | emit          | agent 销毁           |
| `agent/status`           | emit          | 状态变化（idle/running） |
| `agent/pre-step`         | **waterfall** | 步骤前拦截              |
| `agent/request`          | **waterfall** | 请求构建               |
| `agent/request-error`    | **waterfall** | 请求失败恢复             |
| `agent/turn-stopping`    | serial        | 轮次即将结束             |
| `agent/assistant-stream` | emit          | 流式响应分片             |

> **出处**：`core.zh.md:914-1187`（`agent/* events` 节，逐条）

---

## 六、动手案例：给自带的 agent-loop "装仪表盘"（已实测）

> **规则（AGENTS.md）**：动手环节"你动手"。本节给出**可复制的命令**，你直接跑。

### 目标（先说清：你不是在"写 loop"）

**agent-loop 是 dsh 自带的**——你**不写它**、也**看不到它本体**。本案例做两件事：

| 你做 | 本质 | 作用 |
|---|---|---|
| **`count-up-tool`** | **一个工具**（第 02 篇的活） | 给模型一个"数数"的任务载体 |
| **`agent-loop-watcher`** | **一个事件监听器**（第 07 篇的活） | 钩住 `agent/pre-step`，把循环的"读数"打出来 |

> **一句话**：**引擎（loop）是 dsh 自带的；你只是给了它一个工具 + 一个观测钩子**，好让自带循环"留下可见的痕迹"。

**思路**：让模型"从 1 数到 5"——它（模型自己决定）**调 5 次工具** → **循环转 5 圈** → 日志里看得见。

> ⚠️ **必须澄清**：这里的"看得见"是指**看见循环的痕迹（step 读数）**，**不是看见循环本体**。你写的插件没有任何 `while`——**`while` 在 dsh 内核里**。

### 案例位置

```
dsh-learn/example/deepwater/plugins/agent-loop-demo/
├── count-up-tool/           ← 工具（独立文件夹）
│   └── count-up-tool.ts
├── agent-loop-watcher/      ← 观测插件（独立文件夹）
│   └── agent-loop-watcher.ts
└── agent-loop-demo.patch.yml
```

### 核心代码

**工具**（`count-up-tool/count-up-tool.ts`）：

```ts
import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'

let counter = 0

export const name = 'count-up-tool'
export const inject = ['tools']

export function apply(ctx: Context) {
  ctx.tools.register(defineTool({
    name: 'count_up',
    description: 'Count up by exactly one. To count 1..N you MUST call this N times, once per step.',
    parameters: {},
    output: { schema: { type: 'string' }, render: (_a, v) => [{ type: 'text', text: v }] },
    async execute() { counter += 1; return `count = ${counter}` },
  }))
}
```

**观测插件**（`agent-loop-watcher/agent-loop-watcher.ts`）：

```ts
import type { Context } from '@deepseek-ai/cordis'
import type { PreStepDecision } from '@deepseek-ai/dsh-agent'

export const name = 'agent-loop-watcher'
export const inject = ['tools']

export function apply(ctx: Context) {
  // 每进一个步骤前：打印 turn / step（循环的"心跳"）
  ctx.on('agent/pre-step', async ({ turn, step, messages }, next): Promise<PreStepDecision> => {
    console.log(`[loop] ── 即将进入 第 ${turn} 轮 第 ${step} 步（本步 ${messages.length} 条消息）`)
    return next()
  })
  // 每次工具执行完：打印工具名 + 结果
  ctx.on('tools/result', (exec, result) => {
    const text = (result.content ?? []).map(b => b.type === 'text' ? b.text : '').join('')
    console.log(`[loop]   ↳ 工具 ${exec.name}() 执行完 → ${text}`)
  })
}
```

### 🔧 运行（**网页**，你亲手跑）

**三步走**：

**第 ① 步：终端启动**（复制这段到终端）：

```sh
cd ~/ai-work/dsh/dsh-learn
./start.sh --patch "$PWD/example/deepwater/plugins/agent-loop-demo/agent-loop-demo.patch.yml"
```

> `./start.sh` 已自动挂 codebuddy 层（保证有模型适配器）；你只需再叠 agent-loop-demo 层。

**第 ② 步：浏览器**打开它打印的地址（`http://127.0.0.1:3080/?token=...`，dsh 通常自动弹出）。

**第 ③ 步：在网页对话框里，粘贴下面这句话**（⚠️ **必须输入这句**，普通聊天不会触发循环）：

> [!important] 📋 网页对话框里输入这一句（复制）
> ```
> 从 1 数到 5。规则：禁止直接说数字，必须每次只调一次 count_up 工具，共调五次，最后汇总。
> ```

> **为什么必须这句**：普通聊天（如"你好"）**模型不需要工具** → 循环不转。这句**强制模型调 5 次 `count_up`** → 循环转 5 圈。**这是案例的机关。**

**第 ④ 步：看终端**（你启动 dsh 的那个窗口）——会打印（实测输出）：

```
[loop] ── 即将进入 第 1 轮 第 1 步（本步 1 条消息）
[loop]   ↳ 工具 count_up() 执行完 → count = 1
[loop] ── 即将进入 第 1 轮 第 2 步（本步 0 条消息）
[loop]   ↳ 工具 count_up() 执行完 → count = 2
[loop] ── 即将进入 第 1 轮 第 3 步（本步 0 条消息）
[loop]   ↳ 工具 count_up() 执行完 → count = 3
[loop] ── 即将进入 第 1 轮 第 4 步（本步 1 条消息）
[loop]   ↳ 工具 count_up() 执行完 → count = 4
[loop] ── 即将进入 第 1 轮 第 5 步（本步 0 条消息）
[loop]   ↳ 工具 count_up() 执行完 → count = 5
[loop] ── 即将进入 第 1 轮 第 6 步（本步 1 条消息）   ← 不再要工具
```

**模型最终回复**：`已完成。按规则共调用 count_up 五次：1 → 2 → 3 → 4 → 5`

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

### 📖 这张日志 = 循环留下的"痕迹"（不是循环本身）

> [!warning] 别误会：你的插件**没有**"写"循环
> 你写的两个插件，本质就是**一个工具 + 一个打印**——**没写任何 loop**。
> **loop 是 dsh 内核自带的**（`agent.ts` 里的 `while`），**你看不到它本体**。
> **你的插件做的是"装仪表盘"**——通过 `agent/pre-step` 钩子**旁观**那个自带的循环。
> **日志不是循环，是循环的"读数"。**

```
【1 轮（turn 1）里转了 5 个步骤（step）】
  第 1 步：模型要调 count_up → 执行 → 结果(1)回给模型     ← 循环转第 1 圈
  第 2 步：模型要调 count_up → 执行 → 结果(2)回给模型     ← 第 2 圈
  ...
  第 5 步：模型要调 count_up → 执行 → 结果(5)回给模型     ← 第 5 圈
  第 6 步：模型【不再要工具】→ 输出汇总 → 循环结束        ← 退出条件
```

**回扣本节的 `while` 循环**（`agent.ts:228`/`:287`）——**日志里的"第 N 步"就是内层 `while (true)` 的每一圈**；**"第 1 轮"就是外层 `while` 的一次**。

**这就是"让 LLM 自主干多步活"**——模型一步步要工具，循环一圈圈转，直到模型说"够了"。

### 🔬 怎么确信"这真是循环"（而非硬编码调 5 次）

**光看 step 日志不够铁**——你可能会怀疑"是不是 dsh 手动调了 5 次"。

**铁证方法**：**让"圈数"随输入变化**——
- 输入 **"数到 3"** → 日志转 **3 圈**
- 输入 **"数到 8"** → 日志转 **8 圈**

**圈数跟着你的输入变 → 证明是"模型驱动循环"（每圈由模型决定"要不要再来"），而非硬编码。** 这就是 agent-loop 的"活"。

> **出处**：本人实测（2026-09-16）——`count_up` 工具每次 +1，模型要数到几就调几次，**step 号随之变化**。

### ⚠️ 运行踩坑（记录）

1. **headless 测试要挂 codebuddy 层**：`NO_ADAPTER: no adapter registered for provider "codebuddy"`——因为 `~/.dsh/settings.yaml` 说用 codebuddy，但**没挂对应适配器插件**。**挂上 `codebuddy-llm-v2` 层即可**（`./start.sh` 自动处理）。
2. **模型"偷懒"风险**：若提示不够强制，模型可能**直接报答案不调工具**。本案例的提示**明确要求"禁止直接说数字、必须调工具"**——才好使。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **core 六包** | session/system-prompt/tools/agent/agent-loop/scope | — | `core.zh.md:11-18` |
| **一个轮次流向** | driver→session→prompt→LLM→tools→回日志 | `for` 循环 | `core.zh.md:9` |
| `ctx.agents.create/resume` | 造/恢复 agent → `AgentHandle` | 起 worker | `core.zh.md:24` |
| **`AgentHandle`** | `{agent, dispose}`；disposer 是**能力** | `context.CancelFunc` | `core.zh.md:33` |
| **agent 接口 ≠ 循环实现** | 插件只依赖 `agent`，循环**可替换** | seam（08 篇） | `core.zh.md:20` |
| `Agent` 句柄 | 4 投递方法 + cancel + whenIdle | worker 句柄 | `runtime-types.ts` |
| `AgentStatus` | 仅 `idle`/`running` 两态 | — | `runtime-types.ts:109` |
| **`agent/pre-step`** | 请求前**唯一** waterfall；reject/enter | HTTP 中间件 | `core.zh.md:345` |
| **`agent/request-error`** | 失败后可重试（retry/undefined） | 错误恢复中间件 | `core.zh.md:338` |
| `agent/*` 事件 | 一大系列，各有分发模式 | 07 篇矩阵 | `core.zh.md:914+` |

## 踩坑预防

- **⚠️ "core 六包"是文档聚焦，不是全部**：实际 `packages/core/` 有 9 个（+agent-default-model、agent-tool-presentation）。（出处：`ls packages/core/`）
- **⚠️ 扩展插件别依赖 `agent-loop`**：只依赖 `agent`（接口），否则循环不可替换。（出处：`core.zh.md:20`）
- **⚠️ `AgentHandle` 的 disposer 是能力**：不是谁都能 dispose。（出处：`core.zh.md:33`）
- **⚠️ `agent/pre-step` 返回 `reject` 就不会开步骤**：不是"跳过"，是"不进入"。（出处：`core.zh.md:322`）

## 下一步

- **案例已实测** ✅：`count-up-tool` + `agent-loop-watcher`（循环可见）
- **深水区 ②**：dynamic-cordis（运行时自扩展）
