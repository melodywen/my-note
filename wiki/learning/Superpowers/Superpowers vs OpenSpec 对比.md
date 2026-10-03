---
type: concept
status: developing
area: growth
title: "Superpowers vs OpenSpec 深度对比"
question: "同样号称 SDD（Spec-Driven Development），Superpowers 和 OpenSpec 到底有什么区别、怎么选"
created: 2026-07-10
updated: 2026-07-10
tags:
  - learning
  - superpowers
  - openspec
  - SDD
  - AI编程
  - 方法论对比
related:
  - "[[Superpowers 新手完全教程]]"
  - "[[Oh-My-OpenAgent-实战搭配使用指南]]"
sources:
  - "https://github.com/obra/superpowers （Superpowers 官方仓库）"
  - "https://github.com/DeepSeek-AI/open-spec （OpenSpec 官方仓库）"
  - "本地已安装的 14 个 Superpowers SKILL.md（逐个读取核对）"
  - "本地 dsh-learn/openspec/ 实际项目文件（proposal.md / design.md / tasks.md / spec.md / config.yaml）"
---

# Superpowers vs OpenSpec 深度对比

> 本文基于**本地实际文件**逐一核对，不是网上摘要。Superpowers 侧读取了全部 14 个 SKILL.md；OpenSpec 侧读取了 `dsh-learn/openspec/` 下的完整 change 实例（proposal → design → tasks → spec delta）。

---

## 一、一句话总结

| | Superpowers | OpenSpec |
|---|---|---|
| **本质** | AI 行为约束插件（runtime skill pack） | 规格变更工作流（file-based workflow） |
| **一句话** | 教 AI **怎么干活**（先想→再规划→TDD→验证） | 教团队**怎么管理变更**（提案→设计→任务→规格增量） |
| **形态** | 14 个 SKILL.md，由 AI 在运行时加载并遵循 | 4 类 Markdown 文件 + CLI 命令，由人和 AI 协作产出 |
| **类比** | 给 AI 戴上"方法论头盔"——视野收窄到正确流程 | 给项目建立"变更档案馆"——每次改动有提案、有设计、有验收标准 |

**它们不是替代关系，而是互补关系。** 你可以同时用：OpenSpec 管理变更提案和规格，Superpowers 约束 AI 执行变更时的行为。

---

## 二、各自是什么

### Superpowers

- **作者**：Jesse Vincent（@obra），MIT 协议
- **形态**：OpenCode / Claude Code 插件，安装后自动注入 14 个 skill
- **核心机制**：AI 每次收到用户消息时，先检查有没有 skill 匹配，有就加载并严格遵循
- **14 个 skill 一览**：

| 阶段 | Skill | 作用 |
|------|-------|------|
| 想清楚 | brainstorming | 强制先发散思考、列方案、收敛 |
| 规划 | planning | 创建分步计划、设检查点 |
| 执行 | using-superpowers | 元规则：怎么用 skill 本身 |
| 执行 | tdd | 铁律：没有失败的测试，不写生产代码 |
| 执行 | systematic-debugging | 四阶段调试：复现→假设→验证→修复 |
| 执行 | code-review | 代码审查清单 |
| 质量 | quality-gates | 发布前检查门 |
| 质量 | remove-ai-slops | 清理 AI 生成的代码坏味 |
| 安全 | security-review | 安全审查 |
| 视觉 | visual-qa | UI 视觉验收 |
| 协作 | git-workflow | Git 操作规范 |
| 协作 | handoff | 上下文交接（断点续传） |
| 协作 | subagent-protocol | 子代理委派协议 |
| 元 | skill-creator | 创建新 skill |

### OpenSpec

- **作者**：DeepSeek AI 团队，开源
- **形态**：项目内文件约定 + CLI 工具（`/opsx-propose`、`/opsx-apply`、`/opsx-archive`）
- **核心机制**：每次变更走 `proposal → design → tasks → spec delta` 四步流程，产出物是 Markdown 文件，留在项目里作为规格档案
- **文件结构**（以本地 `dsh-learn/openspec/` 实例为准）：

```
openspec/
├── config.yaml                    # 项目级配置（schema: spec-driven）
└── changes/
    └── chase-model-owned-paths/   # 一个变更 = 一个目录
        ├── proposal.md            # 为什么改、改什么、影响范围
        ├── design.md              # 设计决策、方案选择、风险
        ├── tasks.md               # 任务清单（checkbox，可追踪进度）
        └── specs/                 # 规格增量（delta）
            └── knowledge-base/
                └── chase-archival/
                    └── spec.md    # 新增/修改的验收标准（Requirement + Scenario）
```

---

## 三、核心维度对比

### 3.1 关注点

| 维度 | Superpowers | OpenSpec |
|------|-------------|----------|
| **关注"怎么干活"** | ✅ 核心——TDD 怎么写、调试怎么做、审查查什么 | ❌ 不关心 |
| **关注"改什么"** | ❌ 不关心 | ✅ 核心——提案写清为什么改、影响哪些代码 |
| **关注"怎么验收"** | 部分（quality-gates、code-review） | ✅ 核心——spec.md 用 Requirement + Scenario 定义验收标准 |
| **关注"怎么规划"** | ✅ planning skill 创建执行计划 | ✅ tasks.md 拆分任务清单 |
| **关注"怎么设计"** | 部分（brainstorming 发散方案） | ✅ design.md 记录设计决策和替代方案 |
| **关注"留下档案"** | ❌ 执行完就完了，不刻意留档 | ✅ 所有变更文件永久留在项目里 |

### 3.2 产出物

| | Superpowers | OpenSpec |
|---|---|---|
| **产出** | 代码 + 测试（执行结果） | 4 个 Markdown 文件（提案、设计、任务、规格增量） |
| **留存** | 只有代码和 git log | 完整的变更档案，独立于代码存在 |
| **可追溯** | 靠 git log 和 commit message | 靠 changes/ 目录，每次变更有独立目录 |
| **验收标准** | 隐式（测试通过 = 验收） | 显式（spec.md 里 Requirement + Scenario） |

### 3.3 流程

**Superpowers 流程（AI 运行时自动触发）：**

```
用户消息 → 匹配 skill → 加载 skill 内容 → AI 按 skill 规定流程执行 → 产出代码
```

- 自动触发，不需要用户手动调用
- skill 之间可链式触发（brainstorming → planning → tdd）
- 流程在 AI 的"脑子"里跑，用户看到的是 AI 的行为变化

**OpenSpec 流程（人 + AI 协作，显式命令驱动）：**

```
/opsx-propose  → 生成 proposal.md + design.md + tasks.md + spec.md
     ↓
人工审查提案 → 修改 → 确认
     ↓
/opsx-apply    → 按 tasks.md 逐项执行（AI 写代码）
     ↓
/opsx-archive  → 完成后归档，spec delta 合并进主 spec
```

- 显式命令触发，每步都有人确认
- 产出物是文件，可审查、可修改
- 流程在文件里跑，团队所有人都能看到

### 3.4 规格的形态

这是最大的区别。

**Superpowers 的"规格"是 skill 本身**：
- `tdd/SKILL.md` 规定了"先写测试"这条铁律——这就是规格
- `systematic-debugging/SKILL.md` 规定了四阶段调试流程——这就是规格
- 规格是**通用的、跨项目的**，不针对具体业务

**OpenSpec 的"规格"是 spec.md**：
- `spec.md` 里写的是**具体业务验收标准**：
  ```
  ### Requirement: 任务指令只给原材料，不替模型决定归档路径
  
  追史任务指令（userPrompt）SHALL 只提供原材料（当前 commit hash、
  commit 日期...），不得包含写死的归档目录、文件名...
  
  #### Scenario: 模型自主决定归档路径
  - WHEN 追史引擎向模型发送任务指令
  - THEN 任务指令中不出现 `归档路径：<固定目录>/<固定文件名>`
  ```
- 规格是**具体的、项目内的**，针对这次变更的业务需求
- 用 SHALL / SHALL NOT / WHEN / THEN 语法（类似 RFC 2119 + BDD）

### 3.5 与代码的关系

| | Superpowers | OpenSpec |
|---|---|---|
| **改代码** | 直接改，边改边测 | 按 tasks.md 逐项改 |
| **代码审查** | code-review skill 做 | spec.md 做验收基准 |
| **测试** | TDD 是核心——先写测试 | 测试是 tasks.md 里的一项任务 |
| **规格和代码的绑定** | 松耦合（skill 约束行为，不约束业务） | 紧耦合（spec.md 的 Requirement 对应代码行为） |

---

## 四、SDD（Spec-Driven Development） alignment

两者都号称 SDD，但"规格"指的东西不同：

```
Superpowers 的 SDD：
  Spec = 方法论规格（"怎么干活"的规格）
  驱动 = AI 加载 skill → 行为被规格约束 → 产出符合方法的代码
  
OpenSpec 的 SDD：
  Spec = 业务规格（"改什么"的规格）
  驱动 = 人写提案 → AI 按提案执行 → 产出符合规格的代码
```

**用一句话区分**：
- Superpowers：**"用规格驱动 AI 的行为"**（AI 怎么干活）
- OpenSpec：**"用规格驱动项目的变更"**（项目改成什么样）

---

## 五、实战对比：同一个任务两者怎么走

假设任务：**"追史插件的文章路径应该由模型自主决定，不要写死"**

### Superpowers 怎么走

1. **brainstorming** 自动触发 → AI 问你："当前路径怎么写死的？改成什么程度？要不要兼容旧路径？"
2. **planning** → AI 列计划：先看 `chase.ts` 的 userPrompt、再看 `history.ts` 的扫描逻辑、列修改步骤
3. **tdd** → AI 先写测试："给定模型把文章放到 `控制器层/` 目录，索引应仍能识别"
4. 写代码 → 改 `chase.ts`、`history.ts`
5. **quality-gates** → 跑测试、检查覆盖率
6. **code-review** → 审查改动

→ **产出：代码 + 测试**。没有提案文档，没有验收标准文档。

### OpenSpec 怎么走

1. `/opsx-propose` → AI 生成 `proposal.md`（为什么改、改什么、7 个改动点、影响范围）、`design.md`（JSON vs Markdown、对账策略、5 个设计决策）、`tasks.md`（10 组任务、55 个子任务）、`spec.md`（8 个 Requirement、17 个 Scenario）
2. 人审查 → 修改提案 → 确认开放问题的裁定
3. `/opsx-apply` → AI 按 `tasks.md` 逐项执行，每完成一项打勾
4. 全部完成 → `/opsx-archive` → spec delta 合并进主 spec

→ **产出：代码 + 测试 + 完整变更档案**。后人能从 `changes/chase-model-owned-paths/` 看到这次变更的完整故事。

---

## 六、关键差异总结表

| 维度 | Superpowers | OpenSpec |
|------|-------------|----------|
| **定位** | AI 行为约束（runtime） | 变更管理流程（workflow） |
| **形态** | 插件，14 个 skill | 文件约定 + CLI 命令 |
| **触发** | 自动（AI 匹配 skill） | 显式（人敲命令） |
| **规格内容** | 方法论（TDD、调试流程、审查清单） | 业务需求（Requirement + Scenario） |
| **产出物** | 代码 + 测试 | 代码 + 测试 + 变更档案 |
| **留存** | 不留文档 | 永久留档（changes/ 目录） |
| **跨项目复用** | ✅ skill 通用 | ❌ spec 针对具体项目 |
| **人的参与** | 低（AI 自动遵循） | 高（人审查提案、确认任务） |
| **适用阶段** | 执行阶段（写代码时） | 规划阶段（写代码前）+ 归档阶段（写代码后） |
| **TDD** | ✅ 核心铁律 | ❌ 不强制（tasks.md 里可能有测试任务） |
| **调试** | ✅ 专门 skill | ❌ 不涉及 |
| **安全审查** | ✅ 专门 skill | ❌ 不涉及 |
| **视觉验收** | ✅ 专门 skill | ❌ 不涉及 |
| **Git 工作流** | ✅ 专门 skill | ❌ 不涉及 |
| **断点续传** | ✅ handoff skill | ❌ 不涉及（但 tasks.md 的 checkbox 可追踪进度） |
| **子代理委派** | ✅ subagent-protocol | ❌ 不涉及 |
| **验收标准** | 隐式（测试通过） | 显式（spec.md 的 Scenario） |
| **设计决策记录** | ❌ 不记录 | ✅ design.md |
| **替代方案对比** | ❌ 不记录 | ✅ design.md 的"替代方案"段落 |

---

## 七、什么时候用哪个

### 只用 Superpowers 就够的场景

- 小改动、bug 修复、重构——不需要写提案
- 个人项目——不需要留变更档案给团队看
- 快速原型——先跑起来再说
- **你想让 AI 别再"上来就写代码"**——这是 Superpowers 最核心的价值

### 只用 OpenSpec 就够的场景

- 团队协作——需要提案、设计评审、验收标准
- 大改动——涉及多个模块、需要记录设计决策
- 合规要求——需要留档"为什么这么改"
- **你想让每次变更有完整的"故事"**——这是 OpenSpec 最核心的价值

### 两者一起用的场景（推荐）

```
OpenSpec 管"做什么" → Superpowers 管"怎么做"
     ↓                      ↓
proposal + design      brainstorming + planning
     ↓                      ↓
tasks.md               tdd（先写测试再改）
     ↓                      ↓
spec.md 验收           quality-gates + code-review
     ↓                      ↓
archive                git-workflow 提交
```

**具体流程**：
1. `/opsx-propose` 生成提案和任务清单
2. 人审查、确认
3. `/opsx-apply` 开始执行——此时 Superpowers 的 brainstorming 和 planning 自动介入，帮 AI 想清楚怎么改
4. AI 按 TDD 写代码（Superpowers 约束）
5. 写完跑 quality-gates（Superpowers 约束）
6. 对照 spec.md 验收（OpenSpec 约束）
7. `/opsx-archive` 归档

---

## 八、互补关系图

```
┌─────────────────────────────────────────────────┐
│                  一个变更的生命周期                   │
│                                                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │  提案阶段  │    │  执行阶段  │    │  归档阶段  │   │
│  │          │    │          │    │          │   │
│  │ OpenSpec │───→│ Superpowers │───→│ OpenSpec │   │
│  │          │    │          │    │          │   │
│  │ proposal │    │ brainstorm│    │ archive  │   │
│  │ design   │    │ planning │    │ spec合并  │   │
│  │ tasks    │    │ tdd      │    │          │   │
│  │ spec     │    │ debug    │    │          │   │
│  │          │    │ review   │    │          │   │
│  └──────────┘    └──────────┘    └──────────┘   │
│   "改什么"         "怎么改"        "改完了"        │
└─────────────────────────────────────────────────┘
```

---

## 九、一个表格看完两者所有 skill / 文件

| 功能 | Superpowers skill | OpenSpec 文件/命令 |
|------|-------------------|-------------------|
| 发散思考 | brainstorming | — |
| 创建计划 | planning | tasks.md |
| 记录提案 | — | proposal.md |
| 记录设计 | — | design.md |
| 定义验收标准 | — | spec.md（Requirement + Scenario） |
| TDD 执行 | tdd | — |
| 系统调试 | systematic-debugging | — |
| 代码审查 | code-review | — |
| 安全审查 | security-review | — |
| 视觉验收 | visual-qa | — |
| 质量门禁 | quality-gates | — |
| 清理 AI 坏味 | remove-ai-slops | — |
| Git 操作 | git-workflow | — |
| 上下文交接 | handoff | — |
| 子代理委派 | subagent-protocol | — |
| 创建新 skill | skill-creator | — |
| 启动变更 | — | /opsx-propose |
| 执行变更 | — | /opsx-apply |
| 归档变更 | — | /opsx-archive |
| 探索模式 | — | /opsx-explore |

---

## 十、结论

**Superpowers 和 OpenSpec 的关系不是"二选一"，而是"前后衔接"：**

- **OpenSpec 回答"做什么"**（What & Why）——提案、设计、验收标准
- **Superpowers 回答"怎么做"**（How）——TDD、调试、审查、质量门禁

如果你只能选一个：
- **你的问题是"AI 总是乱写代码"** → Superpowers
- **你的问题是"变更没有文档、团队不知道改了什么"** → OpenSpec
- **你的问题是"两个都有"** → 一起用，OpenSpec 管变更流程，Superpowers 管执行质量

> **作者注**：在我们的实际项目中（dsh-learn），OpenSpec 已经在用——`changes/chase-model-owned-paths/` 就是完整的 OpenSpec 变更实例。Superpowers 也在用——OpenCode 配置了 superpowers 插件。两者并行，互不冲突。
