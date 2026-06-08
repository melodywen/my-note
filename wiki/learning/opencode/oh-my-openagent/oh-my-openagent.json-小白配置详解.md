# oh-my-openagent.json 小白配置详解

> 适用人群：刚接触 OpenCode / Oh My OpenAgent，打开配置文件一脸懵的你。

---

## 一、这个文件是什么？

`oh-my-openagent.json` 是 **Oh My OpenAgent（简称 OmO）** 插件的配置文件。

先搞清楚几个概念：

| 概念 | 是什么 | 类比 |
|------|--------|------|
| **OpenCode** | 一个 AI 编程助手终端（类似 Claude Code） | 你的「终端 + AI 搭档」 |
| **Oh My OpenAgent** | OpenCode 的插件，把它从一个 AI 变成一个 AI **团队** | 从「单人作战」变成「团队协作」 |
| **oh-my-openagent.json** | 这个插件的配置文件 | 你给这个团队分配的「人员 + 武器」 |

简单说：**有了这个插件，你不再是和一个 AI 对话，而是和一个由多个 AI 特工组成的团队协作。**

---

## 二、你的配置文件长什么样？

```json
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
  "agents": {
    "hephaestus":    { "model": "opencode/gpt-5-nano" },
    "oracle":        { "model": "opencode/gpt-5-nano" },
    "librarian":     { "model": "opencode/gpt-5-nano" },
    "explore":       { "model": "opencode/gpt-5-nano" },
    "multimodal-looker": { "model": "opencode/gpt-5-nano" },
    "prometheus":    { "model": "opencode/gpt-5-nano" },
    "metis":         { "model": "opencode/gpt-5-nano" },
    "momus":         { "model": "opencode/gpt-5-nano" },
    "atlas":         { "model": "opencode/gpt-5-nano" },
    "sisyphus-junior": { "model": "opencode/gpt-5-nano" }
  },
  "categories": {
    "visual-engineering": { "model": "opencode/gpt-5-nano" },
    "ultrabrain":         { "model": "opencode/gpt-5-nano" },
    "deep":               { "model": "opencode/gpt-5-nano" },
    "artistry":           { "model": "opencode/gpt-5-nano" },
    "quick":              { "model": "opencode/gpt-5-nano" },
    "unspecified-low":    { "model": "opencode/gpt-5-nano" },
    "unspecified-high":   { "model": "opencode/gpt-5-nano" },
    "writing":            { "model": "opencode/gpt-5-nano" }
  }
}
```

当前你的配置中，所有 agent 和所有 category 都使用同一个模型：**`opencode/gpt-5-nano`**。

---

## 三、逐行解释

### 3.1 `$schema`

```json
"$schema": "https://raw.githubusercontent.com/..."
```

这一行**不需要你理解，也不需要你修改**。它告诉编辑器（如 VS Code）「这个 JSON 文件应该遵循什么格式」，这样你在编辑时会有自动补全和错误提示。可以理解为「格式说明书」的链接。

---

### 3.2 `agents` — 你的 AI 特工团队

`agents` 下面定义了 **10 个特工**。每个特工有自己擅长的领域。OmO 的核心思想是：**不同的活交给不同的 AI**，而不是一个 AI 干所有事。

#### 核心特工（最重要的 3 个）

| 特工 | 名字来源 | 干什么的 | 推荐模型 |
|------|----------|----------|----------|
| **Sisyphus** | 希腊神话：西西弗斯，每天推石头上山，永不停歇 | **总指挥**。制定计划、分配任务、驱动一切走向完成。他不会半途而废。 | Claude Opus / Kimi K2.6 |
| **Hephaestus** | 希腊神话：赫菲斯托斯，火神与工匠之神 | **主力干将**。你给他一个目标（而不是一步步指令），他自主探索代码库、研究方案、端到端执行。GPT 原生，被称为「合法的工匠」。 | GPT-5.5 |
| **Prometheus** | 希腊神话：普罗米修斯，盗火者 | **战略规划师**。动手之前先采访你，问清楚需求，识别范围，制定详细计划。 | Claude Opus / Kimi K2.6 |

> ⚠️ 你的配置里没有直接配 Sisyphus（主 orchestrator），而是配了 `sisyphus-junior`（Sisyphus 的轻量版，用于执行子任务）。

#### 咨询与搜索特工

| 特工 | 干什么的 | 什么时候用到 |
|------|----------|--------------|
| **Oracle** | 只读咨询专家。架构决策、复杂调试、安全问题 | 遇到不熟悉的代码模式、多系统权衡时 |
| **Librarian** | 文档和开源代码搜索 | 需要查最新 API 文档、找开源项目中的用法时 |
| **Explore** | 快速代码库搜索（grep） | 想知道「X 在哪里」「哪个文件做了 Y」时 |
| **Multimodal Looker** | 图片/截图/PDF 分析 | 需要分析设计稿、截图、图表时 |

#### 审查与执行特工

| 特工 | 干什么的 | 什么时候用到 |
|------|----------|--------------|
| **Metis** | 计划漏洞分析 | Prometheus 做完计划后，Metis 找遗漏 |
| **Momus** | 计划严格审查 | 按清晰度、可验证性、完整性标准评审计划 |
| **Atlas** | 执行指挥 | 把 Prometheus 的计划拆成任务，分配给子特工 |
| **Sisyphus-Junior** | 专注任务执行器 | 执行单个明确任务，不搞复杂规划 |

#### 每个 agent 可以配什么？

在配置中，每个 agent 不只是配 `model`，还能配很多其他选项（这些是你的配置中没有用到的，但你可以按需添加）：

```jsonc
"oracle": {
  "model": "openai/gpt-5.5",        // 使用什么模型（必填，最常用）
  "fallback_models": ["kimi/k2.6"],  // 模型挂了时的备用方案
  "temperature": 0.7,                // 创造性：0=保守 1=自由（0~2）
  "maxTokens": 8000,                 // 单次输出最大 token 数
  "thinking": {                      // 是否开启深度思考模式
    "type": "enabled",
    "budgetTokens": 4000
  },
  "reasoningEffort": "high",         // 推理力度：none/minimal/low/medium/high/xhigh/max
  "disable": false,                  // 设为 true 则禁用此 agent
  "description": "我的自定义描述",    // 覆盖 agent 的系统描述
  "permission": {                    // 权限控制
    "edit": "allow",                 // 编辑文件：ask(询问)/allow(允许)/deny(禁止)
    "bash": "ask",                   // 执行命令
    "webfetch": "allow",             // 网络请求
    "task": "allow"                  // 派发子任务
  }
}
```

---

### 3.3 `categories` — 任务分类

当你让 AI 做事时，OmO 首先判断你的任务属于哪一类，然后**自动选择该类对应的模型**。你不需要手动说「用 GPT 做这个」。

| 分类 | 含义 | 适合什么任务 | 官方推荐模型 |
|------|------|--------------|--------------|
| **visual-engineering** | 前端/UI/UX | 写界面、调样式、做动画 | Gemini Pro |
| **ultrabrain** | 高难度逻辑 | 复杂架构决策、烧脑问题 | GPT-5.5 xhigh |
| **deep** | 深度自主研究 | 需要自己探索的大任务 | GPT-5.5 |
| **artistry** | 创造性工作 | 设计感、创意方案 | Gemini Pro |
| **quick** | 快速小任务 | 改个拼写、修个类型错误 | GPT-5.4 Mini |
| **unspecified-low** | 未分类低难度 | 不重要的杂活 | 最便宜的模型 |
| **unspecified-high** | 未分类高难度 | 没被分类到但很重要的事 | Claude Opus |
| **writing** | 文档写作 | 写 README、注释、技术文档 | Claude Opus |

**关键理解**：categories 和 agents 的关系是：
- **Agent（特工）** = 谁来做（角色）
- **Category（分类）** = 做什么类型的活 → 决定用什么模型

当 Sisyphus 派任务给子特工时，他说的是「这是一个 `deep` 类型的任务」，然后系统自动选择 `deep` 对应的模型来执行。

---

## 四、`opencode/gpt-5-nano` 是什么意思？

模型名称格式为：**`提供商/模型名`**

- `opencode` = 提供商（OpenCode 平台内置的模型供应商）
- `gpt-5-nano` = 模型名称（GPT-5 的 nano 版本，轻量快速）

常见的模型名称举例：

| 完整名称 | 提供商 | 模型 | 特点 |
|----------|--------|------|------|
| `opencode/gpt-5-nano` | OpenCode | GPT-5 Nano | 轻量、快速、便宜 |
| `openai/gpt-5.5` | OpenAI | GPT-5.5 | 深度编码能力极强 |
| `anthropic/claude-opus-4-7` | Anthropic | Claude Opus 4.7 | 指令遵循最好 |
| `google/gemini-3.1-pro` | Google | Gemini 3.1 Pro | 前端/视觉任务出色 |
| `kimi-for-coding/k2p5` | Kimi | K2.5 | Claude 的替代品，性价比高 |

---

## 五、你的配置意味着什么？

你目前的配置：**所有 agent 和所有 category 都统一用 `opencode/gpt-5-nano`**。

这意味着：
- ✅ **简单**：不需要多想，全部用同一个模型
- ✅ **快速**：gpt-5-nano 是轻量模型，响应快
- ❌ **没有发挥 OmO 的真正优势**：OmO 的精髓是「不同任务用不同模型」，比如前端用 Gemini、架构用 GPT-5.5、小活用便宜模型

这有点像：你有一个团队，但让所有人都用同一把工具。能用，但不是最优。

---

## 六、如果你想进阶配置

### 场景一：你有多个模型供应商的 API Key

```jsonc
{
  "agents": {
    "oracle": {
      "model": "openai/gpt-5.5",
      "variant": "high"  // high = 更强的推理变体
    },
    "librarian": {
      "model": "google/gemini-3-flash"  // 搜索用便宜的
    },
    "explore": {
      "model": "github-copilot/grok-code-fast-1"  // grep 用最快的
    }
  },
  "categories": {
    "visual-engineering": {
      "model": "google/gemini-3.1-pro"  // 前端交给 Gemini
    },
    "ultrabrain": {
      "model": "openai/gpt-5.5",
      "variant": "xhigh"  // 烧脑问题用最强推理
    },
    "quick": {
      "model": "openai/gpt-5.4-mini"  // 小活用便宜的
    }
  }
}
```

### 场景二：你只用 OpenCode 平台

那就保持现状。`gpt-5-nano` 是一个不错的选择，够用且不复杂。

### 场景三：你想禁用某些特工

```jsonc
{
  "disabled_agents": ["multimodal-looker", "mommus"],
  "disabled_skills": ["playwright", "agent-browser"],
  "disabled_commands": ["ralph-loop"]
}
```

---

## 七、常用术语速查表

| 术语 | 大白话解释 |
|------|------------|
| **Model（模型）** | AI 的大脑。不同模型擅长不同的事。 |
| **Agent（特工）** | 一个有特定角色和职责的 AI。比如 Oracle 是架构顾问。 |
| **Category（分类）** | 任务类型标签。系统根据分类自动选模型。 |
| **Orchestration（编排）** | 让多个 AI 特工协作完成一个任务。 |
| **Variant（变体）** | 同一个模型的不同「档位」，如 high/xhigh/max 控制推理深度。 |
| **Fallback（回退）** | 首选模型不可用时的备选方案。 |
| **Token** | AI 处理文本的最小单位。约 1 个中文字 ≈ 2 token，1 个英文单词 ≈ 1.3 token。 |
| **Schema** | JSON 的格式规范。告诉编辑器哪些字段合法。 |

---

## 八、总结

1. **`oh-my-openagent.json`** 是 OmO 插件的配置，定义你的 AI 团队和任务分类规则
2. **`agents`** 是 10 个 AI 特工，各有所长
3. **`categories`** 是 8 种任务类型，决定用什么模型
4. 你目前全用 `opencode/gpt-5-nano`，简单够用，但没发挥多模型协作的优势
5. 如果想进阶，可以给不同 agent/category 配不同模型

---

> **下一步**：在终端里输入 `ultrawork`，体验一下这个 AI 团队是怎么协作的。

---

*写于 OpenCode 学习笔记 · oh-my-openagent 专题*
