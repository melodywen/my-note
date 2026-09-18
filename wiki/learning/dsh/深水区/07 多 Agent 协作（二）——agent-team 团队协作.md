---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, agent-team, 多agent, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 05 多 Agent 协作（二）——agent-team 团队协作

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**04 篇（subagent 委派）**——本篇是它的"进阶：多成员协作"
> - ⚠️ **实验性**（`packages/experimental/`）
> - 写法说明：本系列采用**完整重讲式**；以**读源码 + 讲机制**为主

> [!abstract] 本章是什么 / 该记住什么
> **回答的问题**："**多个 agent 互相调用**"——怎么实现？
> **答案**：**`agent-team`**——**Lead（队长）+ teammates（队友）**：**共享工作目录、共享任务板、能互相发消息**。
> **读完该记住 5 点**：
> 1. **它才是"多 agent 互相调用"**（`send_message` 双向 + 共享任务 DAG）——**不是 subagent**
> 2. **三概念**：roster（谁在场）/ mailbox（消息）/ 任务 DAG（协作任务）
> 3. **9 个工具**：`spawn_teammate` / `send_message` / `wait_agent` / `list_agents` / `team_task_*` / `interrupt_agent`
> 4. **使用纪律**：只在用户明确要求时用；**写操作分不相交 scope**；Lead 必须等队友
> 5. **⚠️ 实验性 + 不默认挂**：要显式加 `agent-team` 相关插件

## 这一篇在讲什么

**04 篇的 subagent = "一次性委派"**（起个子 agent 干活、拿结果）。**但"多个 agent 互相调用/协作"**（发消息、共享任务、共同改代码）——**那是 `agent-team`**。

> **出处**：`tool-agent-team/src/index.ts:31`（POLICY，逐字）——*"**Agent Teams** is available in this session, but **create teammates only when the user explicitly asks to use Agent Teams or teammates**."*

**一句话**：**`agent-team` = 一个"团队"**（**Lead 队长 + 多个 teammate 队友**），**共享工作目录 + 任务板 + 消息**。

> **Go 类比**：像**一个"工作组"**（Leader + Workers）——不像 subagent 的"发一次任务"，而是**持续协作**（发消息、认领任务、共同改文件）。

---

## 一、vs subagent（先分清，别用错）

|     | **subagent**（04 篇）      | **agent-team**（本篇）         |
| --- | ----------------------- | -------------------------- |
| 目标  | **一次性委派**（起子 agent、拿结果） | **多成员持续协作**                |
| 通信  | 返回结果（单向）                | **`send_message` 双向**      |
| 任务  | 无                       | **共享任务 DAG**               |
| 身份  | 子 agent（继承 preset）      | **teammate（有 name/phase）** |
| 实验性 | ❌ 稳定                    | ✅ **实验性**                  |

> **⚠️ 教训（我踩过）**：**想"多 agent 互相调用"，别用 subagent 硬凑**——**那是 `agent-team` 的活**。subagent 的 `subagent` 工具**只能"起新子 agent"，不能"点名通信"**。

---

## 二、三个核心概念

### ① 身份与 roster（谁在场）

> **出处**：`agent-team.zh.md:9`（逐字）

```ts
interface TeamMemberSnapshot {
  readonly id: SessionId          // teammate 的持久身份
  readonly name: string           // 不可变的模型/UI 标签
  readonly description: string
  readonly provider: string
  readonly context: 'fresh' | 'fork'
  readonly phase: TeamMemberPhase
  readonly error?: string
}
```

- **`TeamId`** = **Root `SessionId`**（**队长的会话就是 Team**）
- **`phase`**：`provisioning` → **`active`** / **`failed`**（终态）

> **出处**：`agent-team/src/types.ts:44`——`TeamMemberPhase = 'provisioning' | 'active' | 'failed'`

### ② 持久 mailbox（互相发消息）

> **出处**：`agent-team.zh.md:26`（逐字）

- **`send_message`** → **存储消息** → 尝试投递
- **投递方式**（按目标状态）：**running → 最近步骤边界**；**idle → 启动一轮**；**inactive → 冷恢复**
- **`queued-minus-delivered`** = 恢复用的 mailbox（**持久，崩溃可恢复**）

### ③ 共享任务 DAG（协作任务板）

> **出处**：`agent-team.zh.md:56`（逐字）

```ts
interface TeamTaskSnapshot {
  readonly id: TeamTaskId
  readonly revision: number        // compare-and-set，每次变更 +1
  readonly subject: string
  readonly description: string
  readonly status: TeamTaskStatus
  readonly ownerId?: SessionId
  readonly blockedBy: TeamTaskId[] // 依赖边（无环图）
  readonly writeScopes: string[]   // ⚠️ 提示性路径前缀，不是锁
}
```

- **status**：`pending` / `in_progress` / `completed` / `deleted`
- **`blockedBy`**：任务依赖（`completed` 才解除阻塞）
- **`writeScopes`**：**"提示性"的写路径前缀**（**不是锁**——*"advisory, not a lock"*）

> **出处**：`agent-team/src/types.ts:71`——`TeamTaskStatus = 'pending' | 'in_progress' | 'completed' | 'deleted'`

---

## 三、9 个工具（**"多 agent 互相调用"的实体**）

> **出处**：`tool-agent-team/src/index.ts`（`name:`，逐字）

| 工具                     | 作用                                                            |
| ---------------------- | ------------------------------------------------------------- |
| **`spawn_teammate`**   | **起一个队友**（`name`/`description`/`prompt`/`context`/`provider`） |
| **`send_message`**     | **给另一个 agent 发消息**（running/idle/inactive 都能投递）                |
| **`wait_agent`**       | **等队友变化**（只观察"调用之后"的变化，**不唤醒**）                               |
| **`list_agents`**      | 列队友                                                           |
| **`team_task_create`** | 建任务（`blockedBy`/`writeScopes`）                                |
| **`team_task_get`**    | 读一个任务                                                         |
| **`team_task_list`**   | 列任务                                                           |
| **`team_task_update`** | 更新任务（**claim/complete**）                                      |
| **`interrupt_agent`**  | 打断队友                                                          |

**对应 `ctx.agentTeams` 的方法**：
> **出处**：`agent-team/src/index.ts`——`spawnTeammate`(:153) / `sendMessage`(:163) / `createTask`(:173) / `updateTask`(:202) / `waitForChange`(:213) / `interrupt`(:224) / `membership`(:134) / `listMembers`(:143) / `getTask`(:183) / `listTasks`(:192)

---

## 四、⭐ 使用纪律（POLICY，逐字要点）

> **出处**：`tool-agent-team/src/index.ts:31`（POLICY，逐字）

| 规则 | 原文要点 |
|---|---|
| **只在明确要求时用** | *"create teammates only **when the user explicitly asks** to use Agent Teams or teammates"* |
| **共享目录** | *"The Team Lead and all teammates **share the same working directory and filesystem**. Edits are **immediately visible** to every member."* |
| **写操作分 scope** | *"Split write work into **disjoint scopes**… Write-scope overlap is **advisory, not a lock**."* |
| **任务工作流** | *"list, get, **claim with the current revision**, perform the work, then **complete**."* |
| **`wait_agent` 不唤醒** | *"**wait_agent observes only changes after that call starts, never wakes a member**"* |
| **Lead 必须等** | *"The Lead **must wait for required teammates** before giving the final answer."* |
| **文件冲突处理** | *"If a file operation returns `FS_STALE_VERSION`, read the current file, **rebase your change**, and retry."* |

**⚠️ 关键**：**它是"协作"，不是"隔离"**——**共享目录、写冲突要自己协调**。

---

## 五、⚠️ 实验性 + 要显式挂

> **出处**：本人核对（`packages/experimental/`）

- **它在 `packages/experimental/`**（**实验性**）
- **`dsh-base` / `dsh-web-app` 都【没有】默认挂它**（实测 `grep agent-team packages/bundle/*/cordis.patch.yml` → **无**）
- **要用 → 显式加**（`tool-agent-team` + 相关包）

**相关包**（5 个）：
```
packages/experimental/
├── agent-team                 ← 领域服务（ctx.agentTeams）
├── tool-agent-team            ← 9 个工具
├── agent-team-profile         ← profile 相关
├── agent-team-web-profile     ← web profile
└── client-ui-agent-team       ← UI
```

---

## 六、动手（指南）

> **规则（AGENTS.md）**：动手环节"你动手"。本节是**指南**（**未实测**——agent-team 实验性 + 要显式挂，配置较复杂）。

**思路**：
1. **显式加 `agent-team` 相关插件**（overlay / patch）
2. 起 dsh
3. **让模型（Lead）`spawn_teammate`** 起个队友
4. Lead **`send_message`** 给队友派活 → **`wait_agent`** 等结果
5. 观察**任务板**（`team_task_*`）

**⚠️ 前置**：需确认 `agent-team` 的挂载方式（它自带 `agent-team-profile` / `-web-profile`，可能是专门的 profile）。**动手阶段先摸清怎么挂**。

> **⚠️ 未实测**：agent-team 是**实验性**，挂载/交互比前面的复杂——**动手阶段先验证"能不能挂起来"**。

---

## 一页纸总结

| 概念 | 一句话 | 出处 |
|---|---|---|
| **agent-team** | Lead + teammates 协作 | `tool-agent-team` |
| **vs subagent** | 协作 vs 一次性委派 | 两篇对照 |
| **roster** | 谁在场（`name`/`phase`） | `agent-team.zh.md:9` |
| **mailbox** | 持久消息（`send_message`） | `:26` |
| **任务 DAG** | 共享任务板（`blockedBy`/`writeScopes`） | `:56` |
| **9 工具** | spawn/send/wait/list/team_task_*/interrupt | `tool-agent-team` |
| **纪律** | 明确要求才用；写分 scope；Lead 等队友 | POLICY |
| **实验性** | `packages/experimental/`；**不默认挂** | 实测 |

## 踩坑预防

- **⚠️ 别用 subagent 硬凑"多 agent 协作"**：那是 agent-team 的活。（出处：实测教训）
- **⚠️ 只在用户明确要求时用**：POLICY 首条。（出处：POLICY）
- **⚠️ 共享目录会冲突**：写操作分 scope；`FS_STALE_VERSION` 要 rebase 重试。（出处：POLICY）
- **⚠️ `writeScopes` 不是锁**：只是"提示"，重叠了还得自己协调。（出处：`agent-team.zh.md:56`）
- **⚠️ 实验性 + 不默认挂**：用前先确认怎么挂。（出处：实测）
- **⚠️ 未实测**：动手指南未实跑。（出处：诚实标注）

## 下一步

- **深水区 ④**：mini-dsh 从零（综合检验）
- **③ 多 Agent 收尾**（subagent + agent-team 都覆盖了）
