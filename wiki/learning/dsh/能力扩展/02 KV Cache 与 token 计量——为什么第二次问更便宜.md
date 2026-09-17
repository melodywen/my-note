---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段三, 能力扩展, llm, cache, token-meter, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 02 KV Cache 与 token 计量——为什么第二次问更便宜

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**01 篇（LLM 适配器）**——本篇是它的直接续篇；回顾 07 篇（事件/流）
> - **本篇对应阶段三出口判据**："接入一个新模型并验证 KV Cache 命中"
> - 写法说明：本系列采用**完整重讲式**；本篇由本人从源码 + 实测组织，**每段标出处**

## 这一篇在讲什么

你和 dsh 聊天，**同样一句话，聊得越久、前缀越相同时，越快越便宜**——背后的机制就是 **KV Cache（Key-Value 缓存）**：模型把**已算过的前缀**缓存下来，下次遇到**相同前缀**直接复用，不重算。

**本篇回答三个问题**：
1. **KV Cache 是什么、为什么省钱**（原理）
2. **它怎么在 dsh 里体现 + 适配器怎么接**（`TokenUsage.cacheReadTokens`）
3. **怎么观测它**（UI 的"缓存命中 X%"）

> **一句话**：KV Cache 是 LLM 推理的成本优化——**复用的前缀越多，越便宜**。

---

## 一、原理：什么是 KV Cache

**LLM 是无状态的**——每次请求都要重新处理**整个上下文**（系统提示词 + 历史消息）。上下文越长，**prefill（预填充）越贵**。

**KV Cache 的机制**：
- 模型**逐层计算**，每层的注意力需要 Key/Value 张量
- 对**相同前缀**，Key/Value 张量**不变** → 缓存下来，下次**直接复用**
- 只对**新增部分**（新消息）重新计算

**关键性质**：
- **前缀必须"相同"才命中**——**首个 token 就不同 → 全不命中**；从某处开始不同 → **只有该点之前命中**
- **顺序敏感**——这就是为什么"**KV Cache 前缀稳定性契约**"在 dsh 里重要（阶段三规划提到）

> **Go 类比**：像 HTTP 的 `ETag`/`If-None-Match`——**内容没变就不重算**。只不过这里"内容"是"token 前缀"，粒度细到**每个 token 位置**。

> ⚠️ **本篇不深究模型内部**（那是模型论文范畴），聚焦 **dsh 怎么报/怎么用这个数据**。

---

## 二、dsh 里 KV Cache 的数据表示

### 核心字段：`TokenUsage.cacheReadTokens` / `cacheWriteTokens`

> **出处**：源码 `packages/llm/llm/src/types.ts`（`TokenUsage`）

```ts
export interface TokenUsage {
  inputTokens: number          // 未缓存输入
  outputTokens: number
  totalTokens?: number
  cacheReadTokens?: number     // ← 命中 KV Cache 的量（读缓存）
  cacheWriteTokens?: number    // ← 写入 KV Cache 的量（建缓存）
  reasoningTokens?: number
}
```

**语义（关键）**：这四个计数是 **DISJOINT（不相交）的**——`inputTokens` 是**未缓存**的部分，缓存命中**单独**记在 `cacheReadTokens`：

> **出处**：源码 `packages/llm/llm/src/types.ts:158`（逐字）——*"Counts are DISJOINT: `inputTokens` is uncached input only; cached input is reported separately as `cacheReadTokens`/`cacheWriteTokens` (billed input = sum of the three)."*

**计费输入 = `inputTokens + cacheReadTokens + cacheWriteTokens`**（三者之和）。

> **Go 类比**：像数据库的 **buffer pool 命中统计**——`physical reads`（未缓存）vs `logical reads`（含缓存命中），分开计价。

### 上游 wire 格式（provider 报的原始字段）

provider 返回的 usage **不是** dsh 的格式，适配器要**翻译**。以 DeepSeek/OpenAI-compat 为例：

> **出处**：源码 `packages/llm/llm-deepseek/src/protocols/chat-completions/types.ts:163-176`

```ts
export interface WireUsage {
  prompt_tokens: number                    // ⚠️ 含 cache 命中！
  completion_tokens: number
  prompt_cache_hit_tokens?: number         // 命中
  prompt_cache_miss_tokens?: number        // 未命中
  prompt_tokens_details?: { cached_tokens?: number }  // OpenAI 兼容拼写
  completion_tokens_details?: { reasoning_tokens?: number }
}
```

> **关键**：`prompt_tokens` **包含** cache 命中（`prompt_tokens = prompt_cache_hit_tokens + prompt_cache_miss_tokens`）——**而 dsh 的 `inputTokens` 不含**，所以适配器要**减掉**。

### 适配器的翻译（`mapUsage`）

> **出处**：源码 `packages/llm/llm-deepseek/src/protocols/chat-completions/translate.ts:56-70`

```ts
export function mapUsage(usage: WireUsage): TokenUsage {
  const cacheRead = usage.prompt_tokens_details?.cached_tokens ?? usage.prompt_cache_hit_tokens
  const combined = usage.prompt_tokens + usage.completion_tokens
  return {
    inputTokens: usage.prompt_tokens - (cacheRead ?? 0),   // ← 减去 cache 命中（Disjoint 约定）
    outputTokens: usage.completion_tokens,
    ...hasExactTotal ? { totalTokens: combined } : {},
    ...cacheRead !== undefined ? { cacheReadTokens: cacheRead } : {},
    ...
  }
}
```

**翻译逻辑**：`cacheRead` 优先取 `prompt_tokens_details.cached_tokens`（OpenAI 拼写），回退 `prompt_cache_hit_tokens`（DeepSeek 拼写）——**兼容两种上游格式**。

> **出处**：源码 `translate.ts:56`；注释说明见 `translate.ts:47-51`

### ⭐ 你的 codebuddy 也做了同样的翻译

回看 01 篇的 codebuddy（`mapUsage`）——**它和官方 DeepSeek 适配器的 `mapUsage` 逻辑一致**：

```ts
// plugins/codebuddy-llm-v2/codebuddy-llm.ts:605
function mapUsage(usage) {
  const cacheRead = usage.prompt_tokens_details?.cached_tokens ?? usage.prompt_cache_hit_tokens
  ...
  ...(cacheRead !== undefined ? { cacheReadTokens: cacheRead } : {}),
}
```

**并且发请求时带 `stream_options: { include_usage: true }`**（`:454`）——**要求上游在流末尾额外发一个 usage chunk**。

> **出处**：`plugins/codebuddy-llm-v2/codebuddy-llm.ts:450,605`

---

## 三、怎么观测：UI 的"缓存命中 X%"

dsh 把这些 usage 聚合成**会话级统计**，显示在 **Web UI**。

### 位置一：底部状态栏（会话全局）

> **出处**：`packages/client/ui-chat/src/client/chat/StatsPills.tsx`

对话**底部状态栏**显示一个 **database 药丸**，含"**总 token + 缓存命中 X%**"。点它打开 token 用量对话框。

**命中率公式**：

> **出处**：`StatsPills.tsx:109-121`（逐字）
> ```ts
> export function cacheHitPercent(usage) {
>   const denominator = billedInputTokens(usage)     // = uncachedInput + cacheRead + cacheWrite
>   return formatCacheHitPercent(usage.cacheReadTokens, denominator)
> }
> ```

即 **`命中率 = cacheReadTokens / (未缓存输入 + cacheRead + cacheWrite)`**。

### 位置二：每条回复的「用量」面板

> **出处**：`packages/client/ui-chat/src/client/chat/TurnUsagePanel.tsx:49-107`

每条回复下方有「**用量 N tok**」，点开显示本轮明细：
- **`cacheHit`**：命中率（`formatCacheHitPercent(cacheReadTokens, totalTokens - outputTokens)`）
- **`cacheRead`**：读缓存 token 数
- **`cacheWrite`**：写缓存 token 数
- **`uncachedInput`**：未缓存输入
- **`output`** / **`reasoning`**

---

## 四、实测：KV Cache 真的命中了（证据）

### 环境

- CodeBuddy 适配器（`codebuddy-llm-v2`，01 篇的 V2）——**已接 cache 映射**
- 起 dsh web，正常对话

### 证据一：原始 wire usage（上游确实报 cache）

headless 跑一次，在 `mapUsage` 加探针打印**上游原始 usage**：

```
{"prompt_tokens":13250,"completion_tokens":2,
 "prompt_cache_hit_tokens":5888,          ← 命中 5888！
 "prompt_cache_miss_tokens":7362,
 "prompt_tokens_details":{"cached_tokens":5888}}
```

**解读**：这次请求 **13250 输入 token，其中 5888 命中 KV Cache**（约 **44%**）。

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

### 证据二：UI 显示命中率 82%

Web UI **底部状态栏**实测显示：

```
13 轮 18 步 · 199 tok/s      114K tok · 缓存命中 82%
```

**解读**：该会话累计 **114K token，缓存命中率 82%**——**聊得越久、前缀越稳定，命中率越高**。

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`，截图见操作记录）

### 结论：**阶段三出口判据达成**

> **出口判据**（AGENTS.md）——*"任选一条线做出完整实验（例：给 dsh 接入一个新模型并验证 KV Cache 命中）"*

**整条链路跑通**：

```
CodeBuddy 上游报 prompt_cache_hit_tokens
  → codebuddy-llm 的 mapUsage 映射成 cacheReadTokens     （02 篇第二章）
  → dsh token-meter 聚合成会话统计                        （02 篇第三章）
  → UI 底部状态栏显示「缓存命中 82%」                      （02 篇第三章）
```

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **KV Cache** | 缓存已算过的前缀，复用时直接读 | HTTP ETag / buffer pool | 原理 |
| `cacheReadTokens` | 命中 KV Cache 的量 | 缓存读 | `types.ts` |
| `cacheWriteTokens` | 写入 KV Cache 的量 | 缓存写 | `types.ts` |
| **DISJOINT 计数** | `inputTokens` 不含 cache；计费输入=三者之和 | 物理读 vs 逻辑读 | 源码 `types.ts:158` |
| wire `prompt_cache_hit_tokens` | 上游报的命中量（`prompt_tokens` 含它） | 上游原始格式 | `chat-completions/types.ts:174` |
| `mapUsage` | 上游 usage → dsh usage（**减掉 cache**） | 适配器翻译 | `translate.ts:56` |
| UI 命中率 | `cacheRead / (uncachedInput+cacheRead+cacheWrite)` | 命中率仪表 | `StatsPills.tsx:109` |
| 观测位置 | 底部状态栏 + 每条回复「用量」面板 | 仪表盘 | `ui-chat` 组件 |

## 踩坑预防

- **⚠️ `prompt_tokens` 含 cache 命中**：dsh 约定是 DISJOINT，适配器**必须减掉** `cacheRead`，否则 `inputTokens` 虚高。（出处：源码 `translate.ts:47-51`）
- **⚠️ 前缀不同则命中率骤降**：KV Cache 对**前缀顺序**敏感——改了系统提示词/历史，命中率会掉。（原理）
- **⚠️ cache 字段是 optional**：上游不报（如某些非 DeepSeek 网关）时 `cacheReadTokens` 为 `undefined`，UI 不显示命中率。（出处：`TokenUsage` 字段 optional）

## 下一步

- **阶段三 ① 完成** ✅：LLM 适配器（01）+ KV Cache 验证（02）
- **续**：② 上下文与记忆（compaction / 存储 / Fork / MCP）；③ 自动化与集成（Headless / SDK / MCP / GitHub 评审）
