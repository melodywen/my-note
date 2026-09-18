---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, workflow, 编排, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 05 workflow——模型写的"编排脚本"

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**04 篇（subagent）**——workflow **起的就是 subagent**（编排层）
> - 写法说明：本系列采用**完整重讲式**；以**读源码 + 讲机制**为主

> [!abstract] 本章是什么 / 该记住什么
> **回答的问题**："**workflow** 是什么、干嘛的？"
> **答案**：**让模型"写一段 JS 脚本"，脚本里 `agent()` 调起多个 subagent**——**大规模编排**。
> **读完该记住 4 点**：
> 1. **workflow = "模型写脚本" + "脚本编排 subagent"**
> 2. **又是一条 seam**：`ctx.workflowEngine`（Def）+ Provider（`workflow-ptc`）+ Consumer（`tool-workflow`/`tool-ralph`）
> 3. **与 subagent 的差别**：subagent = 1~2 个委派；**workflow = 大规模编排**（几十个子 agent + phases）
> 4. **⚠️ 只在大规模编排时用**——"一两个委派用普通 subagent"

## 这一篇在讲什么

**04 篇的 subagent = "起一个子 agent"**。**但如果要"起 20 个子 agent、分阶段跑、汇总"**呢？——**一个个调 subagent 太笨**。**workflow 就是解这个的**：**让模型写一段脚本，脚本里批量调 `agent()`**。

> **出处**：`workflow.zh.md:1`（逐字）——*"工作流 seam 允许 agent 运行由**模型编写、会启动 subagent 的编排脚本**。"*

**一句话**：**workflow = "跑一段模型写的 JS 脚本的 seam"**——脚本里用 **`agent()`/`parallel`/`pipeline`** 编排（**常用来编排多 subagent**）。

> **⚠️ 精确说**：**它是"通用脚本执行"**——**`agent()` 只是脚本能用的函数之一**（可不用）。**"编排多 agent"是它的主要用途，不是它的定义**。

> **Go 类比**：像**"给模型一个能跑 JS 的沙箱 + 几个编排原语（`agent`/`parallel`/`pipeline`）"**——**模型写 `go func()` 起 worker + `errgroup` 汇总**。

---

## 一、又是一条 seam（第七次）

| 角色 | 包 | 说明 |
|---|---|---|
| **Definition** | `dsh-workflow`（`ctx.workflowEngine`） | 抽象（`start()`） |
| **Provider** | `dsh-workflow-ptc` | 用 **Node PTC 运行时**执行 VM |
| **Consumer** | `dsh-tool-workflow`（`workflow` 工具）+ `dsh-tool-ralph`（`ralph` 工具） | 面向模型 |

> **出处**：`workflow.zh.md:1`（逐字）——*"与 bash 一样，**每个上下文只允许一个引擎实现**提供 `ctx.workflowEngine`；没有命名提供方注册表（第二个引擎替换第一个，而不与它同时运行）。"*

**⚠️ 与 subagent 的区别**：**subagent 是多提供方**（按名注册）；**workflow 是单引擎**（像 bash）。

---

## 二、⭐ 脚本里到底有什么？（源码级）

**这是本篇最核心的**——**"workflow 脚本"不是黑盒**，它跑在一个 VM 里，有**固定的全局函数**。

> **出处**：源码 `packages/workflow/workflow-ptc/src/guest-source.ts`（`WORKFLOW_GUEST_SOURCE` 的 `globals`，逐字）
```js
const globals = {
  agent:    (prompt, opts) => ...,     // ⭐ 起一个 subagent
  parallel: (thunks) => ...,           // 并行跑一组
  pipeline: (items, ...stages) => ..., // 流水线（每个 item 走一串 stage）
  phase:    (title) => ...,            // 阶段标签（进度展示）
  log:      (message) => ...,          // 日志
  args,                                // 启动时传入的 args
}
```

### 全局函数逐个说

| 函数 | 作用 |
|---|---|
| **`agent(prompt, opts?)`** | **起一个 subagent**（返回：结构化 `schema` 结果，或文本） |
| **`parallel(thunks)`** | **并行**跑一组 thunk（每个 thunk 返回 Promise） |
| **`pipeline(items, ...stages)`** | **流水线**：每个 item 依次走各 stage（**无跨 stage 屏障**） |
| **`phase(title)`** | 设"当前阶段"标签（**仅进度展示**，不暗示执行结构） |
| **`log(message)`** | 打日志 |
| **`args`** | 启动请求传入的 `args`（**原样暴露**） |

### `agent(prompt, opts)` 的细节（约束很严）

> **出处**：`workflow-ptc/src/runtime.ts`（`SUPPORTED_AGENT_OPTIONS`，逐字）

```ts
const SUPPORTED_AGENT_OPTIONS = new Set([
  'label', 'phase', 'schema', 'provider', 'model',
])
```

| 点 | 说明 |
|---|---|
| **`prompt`** | **必须是非空字符串**（否则报 `INVALID_ARGUMENT`） |
| **`opts` 只支持** | `label` / `phase` / **`schema`** / `provider` / `model`——**别的明确报错**（`UNSUPPORTED_OPTION`） |
| **`schema`** | 传了 → 子 agent 返回**结构化结果**（`result.structured`）；不传 → 返回文本 |
| **不支持**（deferred） | `effort` / `isolation` / `agentType`——**明确报错** |
| **上限** | `maxTotalAgents`（默认 **1000**，**防死循环**）+ `maxConcurrentAgents`（并发）+ `maxItemsPerCall`（每次 `parallel`/`pipeline` 的 item 上限） |

> **出处**：`runtime.ts`——`agent()` hook + `acquireSlot()`（并发槽）+ `assertItemCap()`

### ⭐ 关键修正：**脚本"不强制"起 agent**

**`agent()` 只是"可用的函数之一"**——**脚本可以只用 `parallel`/`pipeline` 做纯计算，一个 agent 都不起**。

**所以准确定义**：

> **workflow = 一条 seam，跑"模型写的 JS 脚本"；脚本里"可以"用 `agent()` 起 subagent、用 `parallel`/`pipeline` 编排——它"常用来"编排多 agent，但"本身"是通用脚本。**

### 一个脚本长啥样（示意）

```js
// 脚本（顶层 await；最后 return 一个 JSON 值）
const tasks = ['算 A', '算 B', '算 C']

phase('并行计算')
const results = await parallel(tasks.map(t => () =>
  agent(`请做：${t}`, { schema: { type: 'object', properties: { answer: { type: 'string' } } } })
))

phase('汇总')
return { results }     // ⭐ 必须是纯 JSON
```

> **出处**：脚本格式见 `WorkflowStartRequest.script`——*"The plain-JS script body (top-level await allowed; ends with `return <json-value>`)"*

---

## 三、⭐ 执行路径：串行 / 树状 / 网状

**你的直觉**："workflow 就是**规划一条路径**——A 完了做 B、B 完了做 C；可以是**串行直线**、**树状**、或**网状**。" —— **对！**

**用脚本的三个原语表达**：

| 结构 | 脚本写法 | 说明 |
|---|---|---|
| **串行**（直线） | `await agent(A); const r = await agent(B)` | **一个接一个** |
| **树状**（扇出→汇总） | `const rs = await parallel([...]); return 汇总(rs)` | **并行出多个、再合并** |
| **网状**（有依赖） | `pipeline(items, stage1, stage2)` / 嵌套 `parallel` | **每个 item 走一串 stage，或依赖组合** |

**`parallel`/`pipeline` 的语义**（逐字）：
> **出处**：`dynamic-workflows.zh.md:17`——*"正文接收 `agent(prompt, options)`、`parallel(thunks)`、`pipeline(items, ...stages)`、`phase(title)`、`log(message)` 和 `args`。**流水线各阶段接收 `(prev, item, index)`，阶段之间无屏障**；失败的子 agent 和普通阶段错误将受影响的 item 结算为 `null` 并跳过其剩余阶段。"*

- **`parallel(thunks)`** = **扇出**（一组并行）
- **`pipeline(items, ...stages)`** = **流水线**（每个 item 顺序过各 stage，**stage 间无屏障**——不用等全部 item 过完 stage1）
- **`agent()` 调用 = 一个节点**；`parallel`/`pipeline` = **连接**

### ⚠️ 关键修正：**是"模型规划"，不是"人手工画路径"**

> **出处**：`dynamic-workflows.zh.md:9`（逐字）——*"**模型**编写一段 JavaScript 编排脚本，运行时执行它，**由脚本（而非对话）持有循环、分支和中间结果**。"*

| | 说法 |
|---|---|
| **谁写路径** | ⚠️ **模型写**（模型写脚本） |
| **能不能"人规划"** | ✅ **能**——**你要求模型"按我说的路径写"**，它就写成那样 |
| **"路径"存在哪** | **脚本里**（变量、`parallel`/`pipeline`），**不是"每步塞进对话"** |

**⭐ 核心收益**（为什么需要它）：
> **出处**：`dynamic-workflows.zh.md:9`（逐字）——*"每个中间结果都落入**父上下文**，计划**无处持久存储**，每一步的协调都要**消耗一次模型往返**。"*（这是**没有 workflow 时**的痛点）

**有了 workflow**：
- **循环/分支/中间结果** → **在脚本里**（不塞父上下文）
- **一次启动** → 脚本**跑完整个编排**（不用每步一次模型往返）

### 一个"串行 + 树状"的例子

```js
// 串行：先调研，再实现
phase('调研')
const research = await agent('调研一下需求', { schema: {...} })

phase('实现')   // 树状：三个独立模块并行实现
const modules = await parallel([
  () => agent(`实现模块 A（基于：${research.summary}）`),
  () => agent(`实现模块 B（基于：${research.summary}）`),
  () => agent(`实现模块 C（基于：${research.summary}）`),
])

phase('汇总')
return { research, modules }
```

**这就是**：**"调研 →（扇出）A/B/C → 汇总"**——**一条"树状"路径**（脚本持有）。

---

## 四、核心：模型写脚本（`WorkflowStartRequest`）

### `WorkflowStartRequest`（启动请求）

> **出处**：`workflow.zh.md:11`（逐字）

```ts
interface WorkflowStartRequest {
  script: string          // ⭐ 模型写的 JS 脚本（顶层 await 允许；以 return 结束）
  meta: WorkflowMeta      // 身份块（name/description/... 校验）
  args?: unknown          // 传给脚本的 args 全局
  subagentProvider?: string  // 子 agent 用哪个提供方
  maxTotalAgents?: number    // 子 agent 总数上限
  parent: Agent           // ⭐ 每个子 agent 都归属它（cwd/谱系/深度）
  signal?: AbortSignal
}
```

**关键**：
- **`script`** = **模型写的 JS**（不是 JSON）——**脚本里 `agent()` 起子 agent**
- **`meta`** = **身份块**（`{ name, description, whenToUse?, phases? }`）——`meta` 是**普通 JSON**，**引擎用 schema 校验**（*"绝不会通过对脚本文本求值来获取"*）
- **`parent`** = 必填（子 agent 归属）

### `WorkflowMeta`（身份）

> **出处**：`workflow.zh.md:39`（逐字）
```ts
interface WorkflowMeta {
  name: string           // kebab-case 短名（显示 + 持久化 key）
  description: string    // 一句话
  whenToUse?: string     // 何时用（列表里显示）
  phases?: WorkflowPhase[]  // ⭐ 阶段声明（进度展示用）
}
```
**`phases` 仅用于进度展示**（`phase()` 调用与标题匹配）——**不暗示执行结构**。

### `WorkflowResult`（终态结果）

> **出处**：`workflow.zh.md:63`（逐字）
```ts
interface WorkflowResult {
  value: unknown              // 脚本的返回值（宿主 JSON；无返回=null）
  stopReason: WorkflowStopReason  // completed | cancelled | error
  error?: string              // 失败信息（非 completed 时有）
  agentsStarted: number       // 整个生命周期起了多少个子 agent
}
```

---

## 五、`ctx.workflowEngine`（Definition）

> **出处**：`workflow.zh.md:140`（逐字）
```ts
abstract class WorkflowEngine {
  abstract start(request: WorkflowStartRequest): WorkflowRun
  // 返回"活运行"；其 result 在脚本 settle 时 resolve
}
```
**"活运行"**（`WorkflowRun`）：holder 拥有；**result 永不 reject**；disposal 等脚本 + 子 agent 清理完。

---

## 六、⭐ 使用纪律（**重要**）

> **出处**：`tool-workflow/src/index.ts:214`（逐字，系统提示词）

```ts
`Use the ${toolName} tool ONLY when the user explicitly asks for a workflow or for large multi-agent orchestration: you write a JavaScript script (the tool description documents the exact format) that fans work out across many subagents with phases and structured results. For one or two delegations, prefer plain subagent calls.`
```

**翻译**：
- **只在**"用户明确要求 workflow"**或**"大规模多 agent 编排"时用
- **它让你写 JS 脚本**——**扇出到多个 subagent + 分阶段 + 结构化结果**
- **⚠️ "一两个委派，用普通 subagent"**（别杀鸡用牛刀）

**所以**：**workflow vs subagent 的选择**：

| 场景 | 用谁 |
|---|---|
| **1~2 个委派** | ✅ **subagent**（04 篇） |
| **大规模编排**（几十个 agent + phases） | ✅ **workflow**（本篇） |

---

## 七、两个消费方：`workflow` 与 `ralph`

> **出处**：`packages/workflow/{tool-workflow,tool-ralph}/`

| 工具 | 说明 |
|---|---|
| **`workflow`**（`tool-workflow`） | 默认工具名 `workflow`——**模型写脚本** |
| **`ralph`**（`tool-ralph`） | *"Workflow vs Ralph"*——**Ralph 循环**（另一种编排消费方，需显式启用） |

**base bundle 默认挂**：`workflow-ptc` + `tool-workflow`（`:372-378`）；`tool-ralph`（`:426`）。

---

## 八、动手（指南）

> **规则（AGENTS.md）**：动手环节"你动手"。本节是**指南**（未实测）。

**思路**：
1. base **已默认挂** `workflow` 工具（**开箱**）
2. 起 dsh
3. **让模型"写个 workflow"**——比如"用 workflow 编排 10 个子 agent 分别算 1~10 的平方，汇总"
4. 观察：**模型写脚本 → `agent()` 扇出 → 汇总结果**

> ⚠️ **未实测**：脚本语义/沙箱细节较复杂——**动手阶段先试"小规模"**。

---

## 一页纸总结

| 概念                             | 一句话                                                | 出处                   |
| ------------------------------ | -------------------------------------------------- | -------------------- |
| **workflow**                   | 模型写的编排脚本（起多个 subagent）                             | `workflow.zh.md:1`   |
| **又是 seam**                    | `ctx.workflowEngine`（单引擎，像 bash）                   | `:1`                 |
| **`WorkflowStartRequest`**     | `script`（JS）+ `meta` + `parent`                    | `:11`                |
| **`WorkflowMeta`**             | `{ name, description, whenToUse?, phases? }`       | `:39`                |
| **`WorkflowResult`**           | `{ value, stopReason, error?, agentsStarted }`     | `:63`                |
| **`ctx.workflowEngine.start`** | 返回"活运行"                                            | `:140`               |
| **消费方**                        | `tool-workflow`（`workflow`）+ `tool-ralph`（`ralph`） | `packages/workflow/` |
| **⚠️ 只在大规模编排用**                | 1~2 委派用 subagent                                   | `tool-workflow:214`  |

## 踩坑预防

- **⚠️ 别杀鸡用牛刀**：1~2 个委派用 **subagent**，别用 workflow。（出处：`tool-workflow:214`）
- **⚠️ workflow 是单引擎**：不像 subagent 多提供方。（出处：`workflow.zh.md:1`）
- **⚠️ `meta` 是 JSON 不是脚本**：引擎用 schema 校验，不 eval。（出处：`:11`）
- **⚠️ `phases` 只用于展示**：不暗示执行结构。（出处：`:39`）

## 下一步

- **06 篇**：goal（目标驱动自动续跑）
- **07 篇**：agent-team（团队协作）
