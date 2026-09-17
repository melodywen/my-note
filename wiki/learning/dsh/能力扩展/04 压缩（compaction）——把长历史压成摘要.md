---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段三, 能力扩展, compaction, seam, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 04 压缩（compaction）——把长历史压成摘要

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**08 篇（Seam 三角色）**——compaction 是三角色第四次应用；回顾 03 篇（存储，另一条 seam）
> - 写法说明：本系列采用**完整重讲式**；本篇以**讲透机制 + 观测指南**为主（真实触发需长会话），**每段标出处**

## 这一篇在讲什么

**上下文窗口是有限的**——聊得越久，历史越长，**迟早放不下**。**compaction（压缩）**就是：**把旧的历史压成一段摘要**，腾出空间继续聊。

官方定位：

> **出处**：`docs/subsystems/compaction.zh.md:5`（逐字）——*"压缩 seam 是一个能力 seam…分为 Service Definition（`dsh-compaction`，`ctx.compaction`）、Service Provider（例如 `dsh-compaction-basic` 后端）和面向用户的 Consumer（`dsh-command-compact`）。压缩是**一项可选能力**，不属于 agent loop 主干。"*

**本篇核心**：理解 compaction 的**机制**（选范围 → 摘要 → 替换），以及它和 **surface（表层）** 的关系。

> **Go 类比**：像**日志的 compaction**（LSM-tree 合并 SSTable）、或**视频时间轴压缩**——把"详细过程"压成"摘要"。

---

## 一、为什么需要压缩（问题背景）

**三个前提概念**（回扣 07 篇）：

| 概念 | 含义 |
|---|---|
| **Session 日志**（`SessionEvent`） | 会话的**真源**——只追加，永不删 |
| **Surface（表层）** | **给模型看的那部分**——从日志投影出来的 |
| **Context window** | 模型的输入上限（放不下就报错） |

**问题**：聊久了，surface 越来越大 → 超过 context window → **请求失败**。

**compaction 的解法**：**选一段旧的 surface，用一条"摘要"替换它**——日志不删（真源保留），但**给模型看的 surface 变短了**。

---

## 二、compaction 是能力 seam——三角色第四次应用

| 角色 | 包 | 说明 | 出处 |
|---|---|---|---|
| **Definition** | `dsh-compaction`（`ctx.compaction`） | 抽象 `CompactionEngine` | `compaction/src/index.ts:112` |
| **Provider** | `dsh-compaction-basic` | 基础实现（阈值/保留/摘要调用） | `packages/compaction/compaction-basic/` |
| **Consumer** | `dsh-command-compact` | 面向人的 `/compact` 命令 | `command-compact/src/index.ts` |
| （可选部件） | `...-tool-result-pruner` | 工具结果剪枝（长工具输出先精简） | `packages/compaction/` |
| （可选部件） | `...-image-offload` | 图片省略 | 同上 |

> **出处**：`compaction.zh.md:5`；源码 `packages/compaction/`（5 个包实读）

**Definition**（抽象 seam）：

> **出处**：源码 `packages/compaction/compaction/src/index.ts:112`

```ts
export abstract class CompactionEngine extends Service {   // index.ts:112
  abstract compactIfNeeded(agent, trigger, signal): Promise<CompactionResult | null>  // 自动
  abstract compactNow(agent, signal, sourceCommandId?): Promise<CompactionResult | null>  // 手动
  abstract compactRegion(start, end, agent, signal?): Promise<CompactionResult>  // 指定范围
}
```

**Consumer**（`/compact` 命令）：

> **出处**：源码 `packages/compaction/command-compact/src/index.ts:11-12,83-96`

```ts
export const name = 'command-compact'
export const inject = ['commands', 'compaction']   // ← 依赖 commands + compaction

// 注册命令：
ctx.commands.register({
  definitionId: CommandDefinitionId('@deepseek-ai/dsh-command-compact'),
  name: 'compact',                                  // → 用户输入 /compact
  description: 'Compact older conversation history',
  handler,
})
```

---

## 三、核心机制：三个 `compaction/*` 事件 + 锁

compaction 用**三个会话事件**记录一次压缩（**只写日志，不进 surface**）：

> **出处**：`compaction.zh.md:11-16`（事件表，逐字）

| 事件 | 作用 |
|---|---|
| `compaction/start` | **获取锁**（`turn` 数字=自动轮，`null`=手动） |
| `compaction/summary` | 记录**摘要 + 被遮蔽范围**（`shadowedRange`/`shadowedSeqs`/token 数/模型调用） |
| `compaction/end` | **释放锁**（带 `error?` 记录失败） |

**锁括住整个操作**：start → 摘要生成 → summary + surface 替换 → end。

> **出处**：`compaction.zh.md:19`（逐字）——*"最后释放锁意味着操作中途崩溃会表现为**可检测的遗留锁**（有 `compaction/start` 而无匹配的 `compaction/end`），而非一个虚假声称压缩已完成的 `compaction/end`。"*

**崩溃恢复**：
- 有 `start` 无 `end` → **检测到遗留锁**（可以识别、处理）
- 这就是**"append-only 日志 + 显式锁"**的容错设计

> **Go 类比**：像事务的 **WAL + 显式 begin/commit**——崩溃后能看出"这个事务没提交完"。

---

## 四、关键概念：`shadowedRange`（被遮蔽的范围）

**这是本篇最反直觉的点**。

> **出处**：`compaction.zh.md:62`（`CompactionResult`，逐字注释）

```ts
shadowedRange: {
  start: SessionSeq
  end: SessionSeq
}
```

**注释原文**：
> *"A surface-**POSITION** span, not a numeric seq interval — after a prior replace lands a fresh high-seq summary node at an older range's position, `start` can be **GREATER** than `end`。"*

**翻译**：
- `shadowedRange` 是 **"表层位置跨度"**，**不是数值区间**
- 因为替换后，**摘要节点会拿到一个"新的高 seq"，却落在"旧范围的位置"上**
- **所以 `start` 可能大于 `end`**！

**"shadowedSeqs"** 才是权威的"被遮蔽节点集合"（按表层顺序）。

> **Go 类比**：像**链表节点被替换**——新节点的"内存地址"（seq）比旧的大，但它**占了旧节点的位置**（表层顺序）。**位置**和**编号**是两回事。

**为什么这么设计**：日志是 append-only（seq 只增不减），但 surface 是"逻辑视图"（可以被替换/重排）——两者用**不同坐标系**。

---

## 五、什么时候触发

### 自动触发（`pre-step` 压力）

> **出处**：`compaction.zh.md:101`（逐字）——*"压力压缩在 `agent/pre-step` waterfall（瀑布式事件）中运行，先于请求推导。"*

- 每步请求前检查 **token 压力**（超 `thresholdRatio`）
- 或 **provider 确认 context 溢出**（`context-overflow`）
- 触发后：**先剪枝工具结果**（`toolResultPruner`）→ 重测 → 选范围 → 摘要 → 替换

> **出处**：源码 `packages/compaction/compaction-basic/src/index.ts:150`（`compactIfNeeded(agent, 'pressure', signal)`）

### 手动触发（`/compact`）

> **出处**：`command-compact/src/index.ts:2`——*"Human-facing `/compact` command"*

- 用户输入 **`/compact`**（无参数）
- 调 `ctx.compaction.compactNow(...)`
- **即使没到压力阈值也能压**（"主动瘦身"）

### 手动失败的用户可见文案

> **出处**：`command-compact/src/index.ts:26-53`（逐字）

| code | 用户看到 |
|---|---|
| `busy` | *"Compaction is unavailable because this process has an active compaction, or the agent is not idle."* |
| `cancelled` | *"Compaction cancelled."* |
| `changed` | *"The history selected for compaction changed before it could be replaced..."* |
| `summary` | *"Compaction could not produce a useful summary..."* |
| `commit` | *"Compaction did not finish cleanly..."* |
| `persistence` | *"Compaction finished, but the session could not be saved."* |

---

## 六、动手：观测一次压缩（指南）

> **规则（AGENTS.md）**：动手环节"你动手"。**compaction 的真实触发需长会话**，本节给**观测指南**。

### 前置：确认组件已挂（实测）

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

`dsh-base` bundle **默认已挂** compaction 全套：

```
$ dsh --profile web --patch <codebuddy> --dump-config | grep compaction
- id: compaction-basic            ← Provider（基础实现）
- id: command-compact             ← Consumer（/compact 命令）
  name: '@deepseek-ai/dsh-compaction-tool-result-pruner'   ← 工具结果剪枝
```

**所以 `/compact` 开箱可用。**

### 观测步骤（需 Web UI 操作）

```sh
cd ~/ai-work/dsh/dsh-learn
./start.sh
```

1. **聊几轮**（建立一定历史）——越多越容易看出效果
2. **输入 `/compact`** → 触发手动压缩
3. **观察**：
   - 对话里是否出现"摘要替换"（旧的多轮被一段摘要取代）
   - 会话日志里是否出现 `compaction/start` → `compaction/summary` → `compaction/end`
   - 底部 token 统计是否**变小**（腾出了空间）
4. **查日志**：压缩事件落在会话 JSONL 里（`~/.dsh/sessions/`）

> ⚠️ **当前状态**：组件已挂（实测 ✅）；**真实触发压缩需足够历史**（见下）。

### ✅ 实测发现：会话太短时 `/compact` **不产生压缩**

在一个**短会话**（仅 3 条 user 消息）里执行 `/compact`，**没有产生任何 `compaction/*` 事件**：

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）——解压会话日志 `~/.dsh/sessions/*/session.v3.jsonl.zstd` 后搜 `compaction/`，**0 命中**；事件类型里只有正常的 `user/message`/`step/start`/`assistant/message` 等。

**原因**（源码印证）：`compactNow` 在没有**有效可压范围**时**返回 `null` 且不写入任何事件**：

> **出处**：`compaction.zh.md`（`compactNow` 签名注释）——*"select a useful range without writing on a no-op... Return `null` when no safe useful range exists."*

**这意味着**：**会话历史不够长时，`/compact` 是"空操作"**——不会报错，也不会写事件。要有**足够的旧历史**才谈得上压缩。

> **Go 类比**：像给一个只有 3 行的日志做 compaction——**没东西可压**，直接跳过。

> **📌 要真正触发压缩**：先在会话里积累**大量历史**（聊很多轮 / 贴长内容），**再** `/compact`——才有"可压范围"产生 `compaction/start`→`summary`→`end`。
> **待补充**：本笔记**尚未观测到一次真实压缩**（需长会话）；机制部分已由源码讲透。

### 为什么不在 headless 里做

- headless 是"一问一答即退出"——**建立不了多轮历史**
- 自动触发需**长会话**或**精细调阈值**（`thresholdRatio` + `contextWindow`）
- **手动 `/compact` 最直接**，但要 Web UI 交互

> **权衡结论**：compaction 的**核心价值是机制理解**（已讲透），真实触发成本高——**用观测指南**比硬造假 Provider 更实在。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **compaction** | 把旧 surface 压成摘要，腾上下文 | 日志 compaction / 时间轴压缩 | 官方 |
| **三角色** | Def(`ctx.compaction`) / Provider(`-basic`) / Consumer(`/compact`) | 08 篇框架 | `compaction.zh.md:5` |
| **`CompactionEngine`** | 抽象 seam：`compactIfNeeded`/`compactNow`/`compactRegion` | 接口 | `index.ts:112` |
| **三个事件** | `compaction/start`→`summary`→`end` | WAL begin/commit | `compaction.zh.md:11` |
| **锁** | start 与 end 配对；遗留锁可检测 | 显式事务锁 | `compaction.zh.md:19` |
| **`shadowedRange`** | 表层**位置**跨度（start 可能 > end） | 链表节点替换 | `compaction.zh.md:62` |
| **触发** | 自动（`pre-step` 压力）/ 手动（`/compact`） | — | `compaction.zh.md:101` |
| **日志 vs surface** | 日志永不删；surface 可替换 | 真源 vs 视图 | 概念 |

## 踩坑预防

- **⚠️ `shadowedRange` 的 start 可能大于 end**：它是"位置跨度"不是"数值区间"，别当数值比大小。（出处：`compaction.zh.md:62`）
- **⚠️ compaction 只改 surface，不改日志**：日志是 append-only 真源，永远保留。（出处：概念 + `compaction.zh.md`）
- **⚠️ 遗留锁（有 start 无 end）= 崩溃证据**：不是 bug，是容错设计。（出处：`compaction.zh.md:19`）
- **⚠️ 自动触发依赖 token 压力**：不是"聊几句就压"，要超阈值。（出处：`compaction-basic` 配置）

## 下一步

- **阶段三 ② 续**：Fork/Resume（分叉/恢复）、跨会话搜索（`session-query`）
- **③ 自动化与集成**：Headless / SDK / MCP / GitHub 评审
