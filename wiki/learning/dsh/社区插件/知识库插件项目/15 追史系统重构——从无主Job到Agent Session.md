---
title: 追史系统重构——从无主Job到Agent Session
date: 2026-09-29
tags:
  - 知识库插件
  - 追史
  - 架构设计
  - Agent-Session
  - dsh
---

# 15 追史系统重构——从无主Job到Agent Session

> 本文记录追史系统从"无主裸脚本"重构为"Agent Session 驱动"的架构设计。
> 是实现的权威依据。

---

## 一、现状与问题

### 1.1 当前追史的工作方式

追史 Job 是插件在 `apply()` 里自行 `attachController` 后 `jobs.start()` 的 **unowned job**：

- 没有归属会话（无 owner session）
- 用户在插件面板点"立即追史"→ 调插件自己的 HTTP API → 后台裸脚本执行
- LLM 流的 chunk 类型是 `text-delta`，逐 token 拼接成文章
- 生成完写到 `50-草稿区/`，等人工审阅
- 游标 `lastChased` 记在磁盘 `_追踪.md`（存于库内容根目录），从旧到新顺序追

### 1.2 核心问题

| 问题 | 原因 |
|------|------|
| 侧边栏看不到会话 | Job 是 unowned，不走 dsh 对话流 |
| 看不到过程细节 | 只有 `handle.updateProgress("3/10 · 日期 标题")` 一行文字，前端 3 秒轮询 |
| LLM 生成内容不可见 | text-delta 只拼接到内存字符串，用户看不到"史官正在写什么" |
| 无法被 dsh 原生 Job 插件监控 | `tool-jobs` 在 web-app 被 disabled；unowned job 虽出现在所有 session 的 `job.list` 里，但无完成通知 |
| 生成质量不够准确 | 只给 LLM 看 commit diff，不给完整代码上下文，LLM 不知道"在什么基础上改的" |
| 每个 commit 独立成文，无累积关系 | 没有"分层叠加"概念，功能点的演进脉络断裂 |

### 1.3 dsh 原生能力调研结论

| 能力 | 可用性 | 说明 |
|------|--------|------|
| `ctx.agents.create()` 程序化创建会话 | ✅ | `webhook` 插件已证明可行：创建 workspace + agent + session + 发首条消息 |
| `ctx.jobs` unowned job | ✅ 当前在用 | 出现在所有 session 的 `job.list`，但无完成通知，无过程细节 |
| `ui-jobs` 顶栏 | ❌ 不够用 | `TerminalBlock` 只能渲染纯文本终端，无结构化数据、无 Markdown |
| `tool-jobs` 模型工具 | ❌ 被 disabled | web-app 的 `cordis.patch.yml` 里 `tool-jobs: disabled: true` |
| `dsh-progress-monitor` 等第三方插件 | ❌ 不够用 | 依赖 session-scoped roster，且展示能力同 `ui-jobs`（纯文本终端） |
| `ctx.llm.stream()` LLM 流 | ✅ | `text-delta` chunk 可实时获取每个 token |
| `ctx.skills.register()` 技能注册 | ✅ 当前在用 | 追史提示词模板通过 Skill 注册 |
| `ctx.sessions.create()` 会话创建 | ✅ | 可程序化创建会话，出现在侧边栏 |
| `session.append()` 事件追加 | ✅ | 可往会话日志里写 `user/message`、`assistant/message` 等事件 |
| `webhook` 插件 createWebhookSession() | ✅ 先例 | 程序化创建会话的完整模式：workspace + agent + session + followup |

---

## 二、目标方案：路径 C — 创建 Agent Session

### 2.1 核心思路

追史不再是"无主裸脚本"，而是**创建真正的 dsh Agent Session**：

- 用户点"立即追史"→ 插件调 `ctx.agents.create()` 创建会话
- 侧边栏出现"追史 ecology-agent / 仓库A / 2026-01-15 初始化"的会话
- 用户点进去，能看到完整的对话过程：git checkout、读 diff、读存量、LLM 生成、写草稿
- 全部是 dsh 原生的对话展示，不需要插件自己造 UI

### 2.2 执行模式：逐篇生成，审一篇才能下一篇

```
事情 1 → 创建会话 → 生成草稿 → 审阅通过 → 事情 2 → 创建会话 → ...
```

**逐篇生成**，原因：

1. 串行保证上下文准确——第一篇偏了后面全偏
2. 知识库的存量文章是共享的，事情 2 需要读事情 1 写的层
3. 侧边栏会话按时间顺序排列，逐篇才能看到清晰的"一层层叠加"脉络

### 2.3 每个会话的共同点与差异

| 维度 | 相同 | 不同 |
|------|:----:|:----:|
| workspace 路径 | ✅ 同一个 | |
| 系统提示词（Skill） | ✅ 史官模板 | |
| Agent preset | ✅ 同一个 | |
| 用户提示词 | | ✅ 每个 commit 的 diff 材料 + 存量文章不同 |
| git checkout | | ✅ 每个 commit 切到不同的代码快照 |
| 会话 ID | | ✅ 每次新会话 |
| 工作目录 | ✅ `~/.dsh/knowledge-base/<指纹>/workspace/` | |

---

## 三、目录结构

```
~/.dsh/knowledge-base/
└── <指纹>/                              ← 远端指纹（URL hash）
    ├── knowledge-base/                   ← 知识库克隆（远端 working clone）
    │   ├── .git/
    │   └── <vaultPath>/                  ← 库内容（多个库共享同一远端各写各的子路径）
    │       ├── 00-总表/
    │       ├── 10-史实/
    │       │   ├── <域>/
    │       │   │   └── @<仓库名>/
    │       │   │       ├── 2026-01-15-初始化ObserverPattern.md   ← 第 1 层
    │       │   │       ├── 2026-01-20-新增ClickAdapter.md         ← 第 2 层
    │       │   │       └── 2026-02-10-ClickAdapter增加debounce.md ← 第 3 层
    │       │   └── @快照/
    │       │       └── <域>/
    │       │           └── @<仓库名>/
    │       │               └── 当前能力.md                         ← 当前能力层
    │       ├── 20-术语表/
    │       ├── 30-目录/
    │       ├── 50-草稿区/
    │       └── _追踪.md                  ← 追史游标（lastChased / lastSeenHead）
    └── workspace/                        ← 工作区（Agent 的 cwd）
        ├── knowledge-base -> <绝对路径>/<指纹>/knowledge-base/<vaultPath>/   ← 软链指向知识库内容
        └── repos/                        ← 被跟踪项目（有 working tree 的 clone）
            ├── 仓库A/                     ← git checkout 到对应 commit
            ├── 仓库B/
            └── 仓库C/
```

### 被跟踪仓库的 clone 策略

`workspace/repos/<仓库名>/` 是完整 clone（有 working tree），追史时 `git checkout <commit>` 切到对应提交。

- 多个知识库跟踪同一个仓库时，每个知识库的 workspace 下各有独立 clone（不共享），因为不同知识库可能需要 checkout 到不同 commit
- clone 使用仓库名（而非指纹）作为目录名，便于 Agent 和人类阅读

---

## 四、分层史实生成策略

### 4.1 Docker image 式分层（核心概念）

每个功能点的史实是一层一层叠加的，类似 Docker image 的 layer：

```
commit 1: 新建 ObserverPattern.ts，抽象类 BaseObserver       ← 第 1 层（大量新建）
commit 5: 新增 ClickAdapter 继承 BaseObserver                ← 第 2 层（往功能点上叠）
commit 12: ClickAdapter 增加 debounce 逻辑                   ← 第 3 层（再叠）
```

**每一层都知道下面有哪些层**，不是孤立地写，而是往已有结构上追加。

### 4.2 每个 commit 的追史流程

```
对每个 commit（从旧到新，串行执行）：

1. git checkout <commit>           ← 把被跟踪仓库切到那个时刻
2. 读当前代码快照                    ← Agent 在 workspace/repos/仓库A/ 里看完整代码
3. 读当前 commit 的 diff            ← 这次的改动是什么
4. 读知识库已有的存量文章             ← 之前叠出来的层
5. 结合代码上下文 + 历史增量 + diff   ← LLM 理解"在什么基础上改的"
6. 生成这一层的史实（增量叠加）       ← 往已有功能点结构上追加
7. 写到知识库草稿区                  ← 50-草稿区/
8. 推进游标                          ← 更新 _追踪.md
9. 创建下一个 commit 的会话           ← 继续叠
```

### 4.3 外链索引格式

文章里标注代码位置，不需要精确到行号，精确到"文件 + 函数"即可：

```markdown
> 本层新增 `ClickAdapter`（[`src/adapters/ClickAdapter.ts`](../repos/仓库A/src/adapters/ClickAdapter.ts) · `ClickAdapter` 类），
> 继承自 `BaseObserver`（[`src/patterns/ObserverPattern.ts`](../repos/仓库A/src/patterns/ObserverPattern.ts) · `BaseObserver` 抽象类）。
```

---

## 五、两类知识：增量层 vs 当前能力层

### 5.1 定义

| | 增量层（史实） | 当前能力层 |
|---|---|---|
| 读者 | 想了解演进历史的人 | 做产品方案/技术选型的人 |
| 回答的问题 | 为什么这样设计、踩过什么坑、什么时候改的 | 现在代码能做什么、有哪些能力、接口是什么 |
| 生成时机 | 每个 commit 追史时生成 | 追平后基于 master 生成一次 |
| 跟代码的关系 | 切到对应 commit 看当时的代码 | 只看 master 最新代码 |
| 存放位置 | `10-史实/<域>/<@仓库名>/` | `10-史实/@快照/<域>/<@仓库名>/` |
| 时间线 | 有，按 commit 顺序 | 无，只反映当前 master 状态 |
| 性质 | 历史记录 | 功能能力提取 |

### 5.2 当前能力层不是"总结"也不是"快照"

- **不是"总结"** — 总结意味着把增量层压缩成一层，但当前能力层不追究历史
- **不是"快照"** — 快照意味着代码的某个时刻状态，但当前能力层是功能能力的提取
- **是"功能能力提取"** — 基于当前 master 代码，回答"这个项目现在能做什么"

### 5.3 两类知识独立存在

- 增量层的时间线不会被当前能力层搞乱（存放在不同目录）
- 当前能力层不需要读完所有增量层才能生成（只看 master 代码）
- 用户按需取用：做方案看当前能力层，了解历史看增量层

---

## 六、追史提示词（Skill）规范

1. **Docker image 式分层** — 每篇文章是一个"层"，往已有功能点上叠加
2. **读存量** — 生成前先读已有的史实文章，理解之前叠了哪些层
3. **代码上下文** — Agent 的 workspace 里有完整代码，要主动读
4. **功能点聚合** — 识别哪些 commit 属于同一个功能点
5. **分层抽象原则** — 只要某个东西有"一层一层往上叠"的结构，就按层组织。不限于设计模式（观察者、适配器、抽象类），也包括模块拆分、接口演进、功能迭代、重构等。具体规则：有复用、有独立迭代轨迹的才拆层（如多个 Adapter 共享基类 → 基类一层、每个 Adapter 各一层）；没有的写在一起（如只有一个 Adapter → 不用拆）
6. **外链索引** — 标注对应文件路径 + 函数名
7. **分层标记** — 标记清楚这篇文章是哪一层、叠在哪个功能点上即可，具体措辞由提示词模板决定

> 具体 Skill 内容待实现阶段编写，初版给出大概方向，后续由人工评审迭代定稿。

---

## 七、会话创建的技术实现要点

### 7.1 参考先例：webhook 插件

`dsh-webhook` 的 `createWebhookSession()`（源码：`packages/webhook/webhook/src/session.ts`）已证明程序化创建会话可行：

```typescript
// 1. 创建 workspace
const workspace = await ctx.workspaceRegistry.create(workspacePath)

// 2. 创建 Agent + Session（出现在侧边栏）
const handle = await ctx.agents.create({
  sessionId,
  meta: { cwd: workspace.path, agentPreset: preset.id },
  agentOptions: { provider, model },
  setup: async (agentCtx) => {
    await ctx.agentPresets.mount(agentCtx, preset.id)
  },
})

// 3. 发第一条消息（触发 agent loop）
handle.agent.followup(createUserMessage({
  content: [{ type: 'text', text: prompt }],
}))
```

### 7.2 追史需要的 inject

```typescript
export const inject = ['llm capabilities', 'jobs', 'skills', 'agents', 'agentPresets', 'workspaceRegistry']
```

- `agents` — 创建 Agent + Session
- `agentPresets` — 解析和挂载 preset
- `workspaceRegistry` — 创建 workspace

### 7.3 追史 Workflow 的用户提示词结构（每个 commit 不同）

```
# 追史任务

## 工作空间
- 知识库：workspace/knowledge-base/（软链）
- 被跟踪仓库：workspace/repos/仓库A/
- 当前 commit：<hash>
- 当前 commit 日期：<date>
- 当前 commit 作者：<author>
- 当前 commit 主题：<subject>

## 任务步骤
1. 执行 `git checkout <hash>` 切到当前 commit
2. 阅读当前代码结构，理解项目架构
3. 阅读当前 commit 的 diff（`git show <hash>`）
4. 阅读 workspace/knowledge-base/10-史实/ 下已有的史实文章
5. 结合代码上下文 + diff + 已有史实，生成本层的增量内容
6. 写到 workspace/knowledge-base/50-草稿区/<date>-<title>.md

## 写作规范
（引用 Skill 的 system prompt）
```

### 7.4 串行执行控制

追史主循环串行创建会话：

```typescript
for (const item of plan.items) {
  // 1. 创建会话
  const handle = await ctx.agents.create({ ... })
  
  // 2. 发提示词，触发 agent 执行
  handle.agent.followup(createUserMessage({ content: [...] }))
  
  // 3. 等待 agent 完成
  await waitForAgentIdle(handle.agent)
  
  // 4. 推进游标
  await updateCursor(vault, ..., { lastChased: item.commits[last] })
  
  // 5. 清理 handle，继续下一个 commit
  await handle.dispose()
}
```

### 7.5 待确认的技术问题

| 问题 | 方案方向 |
|------|---------|
| Agent preset 用哪个？ | 用 web-app 的 standard preset，或为追史定制一个最小 preset |
| permission preset 用哪个？ | 需要文件读写 + git 执行权限 |
| 怎么知道 agent 完成了？ | 监听 agent idle 事件，或轮询 session 状态 |
| Agent 有哪些工具可用？ | bash（git checkout / git show）、fs（读写文件），可能不需要其他 |
| workspace 路径如何传给 agents.create？ | `meta.cwd = workspacePath` |
| 多仓库串行怎么控制？ | 外层 Job 循环，按仓库 → commit 顺序逐个创建会话 |
