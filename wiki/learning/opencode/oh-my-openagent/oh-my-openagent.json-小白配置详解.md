# oh-my-openagent.json 小白配置详解

> 适用人群：刚接触 OpenCode / Oh My OpenAgent，打开配置文件一脸懵的你。

---

## 一、这个文件是什么？

| 概念 | 是什么 | 类比 |
|------|--------|------|
| **OpenCode** | AI 编程助手终端（类似 Claude Code） | 你的「终端 + AI 搭档」 |
| **Oh My OpenAgent** | OpenCode 插件，把它从一个 AI 变成一个 AI **团队** | 从「单人作战」变成「团队协作」 |
| **oh-my-openagent.json** | 这个插件的配置文件 | 你给这个团队分配的「人员 + 武器」 |

简单说：**有了这个插件，你不再是和一个 AI 对话，而是和一个由多个 AI 特工组成的团队协作。**

---

## 二、配置文件结构速览

| 顶层字段 | 作用 | 里面有什么 |
|----------|------|------------|
| `$schema` | 格式说明书链接，不用管 | 一个 URL |
| `agents` | 定义 11 个 AI 特工各自用什么模型 | 特工名 → 模型配置 |
| `categories` | 定义 8 种任务类型各自用什么模型 | 分类名 → 模型配置 |

---

## 三、`$schema`

```json
"$schema": "https://raw.githubusercontent.com/..."
```

**不需要你理解，也不需要你修改。** 它告诉编辑器（如 VS Code）「这个 JSON 文件应该遵循什么格式」，这样你在编辑时会有自动补全和错误提示。

---

## 四、`agents` — 你的 11 个 AI 特工

OmO 的核心思想：**不同的活交给不同的 AI**，而不是一个 AI 干所有事。

### 4.1 特工全景表

> 此表同时包含每个特工的配置策略，与 [7.2 配置策略一览](#72-配置策略一览) 互为补充。特工详情见下表，模型分配见 7.2。

### 4.2 按角色分组

| 分组 | 成员 | 一句话 |
|------|------|--------|
| 🧠 指挥层 | Sisyphus、Prometheus | 决定「做什么」 |
| 🔨 执行层 | Sisyphus-Junior、Hephaestus | 负责「动手干」 |
| 📋 协调层 | Atlas、Metis、Momus | 保证「干得对」 |
| 🔍 搜索层 | Explore、Librarian | 提供「情报」 |
| 👁️ 视觉层 | Multimodal Looker | 处理「图像」 |
| 💬 咨询层 | Oracle | 提供「建议」 |

### 4.3 每个 agent 可配置的字段

| 字段 | 类型 | 作用 | 常用程度 |
|------|------|------|----------|
| `model` | string | 首选模型（必填） | ⭐⭐⭐ |
| `fallback_models` | array | 首选挂了依次尝试的备用模型 | ⭐⭐⭐ |
| `temperature` | 0~2 | 创造性：0=保守 1=自由 | ⭐ |
| `maxTokens` | number | 单次输出最大 token 数 | ⭐ |
| `thinking` | object | 深度思考模式开关和预算 | ⭐ |
| `reasoningEffort` | string | 推理力度：none/minimal/low/medium/high/xhigh/max | ⭐ |
| `disable` | boolean | 设为 true 禁用此 agent | ⭐ |
| `permission` | object | 权限控制（编辑/命令/网络/派发） | ⭐ |

---

## 五、`categories` — 8 种任务分类

当你让 AI 做事时，OmO 先判断任务类型，再自动选择对应模型。你不需要手动指定。

### 5.1 分类全景表

| 分类 | 含义 | 适合任务 | 调用频率 | 关键程度 |
|------|------|----------|----------|----------|
| **ultrabrain** | 高难度逻辑 | 复杂架构决策、烧脑问题 | 低 | ⭐⭐⭐ |
| **deep** | 深度自主研究 | 需要自己探索的大任务 | 低 | ⭐⭐⭐ |
| **visual-engineering** | 前端/UI/UX | 写界面、调样式、做动画 | 中 | ⭐⭐ |
| **artistry** | 创造性工作 | 设计感、创意方案 | 低 | ⭐⭐ |
| **writing** | 文档写作 | README、注释、技术文档 | 低 | ⭐ |
| **quick** | 快速小任务 | 改拼写、修类型错误 | 高 | ⭐ |
| **unspecified-low** | 未分类低难度 | 不重要的杂活 | 中 | ⭐ |
| **unspecified-high** | 未分类高难度 | 没被分类但重要的事 | 低 | ⭐ |

### 5.2 Agent 与 Category 的关系

| 概念 | 回答的问题 | 举例 |
|------|------------|------|
| **Agent（特工）** | **谁**来做？ | Sisyphus-Junior |
| **Category（分类）** | 做**什么类型**的活？决定用**什么模型** | `deep` → Claude Sonnet |

当 Sisyphus 派任务时，他说「这是一个 `deep` 类型的任务」，系统自动选 `deep` 对应的模型，交给 Sisyphus-Junior 执行。

---

## 六、模型名称格式

格式：**`提供商/模型ID`**

### 6.1 CodeBuddy 可用模型速查（按价格分档）

| 档次 | 模型 ID | 倍率 | 特点 |
|------|---------|------|------|
| 🟢 极便宜 | `deepseek-v4-flash-ioa` | 0.05x | 搜索专用，最快最省 |
| 🟢 极便宜 | `deepseek-v4-pro-ioa` | 0.13x | 性价比之王，综合能力强 |
| 🟢 极便宜 | `deepseek-v3-2-volc-ioa` | 0.15x | DeepSeek 上一代 |
| 🟢 极便宜 | `gpt-5.1-codex-mini` | 0.18x | GPT 最便宜款 |
| 🟢 极便宜 | `minimax-m2.5-ioa` | 0.13x | MiniMax 入门 |
| 🟢 极便宜 | `minimax-m2.7-ioa` | 0.19x | MiniMax 升级 |
| 🟢 极便宜 | `glm-4.7-ioa` | 0.23x | GLM 入门 |
| 🟡 中等 | `kimi-k2.6-ioa` | 0.50x | 指令遵循好，Claude 平替 |
| 🟡 中等 | `claude-haiku-4.5` | 0.67x | Claude 最便宜款 |
| 🟡 中等 | `glm-5.0-ioa` | 0.68x | GLM 中档 |
| 🟡 中等 | `glm-5v-turbo-ioa` | 0.81x | GLM 视觉版 |
| 🟡 中等 | `glm-5.1-ioa` | 0.90x | GLM 旗舰，Claude-like |
| 🟡 中等 | `gpt-5.1-codex` | 0.90x | GPT 代码专用 |
| 🟡 中等 | `gemini-2.5-pro` | 0.90x | Gemini 上代旗舰 |
| 🟡 中等 | `gemini-3.5-flash` | 0.99x | Gemini 快速版 |
| 🟠 较贵 | `gpt-5.3-codex` | 1.25x | GPT 代码增强 |
| 🟠 较贵 | `gemini-3.1-pro` | 1.32x | 前端/视觉王者 |
| 🟠 较贵 | `gpt-5.4` | 1.65x | GPT 次旗舰 |
| 🔴 昂贵 | `claude-sonnet-4.6` | 2.00x | 指令遵循最强之一 |
| 🔴 昂贵 | `gpt-5.5` | 3.31x | GPT 最强 |
| 🔴 昂贵 | `claude-opus-4.6` | 3.33x | Claude 上代旗舰 |
| 🔴 昂贵 | `claude-opus-4.7` | 3.33x | Claude 旗舰 |
| 🔴 昂贵 | `claude-opus-4.8` | 3.33x | Claude 最新旗舰 |

> 带 `-1m` 后缀的版本（如 `claude-sonnet-4.6-1m`）上下文窗口更大（1M），价格相同。

### 6.2 主要模型家族对比

| 家族 | 代表模型 | 核心优势 | 适合场景 |
|------|----------|----------|----------|
| **Claude** | sonnet-4.6, opus-4.8 | 指令遵循精准、结构化输出强 | 调度、规划、深度思考 |
| **GPT** | gpt-5.4, gpt-5.5 | 深度推理、代码架构 | 架构设计、复杂调试 |
| **Kimi** | kimi-k2.6 | 指令遵循接近 Claude，价格 1/4 | Claude 平替，主力执行 |
| **DeepSeek** | v4-pro, v4-flash | 极致性价比 | 搜索、小活、辅助任务 |
| **Gemini** | gemini-3.1-pro | 前端/视觉表现最佳 | 写 UI、看图 |

---

## 七、实战：最终配置解析

以下是我们经过多轮讨论确定的配置，遵循 **「关键岗位不省钱，次要岗位省到底」** 原则。

### 7.1 完整配置

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
  "agents": {
    "sisyphus": {
      "model": "codebuddy/claude-sonnet-4.6",        // 总指挥，不省钱
      "fallback_models": ["codebuddy/kimi-k2.6-ioa"]
    },
    "hephaestus": {
      "model": "codebuddy/gpt-5.4",                  // GPT 原生，GPT 不能丢
      "fallback_models": ["codebuddy/gpt-5.5"]
    },
    "oracle": {
      "model": "codebuddy/gpt-5.4",                  // 架构咨询，GPT 擅长
      "fallback_models": ["codebuddy/claude-sonnet-4.6"]
    },
    "librarian": {
      "model": "codebuddy/deepseek-v4-flash-ioa",    // 文档搜索，最便宜
      "fallback_models": ["codebuddy/deepseek-v4-pro-ioa"]
    },
    "explore": {
      "model": "codebuddy/deepseek-v4-flash-ioa",    // 代码搜索，最便宜
      "fallback_models": ["codebuddy/deepseek-v4-pro-ioa"]
    },
    "multimodal-looker": {
      "model": "codebuddy/gemini-3.1-pro",           // 看图，Gemini 最强
      "fallback_models": ["codebuddy/gpt-5.4"]
    },
    "prometheus": {
      "model": "codebuddy/claude-sonnet-4.6",        // 规划，不省钱
      "fallback_models": ["codebuddy/kimi-k2.6-ioa"]
    },
    "metis": {
      "model": "codebuddy/deepseek-v4-pro-ioa",      // 漏洞分析，省钱
      "fallback_models": ["codebuddy/deepseek-v4-flash-ioa"]
    },
    "momus": {
      "model": "codebuddy/deepseek-v4-pro-ioa",      // 严格审查，省钱
      "fallback_models": ["codebuddy/deepseek-v4-flash-ioa"]
    },
    "atlas": {
      "model": "codebuddy/deepseek-v4-pro-ioa",      // 执行指挥，省钱
      "fallback_models": ["codebuddy/kimi-k2.6-ioa"]
    },
    "sisyphus-junior": {
      "model": "codebuddy/kimi-k2.6-ioa",            // 主力写代码，质量成本平衡
      "fallback_models": ["codebuddy/claude-sonnet-4.6"]
    }
  },
  "categories": {
    "visual-engineering": {
      "model": "codebuddy/deepseek-v4-pro-ioa",      // 前端，先省不行再升
      "fallback_models": ["codebuddy/gemini-3.1-pro"]
    },
    "ultrabrain": {
      "model": "codebuddy/claude-sonnet-4.6",        // 深度思考，不省钱
      "fallback_models": ["codebuddy/gpt-5.4"]
    },
    "deep": {
      "model": "codebuddy/claude-sonnet-4.6",        // 深度研究，不省钱
      "fallback_models": ["codebuddy/gpt-5.4"]
    },
    "artistry": {
      "model": "codebuddy/deepseek-v4-pro-ioa",      // 设计，先省
      "fallback_models": ["codebuddy/gemini-3.1-pro"]
    },
    "quick": {
      "model": "codebuddy/deepseek-v4-flash-ioa",    // 小活，最便宜
      "fallback_models": ["codebuddy/deepseek-v4-pro-ioa"]
    },
    "unspecified-low": {
      "model": "codebuddy/deepseek-v4-flash-ioa",    // 杂活，最便宜
      "fallback_models": ["codebuddy/deepseek-v4-pro-ioa"]
    },
    "unspecified-high": {
      "model": "codebuddy/deepseek-v4-pro-ioa",      // 重要未分类，省钱
      "fallback_models": ["codebuddy/kimi-k2.6-ioa"]
    },
    "writing": {
      "model": "codebuddy/kimi-k2.6-ioa",            // 写作，Kimi 文笔好
      "fallback_models": ["codebuddy/deepseek-v4-pro-ioa"]
    }
  }
}
```

### 7.2 配置策略一览

| 层级 | 原则 | Agent / Category | 名字来源 | 角色 | 调用频率 | 模型 | 倍率 |
|------|------|------------------|----------|------|----------|------|------|
| 🔴 关键 | 不省钱 | sisyphus | 西西弗斯，永不停歇 | 总指挥：理解意图、分解任务、派发子特工 | 极高 | claude-sonnet-4.6 | 2.00x |
| 🔴 关键 | 不省钱 | prometheus | 普罗米修斯，盗火者 | 战略规划师：采访用户、制定详细计划 | 低 | claude-sonnet-4.6 | 2.00x |
| 🔴 关键 | 不省钱 | ultrabrain | — | 高难度逻辑：复杂架构决策、烧脑问题 | 低 | claude-sonnet-4.6 | 2.00x |
| 🔴 关键 | 不省钱 | deep | — | 深度自主研究：需要自己探索的大任务 | 低 | claude-sonnet-4.6 | 2.00x |
| 🔴 关键 | 质量成本平衡 | sisyphus-junior | Sisyphus 轻量版 | 主力执行器：实际写代码、修 bug、写测试 | 高 | kimi-k2.6 | 0.50x |
| 🟡 中等 | 适度投入 | hephaestus | 赫菲斯托斯，工匠之神 | GPT 原生深度工作者：自主探索执行 | 低 | gpt-5.4 | 1.65x |
| 🟡 中等 | 适度投入 | oracle | 神谕，智者 | 只读架构顾问：提供建议不改代码 | 极低 | gpt-5.4 | 1.65x |
| 🟢 次要 | 尽量省钱 | atlas | 阿特拉斯，擎天巨神 | 执行指挥：拆计划、派任务、收结果 | 极低 | deepseek-v4-pro | 0.13x |
| 🟢 次要 | 尽量省钱 | metis | 墨提斯，智慧女神 | 计划漏洞分析：找遗漏和模糊点 | 极低 | deepseek-v4-pro | 0.13x |
| 🟢 次要 | 尽量省钱 | momus | 摩墨斯，嘲讽之神 | 计划严格审查：按标准打分 | 极低 | deepseek-v4-pro | 0.13x |
| 🟢 次要 | 尽量省钱 | visual-engineering | — | 前端/UI/UX：写界面、调样式、做动画 | 中 | deepseek-v4-pro | 0.13x |
| 🟢 次要 | 尽量省钱 | artistry | — | 创造性工作：设计感、创意方案 | 低 | deepseek-v4-pro | 0.13x |
| 🟢 次要 | 尽量省钱 | writing | — | 文档写作：README、注释、技术文档 | 低 | kimi-k2.6 | 0.50x |
| 🟢 次要 | 尽量省钱 | explore | 探索者 | 代码库搜索（grep）：找代码位置 | 高 | deepseek-v4-flash | 0.05x |
| 🟢 次要 | 尽量省钱 | librarian | 图书管理员 | 文档和开源代码搜索 | 中 | deepseek-v4-flash | 0.05x |
| 🟢 次要 | 尽量省钱 | quick | — | 快速小任务：改拼写、修类型错误 | 高 | deepseek-v4-flash | 0.05x |
| 🟢 次要 | 尽量省钱 | unspecified-low | — | 未分类低难度：不重要的杂活 | 中 | deepseek-v4-flash | 0.05x |
| 🟢 次要 | 尽量省钱 | unspecified-high | — | 未分类高难度：没被分类但重要的事 | 低 | deepseek-v4-pro | 0.13x |
| 👁️ 特殊 | 看图唯一选择 | multimodal-looker | 多模态观察者 | 图片/截图/PDF 分析 | 极低 | gemini-3.1-pro | 1.32x |

### 7.3 模型使用分布

| 模型 | 用在哪些位置 | 倍率 | 角色 |
|------|-------------|------|------|
| **claude-sonnet-4.6** | sisyphus, prometheus, ultrabrain, deep | 2.00x | 质量关口，守住关键决策 |
| **gpt-5.4** | hephaestus, oracle | 1.65x | GPT 原生场景 + 架构推理 |
| **kimi-k2.6** | sisyphus-junior, writing | 0.50x | 主力执行 + 文档写作 |
| **deepseek-v4-pro** | atlas, metis, momus, visual, artistry, unspec-high | 0.13x | 辅助任务批量省钱 |
| **deepseek-v4-flash** | explore, librarian, quick, unspec-low | 0.05x | 搜索和小活极致省钱 |
| **gemini-3.1-pro** | multimodal-looker | 1.32x | 看图专用 |

### 7.4 Fallback 链设计

| 位置 | 首选 → 备选 | 逻辑 |
|------|------------|------|
| sisyphus | sonnet → kimi | Sonnet 挂了用 Kimi，同为指令遵循好 |
| prometheus | sonnet → kimi | 同上 |
| hephaestus | gpt-5.4 → gpt-5.5 | GPT 升级链路，保持血统 |
| oracle | gpt-5.4 → sonnet | GPT 挂了换 Claude |
| sisyphus-junior | kimi → sonnet | Kimi 不够时自动升级到最强 |
| ultrabrain/deep | sonnet → gpt-5.4 | Claude 挂了换 GPT 深度推理 |
| visual/artistry | deepseek → gemini | 省钱优先，效果不好自动升 Gemini |
| 其余 | deepseek 内部互备 | flash↔pro 互相兜底 |

---

## 八、`fallback_models` 是什么？

| 场景 | 行为 |
|------|------|
| 首选模型正常 | 用首选，不理 fallback |
| 首选挂了/限流/超时 | 按顺序尝试 fallback 列表里的模型 |
| 全部不可用 | 报错，告诉你模型都不可用 |

```jsonc
"sisyphus": {
  "model": "codebuddy/claude-sonnet-4.6",       // ① 先试这个
  "fallback_models": ["codebuddy/kimi-k2.6-ioa"] // ② 挂了试这个
}
```

---

## 九、常用术语速查表

| 术语 | 大白话解释 |
|------|------------|
| **Model（模型）** | AI 的大脑。不同模型擅长不同的事。 |
| **Agent（特工）** | 有特定角色和职责的 AI。比如 Oracle 是架构顾问。 |
| **Category（分类）** | 任务类型标签。系统根据分类自动选模型。 |
| **Orchestration（编排）** | 让多个 AI 特工协作完成一个任务。 |
| **Fallback（回退）** | 首选模型不可用时的备选方案。 |
| **Token** | AI 处理文本的最小单位。约 1 个中文字 ≈ 2 token。 |
| **Schema** | JSON 的格式规范。告诉编辑器哪些字段合法。 |
| **Credits（积分）** | CodeBuddy 的计费单位，不同模型消耗不同倍率。 |

---

## 十、总结

| 要点 | 说明 |
|------|------|
| 文件作用 | 给 OmO 的 11 个特工和 8 种任务分配模型 |
| 核心原则 | 关键岗位不省钱，次要岗位省到底 |
| 质量关口 | Sisyphus/Prometheus/深度思考 → Claude Sonnet (2.00x) |
| GPT 阵地 | Hephaestus/Oracle → GPT-5.4 (1.65x) |
| 主力省钱 | Sisyphus-Junior → Kimi K2.6 (0.50x) |
| 其余极致省 | 搜索/小活/辅助 → DeepSeek (0.05-0.13x) |

---

> **下一步**：在终端里输入 `ultrawork`，体验一下这个 AI 团队是怎么协作的。

---

*写于 OpenCode 学习笔记 · oh-my-openagent 专题*
