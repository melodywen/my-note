---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段三, 能力扩展, llm, adapter, seam, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 01 LLM 适配器——接入一个新模型

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/practice/llm-adapter.zh.md`（LLM 适配器）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：完成阶段二（尤其 **08 篇 Seam 三角色**——`ctx.llm` 是又一条 seam）；回顾 06 篇（服务）、07 篇（事件/流）
> - **本篇是阶段三「能力扩展」的开篇**
> - 写法说明：本系列采用**完整重讲式**——每个概念都讲全，并标注**哪些学过、哪些是真实 dsh 的新知**

## 这一篇在讲什么

阶段二你学了 **Seam 三角色**（08 篇），例子是 bash 能力（`dsh-shell`）。这一篇把同一套认知**迁移到一个更核心的域**：**LLM（大模型）本身也是一条 seam**。

官方定位：

> **出处**：`docs/user/develop/practice/llm-adapter.zh.md`——*"本文介绍如何为 Harness 接入新的模型提供方。"* / *"LLM 适配器是一个继承 `LlmAdapter` 并实现 `stream()` 方法的类，它会将 Harness 的提供方无关请求转换为具体提供方的 API 调用，并将响应转换回 Harness 分片。"*

**本篇核心**：理解 **`LlmAdapter`（模型适配器）** 的契约——尤其是**流式分片协议（`StreamChunk`）**——并动手写一个**最小可运行的 mock 适配器**。

> ⚠️ **本篇是 08 篇的直接续集**：`dsh-llm` 是 **Service Definition**，`llm-deepseek` / `llm-pi-ai` / 你写的适配器都是 **Service Provider**，`agent-loop` 是 **Consumer**。**读本篇请始终带着 08 篇的三角色框架。**

---

## 一、先回扣 08 篇：LLM 就是一条 seam

08 篇的三角色，在 LLM 域里的对应：

| 08 篇角色 | LLM 域里的实体 | 说明 |
|---|---|---|
| **Service Definition** | `@deepseek-ai/dsh-llm` | 定义 `LlmAdapter` 抽象类 + `StreamChunk`/`GenerateOptions` 全部类型 |
| **Service Provider** | `llm-deepseek`、`llm-pi-ai`、**你要写的适配器** | 各自的 API 实现 |
| **Consumer** | `agent-loop`（`dsh-agent-loop`） | 通过 `ctx.llm` 发起模型调用 |

```
        dsh-llm (Definition)
        ▲                 ▲
   extend│                 │inject: ['llm']
        │                 │
  llm-xxx (Provider)   agent-loop (Consumer)
        ╲                 ╱
         ╳ 互不依赖
```

> **出处**：结构对照 08 篇 + 官方 `llm-adapter.zh.md`「在 cordis.yml 中使用」节（同时挂 `my-llm` 与 `agent-loop`）

**所以"接入一个新模型" = 写一个 Provider。** 这正是官方「实战参考」说的：

> **出处**：官方 `llm-adapter.zh.md`「实战参考」——*"仓库中包含以下两个完整实现：`packages/llm/llm-deepseek/`（DeepSeek API 适配器）、`packages/llm/llm-pi-ai/`（Pi AI 适配器）。对比这两个已交付的适配器，可以看到同一套 harness 契约如何在不同提供方 SDK 之上实现。"*

---

## 二、Definition：`LlmAdapter` 基类

> **出处**：源码 `packages/llm/llm/src/index.ts:203`

```ts
// packages/llm/llm/src/index.ts:203
export abstract class LlmAdapter {
  // ...6 个有默认实现的钩子（下）

  abstract stream(options: GenerateOptions): AsyncIterable<StreamChunk>   // index.ts:284
}
```

**关键认知**：`LlmAdapter` **只有一个 `abstract` 方法**（`stream`）——**实现它，适配器就能跑**。这是官方「最小实现」的底气。

其余方法都有**默认实现**（`index.ts:203-282`，按需覆写）：

| 方法 | 默认行为 | 作用 | 源码行 |
|---|---|---|---|
| `providerInfo(provider)` | `{ id: provider, name: provider }` | 提供方展示元数据 | :209 |
| `providerRetryPolicy(_provider)` | `undefined` | 该路由的重试策略 | :218 |
| `imageRequestPricing(...)` | `undefined` | 图片请求定价 | :231 |
| `listModels(_provider)` | `Promise.resolve([])` | 公布可选模型（advisory，非强制） | :242 |
| `resolveModel(provider, model, signal?)` | `{ provider, id: model, name: model }` | 解析模型身份/上下文/推理元数据 | :255 |
| `prepareCall(...)` | 绑定 `resolveModel` + `stream` | 动态适配器防"代际混用" | :272 |

> ⚠️ **与 08 篇一致的认知**：**`LlmAdapter` 不是"纯抽象类"**——它带了 6 个默认实现。所以 dsh 的 "Definition" 始终是"**抽象类 + 类型 + 共享默认实现**"，比 Go 的纯 `interface` 更重。

### 注册：`registerAdapter`

> **出处**：源码 `packages/llm/llm/src/index.ts:390`

```ts
registerAdapter(providers: string[], adapter: LlmAdapter): AdapterRegistrationHandle
```

- **第一个参数 = 该适配器负责的路由列表**（provider 名数组）
- 返回值 = **disposer**（用 `ctx.effect` 包装 → **卸载自动反注册**，回扣 05 篇"注册即 effect"）+ `handle.replace()`

> **⚠️ 一个源码级约束**（源码实证）：传入**空数组**会抛错——
> ```ts
> if (providers.length === 0) throw new LlmError('an adapter must register at least one provider', 'INVALID_ADAPTER')
> ```
> **出处**：`packages/llm/llm/src/index.ts:390` 起的 `registerAdapter` 函数体
>
> **Go 类比**：往路由表注册时"至少绑一条路由"，否则 handler 永不触发——早报错胜过静默无用。

---

## 三、`stream()` 的契约：`StreamChunk` 协议

这是本篇**最核心、最容易写错**的部分。

### `StreamChunk` 是 7 种分片的联合类型

> **出处**：源码 `packages/llm/llm/src/types.ts:424`（逐字）

```ts
export type StreamChunk =
  | { type: 'block-start'; index: number; blockType: ContentBlockType }
  | { type: 'text-delta'; index: number; text: string }
  | { type: 'reasoning-delta'; index: number; text: string }
  | { type: 'tool-call-delta'; index: number; id: ToolCallId; name?: string; argumentsDelta: string }
  | { type: 'block-end'; index: number; block: ContentBlock }
  | { type: 'usage'; usage: TokenUsage }
  | { type: 'finish'; reason: FinishReason; replayState?: ReplayEnvelope }
```

**它描述的是一次模型回复的"流式装配过程"**：

```
block-start (index=0, text)                 ← 第 0 个内容块开始（文本）
  text-delta "Hello"                        ← 增量吐字
  text-delta " world"
block-end (index=0, {text:"Hello world"})   ← 第 0 块结束，给完整内容
block-start (index=1, tool-call)            ← 第 1 个内容块开始（工具调用）
  tool-call-delta {id, name, argumentsDelta}
block-end (index=1, {type:'tool-call', ...})
usage {inputTokens, outputTokens}           ← token 统计（必须在 finish 前）
finish {kind:'stop'|'tool-calls'}           ← 收尾（必须最后）
```

> **出处**：官方 `llm-adapter.zh.md`「StreamChunk 协议」节

### 协议规则（官方明确列出）

> **出处**：官方 `llm-adapter.zh.md`「关键规则」（逐字）
> 1. 每个 `block-start` 都必须有与之对应的 `block-end`。
> 2. `index` 从 0 开始递增，用于标识内容块的顺序。
> 3. `tool-call-delta` 的 `argumentsDelta` 是原始 JSON 文本的增量，可以在一个分片中完整生成，也可以分多个分片生成。
> 4. `finish` 必须是最后一个分片。
> 5. `usage` 必须在 `finish` 之前生成。

### `FinishReason`：只有两种 kind

> **出处**：源码 `packages/llm/llm/src/types.ts:143`

```ts
export interface FinishReasonMap {
  'stop': { kind: 'stop' }               // 正常结束
  'tool-calls': { kind: 'tool-calls' }   // 请求执行工具
}
export type FinishReason = FinishReasonMap[keyof FinishReasonMap]
```

**`{ kind: 'tool-calls' }` 是让 agent-loop 去执行工具的信号**（回扣 07 篇事件系统）。

> **Go 类比**：`FinishReason` ≈ 结束状态码——`stop` 是正常 `200`，`tool-calls` 是"我需要回调你的 handler 再继续"。

### `TokenUsage` 的结构

> **出处**：源码 `packages/llm/llm/src/types.ts`（`TokenUsage`）

```ts
export interface TokenUsage {
  inputTokens: number
  outputTokens: number
  totalTokens?: number
  cacheReadTokens?: number
  cacheWriteTokens?: number
  reasoningTokens?: number
}
```

> **注**：`inputTokens` 是**未缓存输入**；缓存命中单独记在 `cacheReadTokens`/`cacheWriteTokens`。（阶段三后续讲 KV Cache 时会用到）

---

## 四、`GenerateOptions`：`stream()` 的输入

> **出处**：源码 `packages/llm/llm/src/types.ts:453`

`stream(options)` 收到的是**提供方无关、完全装配好的请求**：

| 字段 | 含义 |
|---|---|
| `provider` | 路由键（选中哪个适配器） |
| `model` | 模型 id（**适配器拥有**，无需提前注册） |
| `messages` | 对话历史（`Message[]`，`role: 'system'\|'user'\|'assistant'`） |
| `system?` | 一次性调用的系统提示词（loop 构建的请求此项为 undefined） |
| `tools?` | 工具 schema（映射到提供方的 `tools` 字段） |
| `temperature?` / `maxTokens?` | 生成参数 |
| `stop?` | 停止序列 |
| `signal?` | 中止信号（**适配器必须响应**） |
| `reasoningEffort?` | 适配器拥有的推理强度 ID |

> **出处**：源码 `packages/llm/llm/src/types.ts:453`（字段逐项核对）

**适配器职责**：把支持字段**映射到具体 API**；**不支持的字段必须抛带稳定 code 的 `LlmError`，不得静默丢弃**。

> **出处**：官方 `llm-adapter.zh.md`「GenerateOptions」节

---

## 五、`brandString` / `ToolCallId`：一个跨版本的坑（实测）

写 `tool-call-delta` 时要给 `id: ToolCallId`。官方示例用：

```ts
import { brandString } from '@deepseek-ai/dsh-brand'
import type { ToolCallId } from '@deepseek-ai/dsh-llm'
// ...
id: brandString<ToolCallId>('call-123')
```

> **出处**：官方 `llm-adapter.zh.md`「StreamChunk 协议」节（逐字）

**这个写法可用性随版本变化**（本人两次实测）：

| dsh 版本 | `brandString` | `dsh-llm` 的 id 工厂 |
|---|---|---|
| `0.0.1-rc.1`（早期，见阶段一实验07） | ❌ 纯类型包，不导出 | `CallId` |
| **`0.1.5-rc.2`（当前）** | ✅ **已导出运行时函数** | **`ToolCallId`**（不叫 `CallId` 了） |

**当前（0.1.5-rc.2）实测可用**：

```ts
import { brandString } from '@deepseek-ai/dsh-brand'
import type { ToolCallId } from '@deepseek-ai/dsh-llm'
const id = brandString<ToolCallId>('call-123')   // ✅ 实测 typeof === 'function'
```

**或等价写法**（用 `dsh-llm` 自己的工厂）：

```ts
import { ToolCallId } from '@deepseek-ai/dsh-llm'
const id = ToolCallId('call-123')                // 内部就是 brandString
```

> **出处**：源码 `packages/llm/llm/src/brand.ts:38`（`ToolCallId` 是函数）+ `index.ts:42`（`export * from './brand.ts'`）；实测 2026-09-16
>
> **📌 教训**：dsh 是 Developer Preview，**包导出会跨版本变化**。本文命令/写法标明版本；跨版本参考先实测。**（阶段一实验07 的相关记录已按此修订为"版本变更说明"）**

---

## 六、动手案例：最小 mock 适配器（已实测）

> **规则（AGENTS.md）**：动手环节"你动手"。本节**已实测通过**（2026-09-16）。

**目标**：写一个**不依赖任何外部 API 的 mock 适配器**——只按 `StreamChunk` 协议吐固定文本。**不碰真实网络，纯粹验证"协议 + 注册 + 被 web UI 列出 + 被消费"这条链路。**

**案例位置**（阶段三专属目录）：

```
dsh-learn/example/stage-03/plugins/llm-demo/
├── README.md
├── mock-adapter.patch.yml         # 挂载层：挂 mock-llm
└── mock-adapter/
    ├── mock-adapter.ts            # Provider：继承 LlmAdapter
    └── package.json
```

### 核心代码

```ts
// example/stage-03/plugins/llm-demo/mock-adapter/mock-adapter.ts
import { LlmAdapter, type GenerateOptions, type StreamChunk, type LlmModelInfo, type LlmProviderInfo } from '@deepseek-ai/dsh-llm'

class MockAdapter extends LlmAdapter {
  // ⭐ 必须实现：否则 mock 不会出现在 web UI 的 /model 目录里（见下方"关键认知"）
  listModels(provider: string): Promise<readonly LlmModelInfo[]> {
    return Promise.resolve([{ provider, id: 'mock-model-v1', name: 'Mock Model' }])
  }

  providerInfo(provider: string): LlmProviderInfo {
    return { id: provider, name: 'Mock Provider' }
  }

  async *stream(options: GenerateOptions): AsyncIterable<StreamChunk> {
    const text = `[mock] 收到 ${options.messages.length} 条消息`
    yield { type: 'block-start', index: 0, blockType: 'text' }
    yield { type: 'text-delta', index: 0, text }
    yield { type: 'block-end', index: 0, block: { type: 'text', text } }
    yield { type: 'usage', usage: { inputTokens: 1, outputTokens: 1 } }
    yield { type: 'finish', reason: { kind: 'stop' } }
  }
}

export const name = 'mock-llm'
export const inject = ['llm']
export function apply(ctx) {
  ctx.llm.registerAdapter(['mock'], new MockAdapter())
}
```

### ✅ 实测结果（web 路径，推荐）

```sh
cd ~/ai-work/dsh/dsh-learn
./start.sh --patch "$PWD/example/stage-03/plugins/llm-demo/mock-adapter.patch.yml"
```

在 Web UI 里用**模型选择控件**（或 `/model`）切到 **`Mock Provider → Mock Model`**，再发一条消息：

```
[model changed: assistant turns above this point were generated by 
 codebuddy/deepseek-v4.1-flash; the session continues with mock/mock-model-v1]

[mock] 收到 32 条消息            ← 模型回复就是 mock 吐的文本，整条 ctx.llm 链路跑通
```

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`，web profile）

**web 路径的优点**：**完全不碰 `~/.dsh/settings.yaml`**——在 UI 里显式选 `mock` 即可，全局默认模型保持不变。

### ⭐ 关键认知：`listModels()` 是"能被 UI 列出"的必要条件

**默认的 `listModels()` 返回空 `[]`**——这样的 provider **不会出现在 UI 目录里**。源码（web 的模型目录构建）：

> **出处**：`packages/api/session-controller/src/catalog.ts:20,62`（逐字）
> ```ts
> const models = await ctx.llm.listModels(provider.id)          // :23
> // ...
> groups: catalog.flatMap(...).filter(group => group.models.length > 0),  // :62 ← 空目录被过滤！
> ```

**`filter(models.length > 0)` —— 空模型的 provider 分组被直接丢弃。** 所以想让 mock 在 UI 里可选，**必须实现 `listModels()` 返回至少一个模型**。

> **Go 类比**：像注册服务时还要在"服务发现目录"里登记实例——不登记，调用方在目录里找不到你（尽管你实际上线了）。
>
> **出处**：本人实测（不实现 `listModels()` 时 UI 无 mock；实现后出现）+ 源码 `catalog.ts:62`

### 备选路径：headless（需改 settings，有副作用）

headless **没有 UI 可选**——它走 `agent-default-model` 的**当前选择**，而该值被 **`~/.dsh/settings.yaml` 覆盖**：

> **出处**：`dsh-headless/lib/index.js:130,133`——headless 通过 `ctx.get('agent-default-model').currentSelection()` 决定 provider/model（**不走 `agent-loop` 的 `agents` 数组**）。

```sh
# 编辑 ~/.dsh/settings.yaml：agent-default-model.provider → mock（优先级高于 patch）
# 然后：
DSH_PROFILE=headless ./start.sh --patch "$PWD/example/stage-03/plugins/llm-demo/mock-adapter.patch.yml" "你好"
# → [mock] 收到 N 条消息
# ⚠️ settings.yaml 是用户级文件，改完务必还原
```

### ⚠️ 踩坑记录（调试过程的真实弯路）

1. **改 `agent-loop` 的 `agents` → 无效**：headless 不走它，走 `agent-default-model.currentSelection()`。
2. **改 `agent-default-model` 的 config → 仍无效**：被 `~/.dsh/settings.yaml` 覆盖（**settings 优先级 > patch**）。
3. **不实现 `listModels()` → web UI 里看不到 mock**：被 `catalog.ts:62` 的 `filter(models.length > 0)` 过滤。
4. **正解**：实现 `listModels()` → **web UI 里直接选 mock**（零副作用）。

> [!warning] 两条通用教训
> - **配置生效优先级**：`settings.yaml` > profile patch > bundle。**patch 不总能覆盖运行期设置**——排查"配置没生效"先查 `~/.dsh/settings.yaml`。
> - **适配器要能被 UI 选到，必须实现 `listModels()`**：默认返回空会被静默过滤。
> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

### 进阶（未做）

让 mock 吐一个 `tool-calls` finish，验证**工具执行链路**（`blockType: 'tool-call'` + `finish: {kind:'tool-calls'}`）——留待后续。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| LLM 是 seam | `dsh-llm`(Def) / 适配器(Provider) / agent-loop(Consumer) | 08 篇三角色 | 官方 + 08 篇 |
| `LlmAdapter` | 抽象类，**只需实现 `stream()`** | 接口（带默认方法） | 源码 `index.ts:203` |
| `stream()` | 提供方无关请求 → 提供方 API → `StreamChunk` 流 | 适配器模式 | 官方 |
| `StreamChunk` | 7 种分片的联合（内容流式装配） | 流式响应帧 | 源码 `types.ts:424` |
| 协议规则 | block-start/end 配对；usage 在 finish 前；finish 最后 | 协议帧序 | 官方「关键规则」 |
| `FinishReason` | `stop` / `tool-calls` | 结束状态码 | 源码 `types.ts:143` |
| `registerAdapter` | 注册路由 + 返回 disposer（卸载自动反注册） | 路由注册 + defer | 源码 `index.ts:390` |
| `GenerateOptions` | 完全装配好的提供方无关请求 | DTO | 源码 `types.ts:453` |
| `brandString`/`ToolCallId` | id 工厂，**可用性跨版本变化** | 类型品牌 | `brand.ts:38` + 实测 |

## 踩坑预防

- **⚠️ `registerAdapter([])` 空数组抛 `INVALID_ADAPTER`**：至少注册一个路由。（出处：源码 `index.ts:390`）
- **⚠️ 不支持的字段要抛 `LlmError`，不能静默丢弃**。（出处：官方「GenerateOptions」节）
- **⚠️ `brandString` 可用性跨版本变化**：当前 `0.1.5-rc.2` 可用；早期版本不行。（出处：本人两次实测）
- **⚠️ 适配器要能被 web UI 选到，必须实现 `listModels()`**：默认返回空会被 `catalog.ts:62` 的 `filter(models.length > 0)` 静默过滤掉。（出处：源码 + 实测）
- **⚠️ `~/.dsh/settings.yaml` 优先级高于 patch**：headless 想切模型，得改 settings 里的 `agent-default-model`；**web 路径则无需碰 settings**（UI 里选）。（出处：本人实测）
- **⚠️ headless 的模型路由来自 `agent-default-model`（非 `agent-loop` 的 `agents`）**。（出处：`dsh-headless/lib/index.js:130,133`）

## 下一步

- **阶段三续**：② 上下文与记忆（compaction / 存储 / Fork / MCP）；③ 自动化与集成（Headless / SDK / MCP / GitHub 评审）
- **出口判据**："任选一条线做出完整实验（例：接入新模型并验证 KV Cache 命中）"——**① 模型接入层已开篇（mock 跑通）；接入真实 provider + KV Cache 是进阶**
