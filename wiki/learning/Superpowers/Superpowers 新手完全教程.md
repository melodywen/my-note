---
type: concept
status: developing
area: growth
title: "Superpowers 新手完全教程"
question: "Superpowers 是什么、怎么装、怎么用——从零到日常实战"
created: 2026-07-10
updated: 2026-07-10
tags:
  - learning
  - superpowers
  - AI编程
  - Agent技能
  - OpenCode插件
related:
  - "[[Oh-My-OpenAgent-实战搭配使用指南]]"
  - "[[Obsidian 命令与技能完全指南]]"
sources:
  - "https://github.com/obra/superpowers （官方仓库，作者 Jesse Vincent，MIT）"
  - "本地已安装的 14 个 SKILL.md（逐个读取核对）"
  - "https://blog.fsck.com/2025/10/09/superpowers/ （原作者发布博文）"
---

# Superpowers 新手完全教程

> 本文写给**第一次接触 Superpowers 的人**：它是什么、为什么有用、怎么安装、日常怎么用。所有内容基于本地已安装的 14 个 SKILL.md 逐个核对，不是网上抄的摘要。

---

## 一、Superpowers 是什么

### 一句话定义

**Superpowers 是一套给 AI 编程助手用的"软件开发方法论"插件**——它让你的 AI 不再"上来就写代码"，而是先想清楚、再规划、再用 TDD 写、最后验证。

### 它解决什么问题

你大概遇到过这些场景：

| 痛点 | 没有 Superpowers | 有 Superpowers |
|------|-----------------|---------------|
| AI 上来就写代码，方向全错 | 你说"加个登录"，它立刻写 200 行 | 先问你：JWT 还是 session？过期策略？测试怎么写？ |
| 写完代码说"完成了"，其实没测 | "应该能用"、"我测了一下" | 必须跑测试命令、贴输出，有证据才能说"完成" |
| Bug 改了又改，每次改出新 Bug | 瞎猜原因，到处试 | 四阶段系统调试：先找根因，再修 |
| 大任务做到一半上下文丢了 | 重新解释，从头再来 | 进度记在 ledger 文件里，断了能恢复 |
| 代码没有测试 | "太简单不用测" | 铁律：没有失败的测试，不写生产代码 |

### 核心理念（4 条哲学）

1. **Test-Driven Development** — 永远先写测试
2. **Systematic over ad-hoc** — 系统流程，不靠瞎猜
3. **Complexity reduction** — 简单是首要目标（YAGNI / DRY）
4. **Evidence over claims** — 先验证，再宣布成功

### 和 Oh-My-OpenAgent 的关系

|     | Oh-My-OpenAgent (OmO)           | Superpowers              |
| --- | ------------------------------- | ------------------------ |
| 定位  | AI **团队**编排（11 个特工协作）           | AI **工作流**规范（14 个技能约束行为） |
| 解决  | "谁来做、用什么模型"                     | "怎么做、按什么流程做"             |
| 类比  | 给团队分了岗位                         | 给团队定了SOP（标准操作流程）         |
| 关系  | **互补**——OmO 管调度，Superpowers 管质量 |                          |

你可以同时用两者：OmO 的 Sisyphus 接到任务后，Superpowers 的 brainstorming 会先触发，逼它先想清楚再动手。

---

## 二、安装（OpenCode 环境）

### 你可能已经装好了

如果你在 OpenCode 的 `opencode.jsonc` 里看到了这行：

```jsonc
"plugin": [
  // ... 其他插件 ...
  "superpowers@git+https://github.com/obra/superpowers.git"
]
```

那你已经装好了。验证方法：开一个新对话，如果开头出现了 `<EXTREMELY_IMPORTANT>` 和 "You have superpowers" 的内容，说明插件已加载并生效。

### 如果还没装

在 OpenCode 里告诉 AI：

```
Fetch and follow instructions from https://raw.githubusercontent.com/obra/superpowers/refs/heads/main/.opencode/INSTALL.md
```

它会自动拉取安装指南并帮你配置。

### 其他平台

Superpowers 支持 11 个平台（Claude Code / Codex / Cursor / Gemini CLI / Copilot CLI 等），每个平台装法不同，但装好后效果一样。完整列表见[官方 README](https://github.com/obra/superpowers)。

---

## 三、14 个技能总览

Superpowers 的核心是 **14 个 Skill（技能）**，每个技能是一个 `SKILL.md` 文件，定义了一种工作规范。AI 在对话中会自动检测该用哪个技能。

### 速查表

| #   | 技能名                                | 一句话               | 什么时候触发                |
| --- | ---------------------------------- | ----------------- | --------------------- |
| 1   | **using-superpowers**              | 技能系统入口 / 总调度      | 每次对话开始时自动加载           |
| 2   | **brainstorming**                  | 想清楚再动手            | 你说"做一个 X" / "加个 Y 功能" |
| 3   | **writing-plans**                  | 把设计拆成可执行的计划       | brainstorming 结束后     |
| 4   | **executing-plans**                | 按计划执行（人工检查点）      | 有计划了，你说"go"           |
| 5   | **subagent-driven-development**    | 按计划执行（子 Agent 自动） | 有计划了，想全自动             |
| 6   | **test-driven-development**        | TDD 铁律：先写测试       | 每次写代码时                |
| 7   | **systematic-debugging**           | 四阶段调试法            | 遇到 Bug / 测试失败         |
| 8   | **verification-before-completion** | 说"完成"前必须验证        | 每次想宣布完成时              |
| 9   | **dispatching-parallel-agents**    | 并行派发独立任务          | 有 2+ 个互不依赖的问题         |
| 10  | **requesting-code-review**         | 请求代码审查            | 完成一个任务 / 大功能后         |
| 11  | **receiving-code-review**          | 接收审查反馈            | 收到 review 意见时         |
| 12  | **using-git-worktrees**            | 隔离工作区             | 开始新功能开发时              |
| 13  | **finishing-a-development-branch** | 收尾：合并/PR/丢弃       | 所有任务做完后               |
| 14  | **writing-skills**                 | 写新技能（高级）          | 想自己创建新技能时             |

### 按使用频率分

```
几乎每次对话：  using-superpowers（自动）、brainstorming、test-driven-development、verification-before-completion
经常用：        writing-plans、executing-plans / subagent-driven-development、finishing-a-development-branch
偶尔用：        systematic-debugging（出 Bug 时）、dispatching-parallel-agents（多任务时）、requesting/receiving-code-review
很少用：        using-git-worktrees（隔离开发时）、writing-skills（写新技能时）
```

---

## 四、核心工作流（7 步完整流程）

这是 Superpowers 最重要的一条链路——从"我想做一个功能"到"功能完成合并入库"。

```
你说 "做一个 X"
    │
    ▼
① brainstorming —— 想清楚：问问题、出设计、你确认
    │
    ▼
② using-git-worktrees —— 建隔离工作区（新分支）
    │
    ▼
③ writing-plans —— 拆任务：每步 2-5 分钟，带代码和测试
    │
    ▼
④ subagent-driven-development —— 派子 Agent 逐个执行
    │  （每个任务内部：）
    │  ⑤ test-driven-development —— 先写测试→看它失败→写代码→看它通过
    │  ⑥ requesting-code-review —— 子 Agent 做完 → 另一个子 Agent 审查
    │
    ▼
⑦ finishing-a-development-branch —— 全部做完 → 验测试 → 合并/PR/保留/丢弃
```

下面逐个展开。

---

### 第 ① 步：Brainstorming（头脑风暴）

**触发**：你说"做一个 X"、"加个 Y"、"我想实现 Z"。

**AI 会做什么**：
1. 先看你的项目（文件、文档、最近 git 提交）
2. **一次只问一个问题**，搞清楚你到底要什么
3. 提出 2-3 个方案，告诉你各自的优缺点和推荐
4. 分段展示设计，每段问你"这部分对不对？"
5. 你确认后，写设计文档到 `docs/superpowers/specs/` 并 git commit

**铁律**：在你说"设计 OK"之前，**一行代码都不会写**。

**你要做什么**：回答问题、选方案、确认设计。

**实际对话长这样**：

```
你：帮我加一个用户注册功能

AI：先看一下项目……你用的是 Express + PostgreSQL。
    第一个问题：注册需要邮箱验证吗？还是注册即可用？

你：需要邮箱验证。

AI：好的。密码存储用 bcrypt 还是 argon2？

你：bcrypt。

AI：我推荐两个方案：
    A) 邮箱验证链接（点击即激活）—— 简单，用户体验好
    B) 验证码（输入 6 位数字）—— 更安全，但多一步
    我推荐 A，因为注册场景链接验证更常见。你觉得呢？

你：A。

AI：好，设计如下：
    【架构】POST /register → 创建用户(未激活) → 发验证邮件 → GET /verify → 激活
    【数据】users 表加 email_verified 字段
    【测试】……
    这部分对吗？

你：对。

AI：（继续下一段……直到全部确认）
    设计文档已写入 docs/superpowers/specs/2026-07-10-user-registration-design.md
    请你 review 一下，有问题告诉我，没问题我就开始写计划。
```

---

### 第 ② 步：Git Worktree（隔离工作区）

**触发**：设计确认后，开始写代码前。

**AI 会做什么**：
1. 检查是否已经在隔离环境（如果是就跳过）
2. 如果不是，问你"要不要建个 worktree？"
3. 建新分支 + 新目录，不污染你当前的分支
4. 装依赖、跑测试，确认基线干净

**你要做什么**：同意或拒绝建 worktree（一般同意）。

**为什么重要**：你在 `main` 分支上开发到一半，AI 改了一堆文件，突然发现方向错了——有 worktree 就可以直接删掉，`main` 干干净净。

---

### 第 ③ 步：Writing Plans（写实施计划）

**触发**：设计文档确认后。

**AI 会做什么**：
1. 把设计拆成一个个 **bite-sized task**（每步 2-5 分钟）
2. 每个任务写清楚：改哪个文件、代码是什么、测试怎么写、预期输出
3. 保存到 `docs/superpowers/plans/`

**计划长这样**：

```markdown
### Task 1: 创建 User 模型

**Files:**
- Create: src/models/User.ts
- Test: tests/models/User.test.ts

- [ ] Step 1: 写失败的测试
- [ ] Step 2: 跑测试，确认它因为"User 不存在"而失败
- [ ] Step 3: 写最小的代码让测试通过
- [ ] Step 4: 跑测试，确认通过
- [ ] Step 5: git commit

### Task 2: 注册 API 端点
……
```

**铁律**：计划里不能有 "TODO"、"TBD"、"类似 Task 1"——每一步必须有完整的代码和命令。

---

### 第 ④ 步：执行计划

你有两个选择：

#### 选项 A：Subagent-Driven Development（推荐）

**怎么用**：AI 自动派一个"子 Agent"去做每个任务，做完再派另一个"审查 Agent"检查，检查通过才进下一个任务。

**流程**：
```
计划 Task 1 → 派 Implementer Agent → 它写测试→写代码→跑测试→commit
    → 派 Reviewer Agent → 检查是否符合设计 + 代码质量
    → 通过？进 Task 2。不通过？派 Fixer Agent 修。
```

**优点**：
- 每个子 Agent 上下文干净，不会"记混了"
- 自动审查，质量有保障
- AI 可以连续做 2 小时不停，因为你定的计划它照着走

**你要做什么**：开始时说"用 subagent-driven 执行"，然后等它做完。

#### 选项 B：Executing Plans（手动检查点）

**怎么用**：AI 在当前会话里逐个任务执行，每做完一个停下来让你看。

**适合**：你想紧跟每一步、随时介入修改。

---

### 第 ⑤ 步：TDD（测试驱动开发）

**触发**：在执行计划的每个任务内部，只要写代码就强制触发。

**铁律**：
```
没有失败的测试 → 不写生产代码
```

**三步循环**：

```
RED（红）→ 写一个测试 → 跑它 → 看它失败（因为功能还没写）
GREEN（绿）→ 写最少的代码让测试通过 → 跑它 → 看它通过
REFACTOR（重构）→ 整理代码 → 确保测试还通过
```

**如果你先写了代码**：Delete it. Start over.（删掉，从头来。不是"参考一下"，是删除。）

**为什么这么严格**：先写测试 = 先定义"什么算成功"。如果先写代码再补测试，你只会测你写的，不是测你需要的。

---

### 第 ⑥ 步：Code Review（代码审查）

**触发**：每个任务做完后（subagent-driven 模式自动触发）。

**AI 会做什么**：派一个全新的子 Agent（不带有执行者的偏见），检查：
- 设计文档的要求是否都满足了？（spec compliance）
- 代码质量好不好？（命名、结构、有没有多余的代码）

**问题分三级**：
- **Critical**：必须立刻修（阻断进度）
- **Important**：做完这一步前必须修
- **Minor**：记下来，最后统一处理

---

### 第 ⑦ 步：Finishing（收尾）

**触发**：所有任务做完后。

**AI 会做什么**：
1. 先跑完整测试套件，确保全部通过
2. 给你 4 个选项：
   - 合并回主分支
   - 推送并创建 PR
   - 保留分支（你之后自己处理）
   - 丢弃这些工作

**你要做什么**：选一个。

---

## 五、两个"纪律守护"技能

这两个技能不是流程步骤，而是**贯穿全程的行为约束**。

### Verification Before Completion（完成前验证）

**铁律**：
```
没有刚跑过的验证证据 → 不能说"完成了"
```

**禁止说**：
- "应该可以了"
- "我很有信心"
- "大概没问题"
- "完美！" / "搞定！"

**必须做**：跑测试命令 → 贴输出 → 确认 0 个失败 → 然后才能说"测试通过"。

**为什么**：AI 说"完成了"但实际没跑验证，是最常见的翻车原因。这个技能就是堵这个漏洞。

### Systematic Debugging（系统调试）

**触发**：遇到任何 Bug、测试失败、异常行为。

**四阶段**：

| 阶段 | 做什么 | 核心规则 |
|------|--------|---------|
| 1. 根因调查 | 读错误信息、复现、查最近改动 | **没有完成调查，不能提修复方案** |
| 2. 模式分析 | 找类似的能跑的代码、对比差异 | 不假设"这个不重要" |
| 3. 假设测试 | 提一个假设、做最小改动验证 | 一次只改一个变量 |
| 4. 实施修复 | 先写复现 Bug 的失败测试，再修 | 如果修了 3 次还不行 → 质疑架构 |

**红线**：如果你发现自己在想"先试试改这个看行不行"→ 停！回阶段 1。

---

## 六、日常怎么用（实战指南）

### 场景 1：日常小修改（80% 的情况）

**例子**：改个变量名、修个类型错误、加一行日志。

**怎么用**：直接说。Superpowers 的 brainstorming 会判断这太简单不需要走完整流程，TDD 会判断要不要写测试。

```
你：把 src/utils/format.ts 里的 formatDate 改成 formatISODate

AI：（直接改，因为这是改名不是加功能）
```

### 场景 2：加一个新功能（15% 的情况）

**例子**：加个 API 接口、加个页面、加个导出功能。

**怎么用**：完整走 7 步流程。

```
你：帮我加一个用户导出 CSV 的功能

AI：[brainstorming] 先问你几个问题……
    → [设计确认] → [写计划] → [你说 go]
    → [subagent 逐个执行 + TDD + review]
    → [全部完成 → 问你合并还是 PR]
```

### 场景 3：修 Bug（5% 的情况）

**例子**：接口返回 500、测试挂了、数据不对。

**怎么用**：systematic-debugging 自动触发。

```
你：登录接口返回 500

AI：[systematic-debugging 阶段1]
    先看错误信息……
    "TypeError: Cannot read property 'password' of undefined"
    在 src/auth/login.ts:42
    复现：当 email 不在数据库里时触发
    根因：没检查 user 是否存在就用 user.password

    [阶段4] 先写一个测试复现这个 Bug……
    → 测试失败（Bug 还在）→ 修代码 → 测试通过 → commit
```

### 场景 4：多个独立问题要同时处理

**例子**：3 个不同模块的测试各自失败，互不相关。

**怎么用**：dispatching-parallel-agents 自动触发——派 3 个子 Agent 分别去修，并行执行。

---

## 七、技能之间的依赖关系

```
                    using-superpowers（入口）
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
    brainstorming   systematic    verification-
    （设计）        debugging     before-completion
         │          （调试）       （验证）
         ▼
    writing-plans
    （计划）
         │
    ┌────┴────┐
    ▼         ▼
  executing  subagent-driven    ← test-driven-development（贯穿执行）
  -plans     -development       ← requesting/receiving-code-review（贯穿审查）
    │         │
    └────┬────┘
         ▼
    finishing-a-development-branch
    （收尾）

  using-git-worktrees → 在 brainstorming 之后、执行之前
  dispatching-parallel-agents → 独立，任何需要并行时
  writing-skills → 独立，想创建新技能时
```

---

## 八、常见问题

### Q: Superpowers 会让我变慢吗？

**A:** 短期看，小任务确实多了几步（先问问题、先写测试）。但长期看更快——因为方向不会错、Bug 不会积累、代码有测试保底。原作者说得好："TDD 比调试快。"

### Q: 我能跳过 brainstorming 直接写代码吗？

**A:** 能。你说"别问了直接写"就行。**用户指令优先级 > Superpowers 技能**。但跳过了后果自负。

### Q: 我不想用 TDD 怎么办？

**A:** 在你的 `AGENTS.md` / `CLAUDE.md` 里写"不用 TDD"。Superpowers 的技能会尊重你的指令。但同样，后果自负。

### Q: subagent-driven 和 executing-plans 怎么选？

| | subagent-driven | executing-plans |
|--|-----------------|-----------------|
| 自动化程度 | 高（全自动执行+审查） | 中（每步停下来让你看） |
| 上下文隔离 | 好（每个子 Agent 独立） | 一般（同一个会话） |
| 适合 | 任务多、想省心 | 想紧跟每一步 |

**推荐**：如果你用的是 OpenCode（支持子 Agent），用 subagent-driven。

### Q: Superpowers 和我已有的 OmO 冲突吗？

**A:** 不冲突。OmO 管"派谁去做"（模型选择、Agent 调度），Superpowers 管"怎么做"（流程规范、质量约束）。它们在不同的层面工作，可以同时生效。

---

## 九、关键术语速查

| 术语 | 大白话 |
|------|--------|
| **Skill（技能）** | 一套工作规范，写成 SKILL.md 让 AI 遵守 |
| **TDD** | 先写测试再写代码，确保"做对了"而不是"做了" |
| **RED-GREEN-REFACTOR** | TDD 三步：失败→通过→重构 |
| **Subagent（子 Agent）** | 被派出去做具体任务的 AI，有独立上下文 |
| **Worktree（工作树）** | Git 的隔离工作区，不影响主分支 |
| **Spec（设计文档）** | brainstorming 产出的设计，写进文件 |
| **Plan（实施计划）** | writing-plans 产出的任务清单，精确到每步 |
| **Ledger（进度账本）** | 记录哪些任务做完了，断了能恢复 |
| **YAGNI** | You Aren't Gonna Need It——别写用不上的功能 |
| **DRY** | Don't Repeat Yourself——别重复 |
| **Root Cause** | 根因——Bug 的真正源头，不是表面症状 |

---

## 十、一张图总结

```
┌─────────────────────────────────────────────────┐
│           Superpowers 完整工作流                  │
│                                                   │
│  你说 "做一个功能"                                │
│       │                                           │
│       ▼                                           │
│  ① brainstorming ← 先想清楚（问问题、出设计）      │
│       │                                           │
│       ▼                                           │
│  ② git worktree ← 隔离环境（不污染主分支）         │
│       │                                           │
│       ▼                                           │
│  ③ writing-plans ← 拆任务（每步 2-5 分钟）         │
│       │                                           │
│       ▼                                           │
│  ④ subagent-driven ← 自动执行                      │
│       │                                           │
│       ├── ⑤ TDD（每个任务内部）                    │
│       │    RED → GREEN → REFACTOR                 │
│       │                                           │
│       ├── ⑥ code-review（每个任务之后）            │
│       │    审查 → 有问题 → 修 → 再审               │
│       │                                           │
│       └── ⑧ verification（每次说"完成"前）         │
│            跑测试 → 贴输出 → 才能说"通过"           │
│       │                                           │
│       ▼                                           │
│  ⑦ finishing ← 收尾（合并/PR/保留/丢弃）           │
│                                                   │
│  贯穿全程的守护者：                                 │
│  · systematic-debugging（出 Bug 时触发）           │
│  · dispatching-parallel-agents（多任务并行时触发）  │
│  · using-superpowers（每次对话自动加载）           │
└─────────────────────────────────────────────────┘
```

---

## 十一、心得与建议

### 新手最容易犯的 3 个错误

1. **嫌 brainstorming 太啰嗦，让它"直接写"**
   → 结果方向错了，返工 2 小时。brainstorming 的 10 分钟问答省的是后面的 2 小时。

2. **看到 TDD 觉得"这个太简单不用测"**
   → "太简单"的代码恰恰是最容易出 Bug 的——因为你觉得简单就不会仔细检查。30 秒写个测试，值。

3. **AI 说"完成了"就信了**
   → verification-before-completion 存在的唯一原因就是：AI 经常在没验证的情况下说"完成"。要求它贴测试输出。

### 最佳实践

- **让 Superpowers 自动触发**：你不需要手动说"用 brainstorming"，它会自己判断。你只需要正常描述你要做什么。
- **回答问题要具体**：brainstorming 问你问题时，给具体答案（"用 bcrypt"比"用加密"好），减少来回。
- **设计文档要 review**：brainstorming 写完 spec 会让你看——认真看，这是方向锚点。
- **信任流程但保持关注**：subagent-driven 可以自动跑很久，但偶尔看看它在干什么，别完全放羊。

---

## 来源与参考

- **官方仓库**：[github.com/obra/superpowers](https://github.com/obra/superpowers)（作者 Jesse Vincent / Prime Radiant，MIT 协议）
- **发布博文**：[blog.fsck.com/2025/10/09/superpowers](https://blog.fsck.com/2025/10/09/superpowers/)
- **本地 14 个 SKILL.md**：`~/.cache/opencode/packages/superpowers@git+https:/github.com/obra/superpowers.git/node_modules/superpowers/skills/`（逐个读取核对）
- **Discord 社区**：[discord.gg/35wsABTejz](https://discord.gg/35wsABTejz)

---

## 继续阅读

- [[Oh-My-OpenAgent-实战搭配使用指南]] — OmO 和 Superpowers 怎么搭配
- [[Obsidian 命令与技能完全指南]] — 另一套 AI 技能体系（知识库方向）
- [[oh-my-openagent.json-小白配置详解]] — OmO 配置文件详解
