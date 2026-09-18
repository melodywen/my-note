---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, subagent, 多agent, seam, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 04 多 Agent 协作——subagent 委派

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**08 篇（seam 三角色）**——subagent 是三角色**第六次**应用；回顾 01 篇（agent-loop）
> - **本篇是深水区第 ③ 块「多 Agent 协作」的开篇**（核心是 subagent）
> - 写法说明：本系列采用**完整重讲式**；**委派已实测成功**

> [!abstract] 本章是什么 / 该记住什么
> **性质**：**让主 agent 把工作"委派"给子 agent**——多 Agent 协作的核心机制。
> **读完该记住 5 点**：
> 1. **它是一条 seam**（第六次）：`ctx.subagents`（Def）+ **6 个提供方** + `tool-subagent`（Consumer）
> 2. **与 bash 的差异**：**多提供方共存**（按名注册），不像 bash 只允许一个
> 3. **面向模型的工具**：`subagent`（spawn，新子 agent）/ `subagent_fork`（fork，继承历史）/ `send_message` / `interrupt_agent` / `list_agents`
> 4. **由 agent preset 选择**：默认 `disabled`，`standard` preset 启用它们
> 5. **两类能力**：单次（provider 组合）vs **可继续**（continuation 管理器组合）

## 这一篇在讲什么

**主 agent 一个人干不完的活，可以"分给子 agent"**——这就是 **subagent**：**dsh 的多 Agent 协作机制**。

> **出处**：`subagent.zh.md:5`（逐字）——*"subagent seam 让一个 agent（智能体）将工作委派给子 agent。"*

**一句话**：**主 agent 调用 `subagent` 工具 → 起一个子 agent 干活 → 拿回结果。**

> **Go 类比**：像**主 goroutine `go func()` 起个 worker**——**分活、等结果**。只不过这里"worker"是**一个完整的 dsh agent**（有自己会话、模型、工具）。

---

## 一、它又是 seam（第六次）——但与 bash 有个大差异

| 角色 | 包 | 说明 |
|---|---|---|
| **Definition** | `dsh-subagent`（`ctx.subagents`） | 服务 + 词汇 |
| **Provider**（**6 个**） | `spawn-in-process` / `fork-in-process` / `acp` / `codex` / `claude-code` / `dsh-sdk` | **多提供方共存**（**按名注册**） |
| **Consumer** | `tool-subagent` / `tool-subagent-control` | 面向模型的工具 |

> **出处**：`subagent.zh.md:5`（逐字）——*"它不同于其他能力 seam，因为**同一上下文中可共存多个提供方实现**，并按名称注册（`ctx.subagents`），而 **bash 只允许一个执行器**。该注册表遵循 LLM 适配器注册表，而非单服务的 bash 执行器。"*

**⭐ 关键**：**`subagent` 像 `llm`（多适配器注册表），不像 `bash`（单服务）**——
- **`bash`**：一个 context **只能挂一个**执行器
- **`subagent`**：**6 个提供方可以同时挂**，**按名字选**（`provider: spawn` / `fork` / …）

> **出处**：`subagent.zh.md:5`；6 个提供方包实读

---

## 二、6 个提供方（都是"怎么起子 agent"的不同实现）

| 提供方 | 怎么起子 agent |
|---|---|
| **`spawn-in-process`** | **进程内**起一个**全新**子 agent（干净上下文） |
| **`fork-in-process`** | **进程内**起一个**继承父历史**的子 agent |
| `acp` | 通过 ACP 协议（外部进程） |
| `codex` | 通过 Codex |
| `claude-code` | 通过 Claude Code |
| `dsh-sdk` | 通过 DSH SDK（独立子运行时） |

**base bundle 默认挂了**：`subagent` + `spawn-in-process` + `fork-in-process`。

> **出处**：`packages/bundle/base/cordis.patch.yml:328-343`

---

## 三、面向模型的工具（4 个变体，**由 preset 选择**）

**关键**：**这些工具默认 `disabled`**——**由 agent preset 决定"给 agent 看哪些"**。

> **出处**：`web-app/cordis.patch.yml:447-457`（`disabled: true`）——*"What a preset chooses is which delegation TOOLS its agent sees"*

**`standard` preset 启用的**（真实内容）：

> **出处**：`packages/preset/agent-presets/presets/standard/agent.cordis.yml:175-198`

```yaml
- id: tool-subagent
  name: '@deepseek-ai/dsh-tool-subagent'
  config:
    provider: spawn           # 用 spawn 提供方
    toolName: subagent        # 模型看到的工具名
    backgroundMode: continuable

- id: tool-subagent-fork
  name: '@deepseek-ai/dsh-tool-subagent'
  config:
    provider: fork            # 用 fork 提供方
    toolName: subagent_fork
    backgroundMode: continuable

- id: tool-subagent-control            # send_message / interrupt_agent
- id: tool-subagent-list-agents        # list_agents
```

**模型看到的工具**：

| 工具                                 | provider | 干什么                |
| ---------------------------------- | -------- | ------------------ |
| **`subagent`**                     | spawn    | 委派**新**子 agent（干净） |
| **`subagent_fork`**                | fork     | 委派**继承历史**的子 agent |
| `send_message` / `interrupt_agent` | —        | 控制子 agent          |
| `list_agents`                      | —        | 列出子 agent          |

> **`backgroundMode: continuable`**：子 agent 可以**后台跑 + 后续继续对话**（不是一问一答就结束）。

---

## 四、两类能力（重要区分）

> **出处**：`subagent.zh.md:13`

| 类型                   | 谁组合子 agent         | 怎么发现能力                                         |
| -------------------- | ------------------ | ---------------------------------------------- |
| **单次（one-shot）**     | **提供方**（`start()`） | `SubagentCapabilities`（静态描述符，5 个 flag）         |
| **可继续（continuable）** | **继续管理器**          | `SubagentProvider.prepareContinuable`（方法存在=能力） |

**`SubagentCapabilities`**（5 个 flag）：
```ts
interface SubagentCapabilities {
  agentOptions: boolean     // 能否覆盖模型/推理强度/token
  outputSchema: boolean     // 能否要求结构化输出
  depthLimit: boolean       // 能否限制委派深度
  toolFilter: boolean       // 能否过滤子 agent 的工具
  persona: boolean          // 能否给子 agent 人设
}
```

> **"fail loud, no silent degradation"**（逐字）：*"请求依赖提供方不具备的功能，会被**明确拒绝**（`UNSUPPORTED_CAPABILITY`），**绝不会被接受后静默忽略**。"*

---

## 五、终态结果 `SubagentResult`

> **出处**：`subagent.zh.md:288`（逐字）

```ts
interface SubagentResult {
  output: ContentBlock[]        // 子 agent 最后的 assistant 输出
  structured?: unknown          // 若请求了 outputSchema 且成功满足
  diagnostic?: string           // 非 completed 的失败详情（≤4096 字节）
  stopReason: SubagentStopReason
}
```

**`SubagentStopReason`**（可扩展联合）：`completed` / `aborted` / `error` / `max-tokens` / `refusal`。

**关键**：**非 `completed` 意味着 `output` 可能不完整**——消费方映射为 `isError`，**不把部分输出当成功**。

> **出处**：`subagent.zh.md:288`——*"非 `completed` 的 `stopReason` 意味着 `output` 可能不完整——消费方将其映射为 `isError` 的工具结果，而非将部分输出报告为成功。"*

---

## 六、动手：让主 agent 委派一个子 agent（已实测）

> **规则（AGENTS.md）**：动手环节"你动手"。**本节已实测成功**（2026-09-16）。

### 🔧 运行（headless 最简单）

```sh
cd ~/ai-work/dsh/dsh-learn
dsh --profile headless --patch "$PWD/plugins/codebuddy-llm-v2/cordis.patch.yml" \
  "用 subagent 工具委派一个子任务：让子 agent 计算 1+1 并返回结果。然后告诉我子 agent 返回了什么。"
```

**（或网页）**：
```sh
./start.sh
# 对话框输入：用 subagent 工具委派一个子任务：让子 agent 计算 1+1 并返回结果
```

### ✅ 实测结果

```
已完成委派。

我用 `subagent` 工具启动了一个子 agent，任务是「计算 1+1 并返回结果」。

**子 agent 返回的内容：`2`**

即 1+1 = 2。子 agent 按要求只返回了计算结果本身。
```

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

**这证明**：
- 主 agent **成功调用了 `subagent` 工具**（委派）
- 子 agent **独立完成**任务（返回 `2`）
- 主 agent **拿到子 agent 的结果**并汇报

### ⭐ UI 里怎么看"委派"发生了（网页）

在 **Web UI** 里，委派是**可视化**的（比 headless 更能看清）——实测观察到：

| UI 元素 | 说明 |
|---|---|
| **标题显示「… / 1个子代理」** | **明确标出"起了 1 个子代理"** |
| **「1条消息 · 1个 subagent >」**（可点击） | **展开可看子 agent 的对话**（它是独立会话） |
| **顶部「对话 / 轨迹」tab** | 切「**轨迹**」能看**完整调用链**（委派 + 子 agent 干了啥） |
| 右下 `用量 26.8K tok` | 委派的开销（**子 agent 也消耗 token**） |

> **出处**：本人实测（2026-09-16，Web UI）

**这印证**：
- **子 agent 是"独立会话"**（UI 单独标出、可展开）——回扣 05 篇（会话生命周期）
- **委派是"真起了一个 agent"**，不是"内部函数调用"

**`standard` preset（默认）已启用委派工具**——**开箱即用**。

> **注**：`~/.dsh/settings.yaml` 的 `agent-presets.default = standard`（实测）——所以默认就有 `subagent` 工具。

---

## 一页纸总结

| 概念 | 一句话 | 出处 |
|---|---|---|
| **subagent** | 主 agent 委派工作给子 agent | `subagent.zh.md:5` |
| **又是 seam** | `ctx.subagents`(Def) / 6 提供方 / tool-subagent(Consumer) | `subagent.zh.md:5` |
| **与 bash 差异** | **多提供方共存**（按名注册），bash 只一个 | `subagent.zh.md:5` |
| **6 提供方** | spawn/fork/acp/codex/claude-code/dsh-sdk | `packages/subagent/` |
| **模型工具** | `subagent`(spawn) / `subagent_fork`(fork) / `send_message` / `interrupt_agent` / `list_agents` | `standard` preset |
| **由 preset 选** | 默认 disabled，preset 决定给 agent 看哪些 | `web-app:448` |
| **两类能力** | 单次（provider）vs 可继续（continuation） | `subagent.zh.md:13` |
| **`SubagentResult`** | output / structured / diagnostic / stopReason | `subagent.zh.md:288` |
| **深度限制** | `maxDepth`（防无限递归委派） | `subagent.zh.md:38` |

## 踩坑预防

- **⚠️ `subagent` 是多提供方**：别以为像 bash 只有一种——它有 6 个，按名选。（出处：`subagent.zh.md:5`）
- **⚠️ 工具默认 disabled**：委派工具由 **preset** 启用（standard 已启用）。（出处：`web-app:448`）
- **⚠️ 非 `completed` 的输出可能不完整**：别当成功。（出处：`subagent.zh.md:288`）
- **⚠️ 未支持的能力会被明确拒**（`UNSUPPORTED_CAPABILITY`）：不静默降级。（出处：`subagent.zh.md:13`）

## 下一步

- **深水区 ③ 续**：workflow（编排脚本）/ goal（自动续跑）/ agent-team
- **深水区 ④**：mini-dsh 从零
