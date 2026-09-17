---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段三, 能力扩展, session, fork, resume, query, seam, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 05 Fork/Resume 与跨会话搜索——会话的生命周期

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**03 篇（存储）**、**04 篇（compaction）**——都涉及"会话日志 + surface"；回顾 07 篇（`session/event`）
> - 写法说明：本系列采用**完整重讲式**；本篇**讲清机制为主**（偏平台功能，非日常高频），**每段标出处**

## 这一篇在讲什么

会话（Session）**不只是"一次对话"**——它能被**恢复（Resume）**、被**分叉（Fork）**、被**跨会话搜索（Query）**。本篇讲这三件事的机制。

**一句话**：**会话日志是 append-only 的真源**（07 篇讲过），因此可以**重放**（Resume）、**从中间截断分叉**（Fork）、**被检索**（Query）。

> **关联**（回扣前几篇）：
> - **04 篇 compaction**：会话有 surface（可替换的视图）+ 日志（不可变的真源）
> - **03 篇 storage**：会话**自身**的持久化用 `persistence` se/**不是** storage（storage 管"日志之外"）

---

## 一、三个概念：Resume / Fork / Query

| 操作 | 一句话 | 用户场景 |
|---|---|---|
| **Resume（恢复）** | **继续**一个已有会话 | 关掉 dsh 明天再接着聊 |
| **Fork（分叉）** | 从某会话**某点**克隆出新会话 | "这个思路不错，但我想换个方向试" |
| **Query（搜索）** | **跨会话**检索历史 | "我上次问过 XXX，翻出来看看" |

**共同基础**：**会话日志（`SessionEvent[]`）是 append-only 真源**——所以三种操作都建立在"日志可重放"之上。

> **出处**：`session.zh.md:5`——*"`Session` 是一份由类型化 `SessionEvent` 组成的**仅追加日志**，是 agent 完整交互历史的唯一真源。LLM 消息历史从日志*派生*而来，从不单独存储；回放即从同一组事件重新派生。"*

---

## 二、Resume：恢复会话

**机制**：用**已有的会话日志 seed**（作为构造种子）→ **重放** → 继续。

> **出处**：`session.zh.md:443-451`
> - *"Seeding with an existing event log replays/forks a session."*
> - 事件带 `{ inherited: true }` 标记（来自 seed：**resume、fork 或 replay**）
> - `inheritedEventCount`：**从这个 Session 的 fork 父继承的前导事件数**

**关键区分**（`session.zh.md:465`）：会话的构造方式有三种——
- **replay**（重放）
- **fork**（分叉）
- **resume**（恢复）

前导事件**从不发布在**（新）会话上——它们是"继承来的"。

**Resume 的日志标记**：
> **出处**：`session.zh.md:173`——*"带有 reason `'initial'` 或 `'resume'` 的完整 `request/header` 快照记录每个 agent loop 实例的边界"*

即：一个 `request/header` 事件的 `reason` 是 `'initial'`（新会话）或 `'resume'`（恢复的会话）——**标记 agent loop 实例的边界**。

> **Go 类比**：像**读一个 WAL 日志从头重放**，保持状态一致——恢复 = 重放已有日志 + 继续追加。

---

## 三、Fork：分叉会话

**机制**：从父会话**截取前 N 个事件**继承过来，然后**独立发展**。

> **出处**：`session.zh.md:147`——*"A fresh fork child owns one `{ inherited: true }` marker at its exact [cut]"*
> **出处**：`session.zh.md:458`——*"Number of leading events inherited from this Session's fork parent."*

**关键点**：
- fork 子会话有 **`inheritedEventCount`**（继承了多少前导事件）
- fork 点是 **"fork-lineage cut"**（分叉血缘切点）
- 恢复会话的构造种子 = 它**完整的已存日志**（`session.zh.md:470`）

**API（Web Host）**：
> **出处**：`packages/api/session-controller/src/index.ts:335-337`
```ts
@Remote('fork')
fork(request: SessionForkRequest): Promise<SessionForkValue> {
  return this.commands.fork(request)
}
```

**用户场景**：你在 UI 里点"从此处分叉"→ 新会话继承到该点为止的历史 → 你换方向继续。

> **Go 类比**：像**从某个 commit 拉分支**——`git branch new-branch <commit>`，共享历史，之后独立提交。

---

## 四、跨会话搜索：`session-query`

**它也是一条能力 seam**（三角色**第五次**应用）：

| 角色 | 包 | 说明 |
|---|---|---|
| **Definition** | `dsh-session-query`（`ctx.sessionQuery`） | 查询词汇 + 与提供方无关的过滤器 |
| **Provider** | `dsh-session-query-sqlite` | **SQLite 全文索引**实现 |
| **Consumer** | `dsh-tool-session-query` | 把搜索**暴露为模型工具** |
| （附带） | `dsh-session-log-export` | 会话日志导出 |

> **出处**：`session-query.zh.md:5`；源码 `packages/session-query/`（4 包实读）

> **出处**：`session-query.zh.md:5`（逐字）——*"当 live 数据存在时，该语料库优先使用 live 数据。Service Definition 包负责精确读取、来源优先级、关系追踪、语义提取，以及与提供方无关的过滤器；SQLite 提供方负责具体全文索引的生命周期。"*

### 核心模型：逻辑记录

> **出处**：`session-query.zh.md`（`SessionRecord`/`SessionEventRecord`）

```ts
interface SessionRecord {
  header: SessionHeader
  live: boolean           // 当前是否存在于 ctx.sessions（内存）
  persisted: boolean      // 持久化后端是否列出该 id
}
```

**三类事件 surface**（回扣 04 篇的 surface 概念）：
```ts
type SessionEventSurface = 'current' | 'shadowed' | 'log-only'
```
- `current`：**当前**模型上下文（surface 里）
- `shadowed`：**被替换**的（compaction 遮蔽的）
- `log-only`：**只在日志里**（不进 surface）

> **出处**：`session-query.zh.md`（`SessionEventSurface`，逐字）

### Live 优先（Live-preferred）

**搜索时**：**优先用内存里的 live 数据**，缺了才读持久化层——保证搜到最新状态。

> **出处**：`session-query.zh.md`（`SessionRecord.live`/`persisted` 分离暴露各源可用性）

> **Go 类比**：像**带缓存的查询**——先查内存（live），miss 了再查库（persisted）。

---

## 五、三者如何串起来（回扣 append-only 日志）

```
会话日志（SessionEvent[]，append-only 真源）
   │
   ├── Resume  = 用已有日志 seed → 重放 → 继续        （{inherited:true} 标记）
   ├── Fork    = 截取前 N 事件继承 → 独立发展          （inheritedEventCount）
   └── Query   = 检索多个会话的日志                    （session-query seam）
         └── 分类：current / shadowed / log-only     （回扣 04 篇 surface）
```

**统一基础**：**"日志是唯一真源，一切从日志派生"**——
- 消息历史从日志**派生**（`foldSurface`）
- Resume/Fork 是"**用日志 seed**"
- Query 是"**跨日志检索**"
- compaction（04 篇）改的是 **surface**（派生视图），**日志不动**

> **出处**：`session.zh.md:5`（*"LLM 消息历史从日志派生而来，从不单独存储"*）

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **会话日志** | append-only 真源，一切派生 | WAL | `session.zh.md:5` |
| **Resume** | 用已有日志 seed → 重放 → 继续 | 重放 WAL | `session.zh.md:443,465` |
| **Fork** | 截前 N 事件继承 → 独立 | `git branch` | `session.zh.md:147,458` |
| **`{inherited:true}` 标记** | seed 来源（resume/fork/replay） | 血缘标记 | `session.zh.md:143` |
| **`request/header` reason** | `initial`/`resume` 标 agent loop 边界 | 日志边界 | `session.zh.md:173` |
| **session-query 是 seam** | Def(`ctx.sessionQuery`) / Provider(sqlite) / Consumer(tool) | 第五次三角色 | `session-query.zh.md:5` |
| **三类 surface** | `current`/`shadowed`/`log-only` | 视图分类 | `session-query.zh.md` |
| **Live 优先** | 先查内存，miss 再查库 | 带缓存查询 | `session-query.zh.md` |

## 踩坑预防

- **⚠️ Resume/Fork 用 `persistence` 存日志，不用 storage**：storage 管"日志之外"（03 篇）。（出处：`persistence.zh.md`）
- **⚠️ Fork 是"截前 N 事件"，不是整份复制**：`inheritedEventCount` 决定继承到哪。（出处：`session.zh.md:458`）
- **⚠️ 搜索有"live 优先"**：搜到的是**最新内存态**，不是只读盘。（出处：`session-query.zh.md`）
- **⚠️ 事件有三类 surface**：`shadowed`（被压缩遮蔽的）≠ 真的消失，它在日志里。（出处：`session-query.zh.md`）

## 下一步

- **阶段三 ② 完成** ✅（03 存储 / 04 压缩 / 05 Fork·Resume·查询）
- **③ 自动化与集成**：Headless 跑 CI / Python SDK / MCP 客户端 / GitHub 评审 / API Gateway / ACP
