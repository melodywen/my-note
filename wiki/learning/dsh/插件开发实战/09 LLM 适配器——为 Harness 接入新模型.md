---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, practice, llm, seam, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 09 LLM 适配器——为 Harness 接入新模型

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/practice/llm-adapter.zh.md`（LLM 适配器）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 前置：完成 08 篇（Seam 三角色）；回顾 06 篇（服务）与 07 篇（事件/流）
> - **本篇是 `develop/practice` 教程的第二篇，也是阶段二主路径的收官篇**
> - 写法说明：本系列采用**完整重讲式**——每个概念都讲全，并标注**哪些在阶段一学过、哪些是真实 dsh 的新知**

## 这一篇在讲什么

08 篇你学了 **Seam 三角色**（Definition / Provider / Consumer），例子是 bash 能力。这一篇把同一套认知**迁移到一个更复杂、更核心的域**：**LLM（大模型）本身也是一个 seam**。

官方定位：

> **出处**：`docs/user/develop/practice/llm-adapter.zh.md`——*"本文介绍如何为 Harness 接入新的模型提供方。"* / *"LLM 适配器是一个继承 `LlmAdapter` 并实现 `stream()` 方法的类，它会将 Harness 的提供方无关请求转换为具体提供方的 API 调用，并将响应转换回 Harness 分片。"*

**本篇的核心**：理解 **`LlmAdapter`（模型适配器）** 的契约——尤其是那条**流式分片协议（`StreamChunk`）**——并动手写一个能跑的适配器。

> ⚠️ **本篇是 08 篇的直接续集**：`dsh-llm` 是 **Service Definition**，`llm-deepseek` / `llm-pi-ai` / 你写的适配器都是 **Service Provider**，`agent-loop` 是 **Consumer**。**读本篇时请始终带着 08 篇的三角色框架。**

---

## 一、先回扣 08 篇：LLM 就是一条 seam

08 篇的三角色，在 LLM 域里的对应：

| 08 篇角色 | LLM 域里的实体 | 说明 |
|---|---|---|
| **Service Definition** | `@deepseek-ai/dsh-llm` | 定义 `LlmAdapter` 抽象类 + `StreamChunk`/`GenerateOptions` 等全部类型 |
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

> **出处**：结构对照 08 篇 + 官方 `llm-adapter.zh.md`「在 cordis.yml 中使用」节（profile 层同时挂 `my-llm` 与 `agent-loop`）

**所以"接入一个新模型" = 写一个 Provider**。这正是官方"实战参考"里说的：

> **出处**：官方 `llm-adapter.zh.md`「实战参考」——*"仓库中包含以下两个完整实现：`packages/llm/llm-deepseek/`（DeepSeek API 适配器）、`packages/llm/llm-pi-ai/`（Pi AI 适配器）。对比这两个已交付的适配器，可以看到同一套 harness 契约如何在不同提供方 SDK 之上实现。"*

---

## 二、Definition：`LlmAdapter` 基类

> **出处**：源码 `packages/llm/llm/src/index.ts:203`

```ts
// packages/llm/llm/src/index.ts:203
export abstract class LlmAdapter {
  // ...（下面 6 个都是有默认实现的钩子，可选择覆写）

  abstract stream(options: GenerateOptions): AsyncIterable<StreamChunk>   // index.ts:284
}
```

**关键认知**：`LlmAdapter` **只有一个 `abstract` 方法**（`stream`）——**实现它，适配器就能跑**。这是官方"最小实现"的底气。

其余方法都有**默认实现**（`index.ts:203-282`，按需覆写）：

| 方法 | 默认行为 | 作用 | 源码行 |
|---|---|---|---|
| `providerInfo(provider)` | `{ id: provider, name: provider }` | 提供方展示元数据 | :209 |
| `providerRetryPolicy(_provider)` | `undefined` | 该路由的重试策略 | :218 |
| `imageRequestPricing(...)` | `undefined` | 图片请求定价 | :231 |
| `listModels(_provider)` | `Promise.resolve([])` | 公布可选模型（advisory，非强制） | :242 |
| `resolveModel(provider, model, signal?)` | `{ provider, id: model, name: model }` | 解析模型身份/上下文/推理元数据 | :255 |
| `prepareCall(...)` | 绑定 `resolveModel` + `stream` | 动态适配器防"代际混用" | :272 |

> ⚠️ **与 08 篇一致的修正**：**`LlmAdapter` 不是"纯抽象类"**——它带了 6 个默认实现。所以"Definition"在 dsh 里始终是"抽象类 + 类型 + 共享默认实现"，比 Go 的纯 `interface` 更重。（回扣 08 篇第二节的修正）

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
> **出处**：源码 `packages/llm/llm/src/index.ts:390` 起的 `registerAdapter` 函数体
>
> **Go 类比**：往路由表注册时"至少要绑一条路由"，否则这个 handler 根本不会被触发——早报错胜过静默无用。

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
block-start (index=0, text)          ← 第 0 个内容块开始（文本）
  text-delta "Hello"                 ← 增量吐字
  text-delta " world"
block-end (index=0, {text:"Hello world"})  ← 第 0 块结束，给完整内容
block-start (index=1, tool-call)     ← 第 1 个内容块开始（工具调用）
  tool-call-delta {id, name, argumentsDelta}
block-end (index=1, {type:'tool-call', ...})
usage {inputTokens, outputTokens}    ← token 统计（必须在 finish 前）
finish {kind:'stop'|'tool-calls'}    ← 收尾（必须最后）
```

> **出处**：官方 `llm-adapter.zh.md`「StreamChunk 协议」节

### 6 条协议规则（官方明确列出）

> **出处**：官方 `llm-adapter.zh.md`「关键规则」（逐字）
> 1. 每个 `block-start` 都必须有与之对应的 `block-end`。
> 2. `index` 从 0 开始递增，用于标识内容块的顺序。
> 3. `tool-call-delta` 的 `argumentsDelta` 是原始 JSON 文本的增量，可以在一个分片中完整生成，也可以分多个分片生成。
> 4. `finish` 必须是最后一个分片。
> 5. `usage` 必须在 `finish` 之前生成。

（第 6 条见下：`FinishReason` 的两种 kind）

### `FinishReason`：只有两种 kind

> **出处**：源码 `packages/llm/llm/src/types.ts:143`

```ts
export interface FinishReasonMap {
  'stop': { kind: 'stop' }               // 正常结束
  'tool-calls': { kind: 'tool-calls' }   // 请求执行工具
}
export type FinishReason = FinishReasonMap[keyof FinishReasonMap]
```

**`{ kind: 'tool-calls' }` 是让 agent-loop 去执行工具的信号**——回扣 07 篇讲的事件系统，模型说"我要调工具"，loop 收到后走工具执行流水线。

> **Go 类比**：`FinishReason` ≈ gRPC/HTTP 的结束状态码——`stop` 是正常 `200`，`tool-calls` 是"我需要回调你的 handler 再继续"。

### ⚠️ 官方示例的一个坑（在 npm 发行版上实测有出入）

官方「StreamChunk 协议」示例写的是：

```ts
import { brandString } from '@deepseek-ai/dsh-brand'
import type { StreamChunk, ToolCallId } from '@deepseek-ai/dsh-llm'
// ...
yield { type: 'tool-call-delta', index: 1, id: brandString<ToolCallId>('call-123'), ... }
```

> **出处**：官方 `llm-adapter.zh.md`「StreamChunk 协议」节（逐字）

**但源码里正确的是**：`ToolCallId` 由 **`dsh-llm` 自己导出**（`packages/llm/llm/src/index.ts:42` → `export * from './brand.ts'`），且它是**一个函数**（`ToolCallId(id: string): ToolCallId`，见 `brand.ts`），不是"类型 + 泛型 brandString"。

**⚠️ 待验证**：npm 安装版的 `@deepseek-ai/dsh-brand` 是否导出 `brandString`？据 05–07 篇实测经验（**npm 版 `dsh-brand` 是纯类型包**），**官方示例的这段在发行版上大概率编译不过**。正确写法应为：

```ts
import { ToolCallId } from '@deepseek-ai/dsh-llm'   // ← 从 dsh-llm 导入
// ...
id: ToolCallId('call-123'),
```

> **本条标 `⚠️ 待验证`**——动手阶段会实测确认，并回填准确写法。
> **出处**：源码 `packages/llm/llm/src/brand.ts`（`ToolCallId` 是函数）+ `index.ts:42`（re-export）；官方文档说法的差异由本人核对源码发现（2026-09-16）

---

## 四、`GenerateOptions`：`stream()` 的输入

> **出处**：源码 `packages/llm/llm/src/types.ts:453`

`stream(options)` 收到的是**提供方无关的、完全装配好的请求**：

| 字段 | 含义 |
|---|---|
| `provider` | 路由键（选中哪个适配器） |
| `model` | 模型 id（**适配器拥有**，无需提前注册） |
| `messages` | 对话历史（`Message[]`，含 system 角色） |
| `system?` | 一次性调用的系统提示词（loop 构建的请求此项为 undefined） |
| `tools?` | 工具 schema（`ToolSchema[]`，映射到提供方的 `tools` 字段） |
| `temperature?` / `maxTokens?` | 生成参数 |
| `stop?` | 停止序列 |
| `signal?` | 中止信号（**适配器必须响应**） |
| `reasoningEffort?` | 适配器拥有的推理强度 ID |
| `purpose?` | 辅助调用分类（`'compaction' \| 'session-title'`） |

> **出处**：源码 `packages/llm/llm/src/types.ts:453`（字段逐项核对）

**适配器的职责**：把 `GenerateOptions` 的**支持字段映射到具体 API**；**不支持的字段必须抛带稳定 code 的 `LlmError`，不得静默丢弃**。

> **出处**：官方 `llm-adapter.zh.md`「GenerateOptions」节——*"适配器必须将支持的字段映射到具体 API；如果无法支持某个字段，应抛出带稳定 code 的 `LlmError`，不得静默丢弃。"*

---

## 五、现成 Provider 的写法（读 `llm-pi-ai`）

> **出处**：源码 `packages/llm/llm-pi-ai/src/{adapter.ts, stream.ts}`

现成适配器的骨架：

```ts
// packages/llm/llm-pi-ai/src/adapter.ts:219
export class PiAiAdapter extends LlmAdapter {
  override listModels(provider): Promise<readonly LlmModelInfo[]>      // :276
  override resolveModel(...)                                           // :289
  stream(options: GenerateOptions): AsyncIterable<StreamChunk> {       // :326
    return this.streamWithSnapshot(options, this.current())
  }
}
```

**`stream()` 的真实转换模式**（`stream.ts:142`，`toStreamChunks()`）：

```ts
export async function* toStreamChunks(...) {
  // 遍历上游事件流，逐事件 yield 成 harness 分片
  yield { type: 'block-start', index: event.contentIndex, blockType: 'text' }
  yield { type: 'text-delta', index: event.contentIndex, text: event.delta }
  yield { type: 'block-end', index: event.contentIndex, block: { type: 'text', text: event.content } }
  // ...tool-call / reasoning 同理...
  yield { type: 'usage', usage: mapUsage(...) }       // mapUsage: stream.ts:24
  yield { type: 'finish', reason: mapStopReason(...) } // mapStopReason: stream.ts:80
}
```

**这就是 `stream()` 的标准套路**：**上游 SDK 的流式事件 → 映射 → harness `StreamChunk` 序列**。你写自己的适配器时，就是写这一层映射。

> **出处**：源码 `packages/llm/llm-pi-ai/src/stream.ts:142`（`toStreamChunks`）

---

## 六、错误处理（官方强调）

> **出处**：官方 `llm-adapter.zh.md`「错误处理」节（逐字）

- 用 **`LlmError` + 稳定 code** 抛传输/协议故障——*"agent loop 会保留该错误及其 code，用于诊断和策略处理。不要依赖普通 `Error` 被自动转换。"*
- 每个 HTTP 请求**必须合并 `attributionHeaders()`**，并传递 `options.signal`
- 不支持的字段：抛 `LlmError`，不静默丢弃

```ts
import { LlmAdapter, LlmError, attributionHeaders, type GenerateOptions, type StreamChunk } from '@deepseek-ai/dsh-llm'

class HttpAdapter extends LlmAdapter {
  async *stream(options: GenerateOptions): AsyncIterable<StreamChunk> {
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...attributionHeaders() },
      body: JSON.stringify({ model: options.model, messages: options.messages }),
      ...options.signal ? { signal: options.signal } : {},
    })
    if (!response.ok) {
      throw new LlmError(`Provider API error: ${response.status}`, 'PROVIDER_HTTP_ERROR')
    }
    yield { type: 'finish', reason: { kind: 'stop' } }
  }
}
```

> **出处**：官方 `llm-adapter.zh.md`「错误处理」节（逐字，含代码）

---

## 七、动手案例：写一个最小可运行的适配器（预告）

> **规则（AGENTS.md）**：动手环节"你动手"。本节待**动手阶段**补齐并实测。

**目标**：亲手写一个**不依赖真实外部 API 的 mock 适配器**，把 `StreamChunk` 协议**真跑通**——因为它只吐固定文本，所以能纯粹验证"协议 + 注册 + 被 agent-loop 消费"这条链路。

**计划**（`dsh-learn/example/plugins/llm-demo/`）：

```
llm-demo/
├── mock-adapter/
│   └── mock-adapter.ts   ← Provider：继承 LlmAdapter，stream() 吐固定分片
└── mock-adapter.patch.yml ← 挂载层：注册 provider 'mock' + 配 agent-loop 用它
```

**验证步骤**：

1. 写 `MockAdapter extends LlmAdapter`，`stream()` 按协议吐：`block-start(text)` → `text-delta` → `block-end` → `usage` → `finish(stop)`
2. 用 `ctx.llm.registerAdapter(['mock'], new MockAdapter())` 注册
3. profile 里让 `agent-loop` 用 `provider: mock`
4. 起 dsh（headless）→ 发一句 → 观察**模型回复就是 mock 的固定文本**（证明整条 `ctx.llm` 链路通）

**同时验证两个悬而未决的问题**：
- ⚠️ `ToolCallId` 到底该从哪导入、怎么写（本报告第三章末尾的坑）
- ⚠️ 官方示例的 `brandString` 是否真的不可用

> ⚠️ **当前状态**：上述案例**尚未动手**，本节的命令与输出**均未实测**。按 AGENTS.md「写入笔记的命令必须是实际运行过的」，标记 **⚠️ 待实测**，动手后回填。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| LLM 是 seam | `dsh-llm`(Def) / 适配器(Provider) / agent-loop(Consumer) | 08 篇三角色 | 官方 + 08 篇 |
| `LlmAdapter` | 抽象类，**只需实现 `stream()`** | 接口（带默认方法） | 源码 `index.ts:203` |
| `stream()` | 提供方无关请求 → 提供方 API → `StreamChunk` 流 | 适配器模式 | 官方 |
| `StreamChunk` | 7 种分片的联合类型（内容流式装配） | 流式响应帧 | 源码 `types.ts:424` |
| 协议规则 | block-start/end 配对；usage 在 finish 前；finish 最后 | 协议帧序 | 官方「关键规则」 |
| `FinishReason` | `stop` / `tool-calls` | 结束状态码 | 源码 `types.ts:143` |
| `registerAdapter` | 注册路由 + 返回 disposer（卸载自动反注册） | 路由注册 + defer | 源码 `index.ts:390` |
| `GenerateOptions` | 完全装配好的提供方无关请求 | DTO | 源码 `types.ts:453` |
| 错误处理 | `LlmError` + 稳定 code + `attributionHeaders()` + `signal` | 带码 error + trace header | 官方「错误处理」 |
| **仅需实现 stream** | 其余 6 个方法都有默认实现 | 接口默认方法 | 源码 `index.ts:203-282` |

## 踩坑预防（写作阶段已知）

- **⚠️ `ToolCallId` 的导入/构造方式**：正解是 `import { ToolCallId } from '@deepseek-ai/dsh-llm'` 然后 `ToolCallId('call-123')`（它是个函数）；**官方示例的 `brandString<ToolCallId>` 写法在 npm 发行版上待验证**。（出处：源码 `brand.ts` vs 官方文档，本人核对）
- **⚠️ `registerAdapter([])` 空数组会抛 `INVALID_ADAPTER`**：至少注册一个路由。（出处：源码 `index.ts:390`）
- **⚠️ 不支持的字段要抛 `LlmError`，不能静默丢弃**：否则 agent-loop 拿不到错误信号。（出处：官方「GenerateOptions」节）

## 下一步

- **阶段二收官** ✅（basic → framework → practice 三块全过）
- **动手补全**：本篇第七节待实际写 mock 适配器 + 实测后回填（同时消掉两个 ⚠️）
- **进入阶段三**：模型接入层的更深内容——流式响应管线（llm-streaming 子系统）、模型路由、KV Cache 前缀稳定性契约等；或横向技能（提示词工程 / 可观测性）
