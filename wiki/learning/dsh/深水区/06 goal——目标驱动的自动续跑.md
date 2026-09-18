---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, goal, 续跑, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 06 goal——目标驱动的自动续跑

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**01 篇（agent-loop / `agent/pre-step`）**、**04 篇（subagent）**
> - 写法说明：本系列采用**完整重讲式**；以**读源码 + 讲机制**为主

> [!abstract] 本章是什么 / 该记住什么
> **回答的问题**："**goal** 是什么？为什么叫'自动续跑'？"
> **答案**：**给会话设一个"目标"**——agent **一轮轮自己往下干**（`goal-round-driver` 自动续跑），直到目标 `complete`（或 paused/blocked）。
> **读完该记住 4 点**：
> 1. **goal = 同会话的"持久目标"**（`active`/`paused`/`blocked`/`complete`）
> 2. **"续跑" = `goal-round-driver` 自动起"目标轮次"**（agent 干完一轮，自动再来一轮，直到达标的）
> 3. **3 个工具**：`get_goal` / `create_goal` / `update_goal`（+ `/goal` 命令）
> 4. **它是"长任务的驱动器"**——让 agent 不用人盯着，自己推进

## 这一篇在讲什么

**前面都是"一问一答/一次委派"**。**但"给 agent 一个长期目标，让它自己一轮轮干到完成"**呢？——**那就是 `goal`**。

> **出处**：`goal-round-driver/src/index.ts:1`（逐字）——*"**Same-session goal-round driver** over public agent, session, and goal services."*

**一句话**：**goal = "给会话设个目标，agent 自动一轮轮续跑，直到达标"**。

> **Go 类比**：像**一个"while 未达标"的循环**——**每轮干一批，检查目标，没完就再来一轮**——**goal 就是把这个循环做成持久、可暂停/恢复的**。

---

## 一、`GoalPhase`（目标的 4 个持久阶段）

> **出处**：`goal.zh.md:7`（逐字）
```ts
type GoalPhase =
  | 'active'      // 进行中（可续跑）
  | 'paused'      // 暂停
  | 'blocked'     // 阻塞（有问题）
  | 'complete'    // 完成
```

**"blocked"** 是唯一表示"**因问题而停止**"的状态：

> **出处**：`goal.zh.md:32`（逐字）——*"阻塞是唯一表示「因问题而停止」的持久状态。由策略负责的阻塞原因会携带一个用于路由、稳定且采用 lower-kebab-case 的代码，以及一段供人和模型阅读的自由文本说明。"*
```ts
interface GoalBlockReason {
  code: string      // 稳定分类（lower-kebab-case）
  message: string   // 人/模型可读的说明
}
```

**⚠️ 关键区分**（`goal.zh.md:7`）：
- **`GoalPhase`** = **持久状态**（目标发生了什么）
- **`activation`** = **进程本地**（续跑消费方"能否开始下一轮"）——**从不持久**

---

## 二、目标的数据（`GoalSnapshot` / `GoalView`）

> **出处**：`goal.zh.md`（逐字）
```ts
interface GoalSnapshot extends GoalRef {
  objective: string          // 目标（人类要求的完成目标）
  phase: GoalPhase           // 持久阶段
  blockedReason?: GoalBlockReason  // 仅 phase=blocked 时
  maxGoalRounds: number      // 总轮次上限
}

interface GoalView extends GoalSnapshot {
  roundsStarted: number      // 已开始的最高轮次
  createdAt / updatedAt      // 时间戳
  activation: GoalActivation // 进程本地（续跑资格），不持久
}
```

- **`GoalRef`** = `{ id, revision }`（compare-and-set——**改要带当前 revision**）
- **`maxGoalRounds`** = **轮次上限**（防无限续跑）

---

## 三、⭐ "自动续跑"怎么实现（`goal-round-driver`）

> **出处**：`packages/goal/goal-round-driver/`（逐字）

```ts
export const name = 'goal-round-driver'
export const inject = ['agents', 'goals', 'sessions']   // 依赖 agent/goal/session
// "Same-session goal-round driver over public agent, session, and goal services."
```

**机制**：
- **`goal-round-driver`** 监听（**很可能用 `agent/pre-step`**——回扣 01 篇）→ **每轮结束时，若目标还没 `complete` → 自动注入"下一轮"的提示**（`renderGoalRoundPrompt`）→ **agent 接着干**
- **`RoundIdentity`**：*"Identity reserved before a goal continuation enters the agent inbox"*——每轮的身份

**所以"续跑"** = **agent 干完一轮 → driver 判断目标未完成 → 自动起下一轮**——**不用人盯着**。

> **Go 类比**：像 **`for goal.NotDone() { agent.RunRound() }`**——**driver 就是这个 `for`**。

---

## 四、3 个工具 + 1 个命令

> **出处**：`packages/goal/tool-goal/src/index.ts`（`name:`，逐字）

| 工具 | 作用 |
|---|---|
| **`get_goal`** | 读当前目标 |
| **`create_goal`** | **建目标**（`objective` + `maxGoalRounds`） |
| **`update_goal`** | 更新目标（改 objective / 阶段） |

**命令**：**`/goal`**（`command-goal/src/index.ts:193`）——面向人的入口。

---

## 五、`ctx.goals`（服务 API）

> **出处**：`goal.zh.md:176`（逐字）

| 方法 | 作用 |
|---|---|
| `get(agent)` | 读当前目标 |
| `create(agent, request)` | 建并"arm"目标（**设目标即开始续跑**） |
| `edit(agent, ref, request)` | 改 objective/轮次上限（不改阶段） |
| `resume` / `clear` / `disarm` | 恢复/清除/解除"续跑资格" |

> **关键**（`goal.zh.md`）——*"`create` 会**建并 arm**（武装）目标"*——**arm = 允许续跑**；`disarm` = 停止续跑（但保留持久目标）。

---

## 六、动手（指南）

> **规则（AGENTS.md）**：动手环节"你动手"。本节是**指南**（未实测）。

**思路**：
1. base **默认挂了** `goal` + `goal-round-driver` + `command-goal` + `tool-goal`（`base/cordis.patch.yml:292-299`）——**开箱**
2. 起 dsh
3. **设个目标**："用 goal 设定目标：把当前目录的 README 补全，然后自动续跑直到完成"
4. 观察：**agent 一轮轮自己干**（`goal/round` 相关事件）→ 直到 `complete`

> ⚠️ **未实测**：续跑涉及多轮 + 自动注入——**动手阶段先设"小目标"试**。

---

## 一页纸总结

| 概念 | 一句话 | 出处 |
|---|---|---|
| **goal** | 同会话持久目标（可续跑） | `goal.zh.md:7` |
| **`GoalPhase`** | `active`/`paused`/`blocked`/`complete` | `:7` |
| **blocked** | 唯一"因问题停止"状态（带 `code`） | `:30` |
| **持久 vs 进程本地** | `phase`（持久）vs `activation`（进程本地） | `:7` |
| **`goal-round-driver`** | **自动续跑的驱动器** | `goal-round-driver` |
| **3 工具** | `get_goal`/`create_goal`/`update_goal` | `tool-goal` |
| **命令** | `/goal` | `command-goal:193` |
| **`ctx.goals`** | `get`/`create`/`edit`/`resume`/`disarm` | `:176` |

## 踩坑预防

- **⚠️ `phase`（持久）≠ `activation`（进程本地）**：别混。（出处：`goal.zh.md:7`）
- **⚠️ 改 goal 要带 `revision`**（compare-and-set）。（出处：`GoalRef`）
- **⚠️ `maxGoalRounds` 是上限**：防无限续跑。（出处：`GoalSnapshot`）
- **⚠️ `blocked` 表示"有问题停了"**：不是"完成"。（出处：`goal.zh.md:32`）

## 下一步

- **07 篇**：agent-team（团队协作）
- **深水区 ④**：mini-dsh 从零
