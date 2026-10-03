---
type: concept
status: developing
area: growth
title: "新手教程——从零上手你的 AI 工具链"
created: 2026-07-11
updated: 2026-07-11
tags:
  - learning
  - 新手教程
  - Obsidian
  - opencode
  - oh-my-openagent
  - dsh
  - 大模型微调
related:
  - "[[Obsidian 命令与技能完全指南]]"
  - "[[Oh-My-OpenAgent-实战搭配使用指南]]"
  - "[[oh-my-openagent.json-小白配置详解]]"
  - "[[00 dsh 概述]]"
  - "[[01 大模型微调概述]]"
---

# 新手教程——从零上手你的 AI 工具链

> 本文是 `learning/` 目录下所有笔记的**总入口**。你手上有四套工具，本文按「**这是什么 → 怎么装 → 怎么用**」的顺序，带你从零跑通每一步。
>
> 四套工具各管一件事，互不冲突，可以按任意顺序学：
>
> | 工具 | 一句话 | 你拿它做什么 |
> |------|--------|------------|
> | **Obsidian + claude-obsidian** | 会自我增长的知识库 | 把学过的东西存下来、查出来、越长越厚 |
> | **OpenCode + Oh-My-OpenAgent** | AI 编程特工团队 | 让一群 AI 帮你写代码、改 bug、做重构 |
> | **DSH（DeepSeek Harness）** | 一切皆插件的 Agent 框架 | 给大模型穿上"工作服"让它能干活 |
> | **大模型微调** | 改模型参数让它在你的领域更强 | 把通用模型变成你的专属模型 |

---

## 第一部分：Obsidian + claude-obsidian——你的"第二大脑"

### 1.1 这是什么

**Obsidian** 是一个本地 Markdown 笔记软件。你打开它就像打开一个文件夹，每个笔记就是一个 `.md` 文件，笔记之间用 `[[双链]]` 互相关联。

**claude-obsidian** 是装在 OpenCode 里的 AI 插件（v1.9.0，14 个技能），它把你的 Obsidian 笔记库变成一个**会自我增长的知识库**——AI 不只回答问题，还会把答案写回知识库，越用越厚。

> 核心理念：**Wiki 才是产品，聊天只是接口。** 每次你问 AI 一个问题，好的答案会被自动存进笔记库，下次不用再问。

### 1.2 怎么装

1. **装 Obsidian**：去 [obsidian.md](https://obsidian.md) 下载安装。
2. **建一个 Vault**：打开 Obsidian → 新建 Vault → 选一个文件夹（比如 `~/ai-work/my-note`，就是你现在的笔记库）。
3. **claude-obsidian 插件**：已经装在 OpenCode 里了（`~/.config/opencode/skills/obsidian/`），不用额外操作。

### 1.3 怎么用——记住一个快捷键

> **`Cmd+P`（Mac）/ `Ctrl+P`（Win）** 打开命令面板。Obsidian 里几乎所有功能都能在这里搜到。不用记几百个快捷键，记住这一个就够了。

### 1.4 日常用法——三个核心命令

| 你想做什么 | 输入什么 | 背后发生的事 |
|-----------|---------|------------|
| **查知识库** | `什么是 LoRA？` 或 `query: LoRA` | AI 先读热缓存 `hot.md` → 再查目录 `index.md` → 打开相关页面 → 带引用回答 |
| **存对话** | `/save` 或 `存一下` | AI 自动判定笔记类型 → 生成 frontmatter → 归档到正确目录 → 更新目录和日志 |
| **摄取素材** | `ingest this url` 或 `把这个加进 wiki` | 抓网页内容 → 抽取概念和实体 → 创建/更新多个 wiki 页面 |

### 1.5 推荐工作流——知识增长循环

```
1. 建库（一次性）        → /wiki set up（你已经建好了，跳过）
2. 进料（看到好文章）    → defuddle 清洗 → wiki-ingest 摄取建页
3. 深挖（对某主题不熟）  → /autoresearch [主题] 自动联网研究并归档
4. 取用（随时查）        → wiki-query（三档：quick / standard / deep）
5. 沉淀（聊出好结论）    → /save 存回库
6. 维护（每周一次）      → wiki-lint 体检（查孤儿页、死链…）
```

### 1.6 三档查询控制成本

| 模式 | 触发方式 | Token 消耗 | 适用 |
|------|---------|-----------|------|
| Quick | `query quick:` 或简单事实题 | ~1,500 | "X 是什么"、查日期 |
| Standard（默认） | 不加标记 | ~3,000 | 大多数问题 |
| Deep | `query deep:` 或"全面""详尽" | ~8,000+ | 跨页综合、对比 |

### 1.7 新手第一步

打开 OpenCode，输入：

```
什么是 LoRA 微调？
```

AI 会从你的知识库里找到 `[[03 LoRA 与 QLoRA]]` 页面，带引用回答你。这就是 `wiki-query` 在工作。

---

## 第二部分：OpenCode + Oh-My-OpenAgent——AI 编程特工团队

### 2.1 这是什么

**OpenCode** 是一个终端里的 AI 编程助手（类似 Claude Code）。你在终端里和它说话，它帮你写代码、改 bug、做重构。

**Oh-My-OpenAgent（OmO）** 是 OpenCode 的插件，把"一个 AI"变成"一个 AI 团队"——11 个特工各司其职，自动协作。

### 2.2 怎么装

已经装好了。配置文件在 `~/.config/opencode/opencode.jsonc`，OmO 配置在 `oh-my-openagent.json`。

### 2.3 11 个特工速览

不用全记，按角色分 6 组：

| 分组 | 成员 | 干什么 |
|------|------|--------|
| 🧠 指挥层 | **Sisyphus**、**Prometheus** | 理解意图、制定计划 |
| 🔨 执行层 | **Sisyphus-Junior**、**Hephaestus** | 实际写代码 |
| 📋 协调层 | **Atlas**、**Metis**、**Momus** | 拆任务、查漏洞、审查计划 |
| 🔍 搜索层 | **Explore**、**Librarian** | 搜代码、查文档 |
| 👁️ 视觉层 | **Multimodal-Looker** | 看图片/截图/PDF |
| 💬 咨询层 | **Oracle** | 只读架构顾问，给建议不改代码 |

### 2.4 三种工作模式——日常使用全部决策逻辑

```
你有一个任务
    │
    ├─ 简单小活？ → 直接说话，不用任何特殊操作（80%）
    │
    ├─ 复杂但不想废话？ → 输入 "ulw" 或 "ultrawork"（15%）
    │
    └─ 复杂且需要精确控制？ → @plan 规划 → /start-work 执行（5%）
```

### 2.5 模式一：直接对话（日常 80%）

适合：改变量名、修类型错误、问"这个函数是干什么的"、加一行日志。

直接在终端说话就行：

```
帮我把 src/utils/format.ts 里的 formatDate 函数名改成 formatISODate
```

OmO 的 **IntentGate（意图门）** 会自动分析你的意图，路由到合适的 agent。你不用手动指定。

### 2.6 模式二：ultrawork（懒人神器，15%）

适合：任务复杂但不想写长篇需求、"你帮我搞定"类型的活。

```
ulw 给 API 接口加上 JWT 认证
```

或完整版：

```
ultrawork 修复所有失败的测试
```

**背后发生的事**：
1. Sisyphus（总指挥）接手
2. 派 Explore 搜代码库找相关文件
3. 派 Librarian 查最佳实践文档
4. 派 Sisyphus-Junior 执行修改
5. 用 LSP 检查有没有报错
6. **循环直到完成**（有 Todo Enforcer + Ralph Loop 保证不停）

### 2.7 模式三：@plan → /start-work（精确控制流，5%）

适合：大型重构、新功能开发、架构变更、跨天的大任务。

**第一步：启动规划**
```
@plan 重构用户认证系统，把 session 改成 JWT
```

**第二步：接受采访**——Prometheus 不会直接动手，它会像真正的工程师一样采访你：
```
Prometheus：JWT 过期时间设多长？
你：access token 15 分钟，refresh token 7 天

Prometheus：现有 session 表要保留吗？
你：保留，做平滑迁移
```

**第三步：计划审查**——Metis 检查漏洞，Momus 按标准打分，计划写进 `.omo/plans/`。

**第四步：开始执行**
```
/start-work
```
Atlas 读取计划 → 逐个派给 Sisyphus-Junior 执行 → 每完成一个任务提取经验传给下一个。

**第五步：跨天继续**——明天打开 OpenCode，再输 `/start-work`，Atlas 会从 `.omo/boulder.json` 恢复进度，**不需要重新解释上下文**。

### 2.8 什么时候用 Oracle

Oracle 是**只读**顾问，不改代码，只给建议。适合架构决策：

```
@oracle 我打算用 Redis 做缓存层，有什么坑需要注意？
```

### 2.9 配置模型——「关键岗位不省钱，次要岗位省到底」

编辑 `oh-my-openagent.json`：

| 层级 | 原则 | 用什么模型 | 倍率 |
|------|------|-----------|------|
| 关键（Sisyphus/Prometheus/深度思考） | 不省钱 | claude-sonnet-4.6 | 2.00x |
| GPT 阵地（Hephaestus/Oracle） | 适度投入 | gpt-5.4 | 1.65x |
| 主力执行（Sisyphus-Junior） | 质量成本平衡 | kimi-k2.6 | 0.50x |
| 搜索/小活（Explore/Librarian/quick） | 极致省钱 | deepseek-v4-flash | 0.05x |

### 2.10 新手第一步

打开 OpenCode，输入：

```
ulw 帮我在 learning 目录下创建一个测试文件
```

观察 Sisyphus 如何自动分解任务、派发子特工、循环执行直到完成。

---

## 第三部分：DSH（DeepSeek Harness）——一切皆插件的 Agent 框架

### 3.1 这是什么

**DSH** 是 DeepSeek 开源的 Agent Harness（智能体框架），核心理念：**"Everything is a Plugin"（一切皆插件）**。

大模型本身只会聊天——你问它答。DSH 给模型穿上"工作服"，让它能读写文件、执行命令、搜索网页、委派子 Agent……从"只会聊天"变成"能做事"。

### 3.2 怎么装

**方式一：npx 临时运行（推荐初次体验）**
```bash
npx @deepseek-ai/dsh web
```
打开浏览器 `http://127.0.0.1:3080` 就能用。

**方式二：全局安装（推荐日常使用）**
```bash
npm install -g @deepseek-ai/dsh
dsh web
```

### 3.3 四个核心概念——用"搭积木"理解

| 概念 | 一句话 | 比喻 |
|------|--------|------|
| **Plugin** | 最小功能单位（调模型、跑命令、读文件…各是一个插件） | 一块积木 |
| **Bundle** | 一组配套插件的分发包 | 一袋积木 |
| **Profile** | 你搭出来的最终配置 | 搭好的作品 |
| **Patch** | 对配置的修改，后层覆盖前层 | 画上的修改 |

**配置叠加顺序**（后者覆盖前者）：
```
bundles → profile 的 cordis.patch.yml → home 级 ~/.dsh/cordis.patch.yml → --patch 参数
```

你只需要编辑 `~/.dsh/profiles/web/cordis.patch.yml`（你的用户覆盖层），其他不用动。

### 3.4 怎么用——四种方式

#### 方式一：Web UI——日常写代码
```bash
dsh web
```
打开浏览器，配好 API Key，选一个项目目录，开始对话。体验类似 Claude Code，但用 DeepSeek 模型。

#### 方式二：Headless——自动化任务
```bash
dsh --profile headless "检查仓库并修复失败的测试"
```
不启动浏览器，给任务就跑，跑完退出。适合 CI/CD。

#### 方式三：Python SDK——嵌入自己的程序
```python
with DeepSeekHarness(
    provider="deepseek-official",
    model="deepseek-v4-flash",
    cwd="/path/to/project",
) as harness:
    result = harness.run("修复失败的测试", session_id="task-001")
```

#### 方式四：自定义 Profile——搭自己的 Agent
```bash
dsh --profile myagent --patch ./extra.yml
```

### 3.5 写一个自己的插件——最小例子

**第 1 步：建插件目录**
```bash
mkdir -p example/plugins/hello-plugin
```

**第 2 步：写插件本体** `hello-plugin.ts`：
```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'hello-plugin'

export function apply(ctx: Context) {
  console.log('[hello-plugin] plugin loaded!')
}
```

**第 3 步：写挂载层** `cordis.patch.yml`：
```yaml
- insert:
    - id: hello-plugin
      name: '/绝对路径/example/plugins/hello-plugin/hello-plugin.ts'
```

> ⚠️ `name` 必须是**绝对路径**，相对路径会解析失败。

**第 4 步：启动**
```bash
./start.sh --patch example/plugins/hello-plugin/cordis.patch.yml
```

看到终端打印 `[hello-plugin] plugin loaded!` 就成功了。

### 3.6 新手第一步

```bash
npx @deepseek-ai/dsh web
```

打开浏览器，输入你的 DeepSeek API Key，然后说：

```
帮我看看当前目录下有哪些文件，解释一下项目结构
```

观察 DSH 怎么调用文件系统工具去读你的项目。

### 3.7 进阶学习路线

`learning/dsh/` 目录下有完整的学习笔记，按这个顺序读：

1. **旧稿-仅供参考/**（概念篇 00-06）——理解 DSH 是什么、怎么运转
2. **插件开发实战/**（01-09）——从第一个插件到完整开发
3. **能力扩展/**（01-06）——LLM 适配、存储、压缩、自动化
4. **深水区/**（00-11）——内核机制、多 Agent 协作、Web UI、mini-dsh 从零实现

---

## 第四部分：大模型微调——把通用模型变成你的专属模型

### 4.1 这是什么

**微调**：拿一个已预训练好的大模型，用你自己的标注数据**继续训练**，改动它的参数，让它在特定任务/领域上表现更好。

> **微调 vs RAG/Agent 的区别**：
> - RAG / Agent：模型本体不动，在外面加检索库、加工具链——像给人配了本字典。
> - 微调：直接改模型参数——像让人把技能"背进脑子里"，永久掌握。

### 4.2 什么时候用微调

| 你的需求 | 推荐方案 |
|---------|---------|
| 改变模型说话风格/行为（如客服口吻、固定输出格式） | **微调** |
| 让模型掌握一种通用任务能力（如分类、特定推理） | **微调** |
| 回答实时/海量/经常变动的知识（如最新文档） | RAG |
| 既要专业行为、又要最新知识 | **微调 + RAG 组合** |

> **判断口诀**：要"新行为/新风格" → 微调；要"新知识（尤其常变）" → RAG。

### 4.3 LoRA 与 QLoRA——最主流的省资源方法

**LoRA（Low-Rank Adaptation）** 的核心思想：不去改庞大的原始权重 W，而是在旁边挂一个很小的模块来学习"该怎么改"。

> **LoRA 的精髓**：同样表达"权重该怎么改"，全量微调要训 52 万个数，LoRA 只要训 1.2 万个——降到约 2.3%，省掉 97.7%。效果几乎不掉。

**QLoRA = 量化 + LoRA**：把冻结的原始权重从 16-bit 压到 4-bit 存储，让"加载并微调一个超大模型"能在一张消费级显卡上完成。

| 模型 | LoRA（FP16） | QLoRA（INT4） | 参考显卡 |
|------|-------------|--------------|---------|
| 7B | 约 16GB | 约 6GB | RTX 4090 / 3060 |
| 13B | 约 32GB | 约 12-13GB | RTX 4090 |
| 70B | 约 80GB | 约 48GB | H100 / L40 |

> **选型口诀**：显存够 → LoRA；显存紧张 → QLoRA。

### 4.4 四大微调框架怎么选

| 框架 | 一句话 | 适合谁 |
|------|--------|--------|
| **Unsloth** | 单卡极致提速（快 2-5 倍、省 70% 显存） | 单卡、快速迭代 |
| **LLaMA-Factory** | 全能型（100+ 模型、有 Web UI、方法最全） | 复杂任务、想要图形界面 |
| **ms-SWIFT** | 魔搭生态全家桶（450+ 模型、训→推→评→部署一条龙） | 国产模型（Qwen）、端到端部署 |
| **ColossalAI** | 大规模分布式引擎（多机多卡训千亿级模型） | 超大模型、集群训练 |

> **初学者建议路线**：先 Unsloth 或 LLaMA-Factory 跑通第一个 LoRA 任务 → 想可视化用 LLaMA-Factory 的 UI → 用 Qwen 等国产模型需要直接部署用 ms-SWIFT → 等要训超大模型再学 ColossalAI。

### 4.5 实战：用 ms-SWIFT 微调 Qwen3

#### 第 1 步：装环境

```bash
# 建独立环境（强烈建议）
conda create -n swift python=3.11 -y
conda activate swift

# 装 torch（按 CUDA 版本选）
pip install torch --index-url https://download.pytorch.org/whl/cu128

# 装 ms-swift（最简单一行）
pip install 'ms-swift[all]'
```

> 怕踩坑？用官方 Docker 镜像，CUDA/torch/vLLM/ms-swift 全打包好了。

#### 第 2 步：准备数据

微调的成败关键在数据。SFT 数据格式（JSONL，每行一条）：

```json
{"instruction": "用户问：我的订单什么时候发货？", "output": "订单通常在付款后 24 小时内发货。"}
{"instruction": "用户问：可以退货吗？", "output": "7 天无理由退货，商品保持完好即可。"}
```

> **常见误区**：几十条就想微调极易过拟合；学习率太高会灾难性遗忘（一般用 1e-4 ~ 2e-4）。

#### 第 3 步：开始训练

```bash
swift sft \
    --model Qwen/Qwen3-4B-Instruct \
    --dataset your_data.jsonl \
    --torch_dtype bfloat16 \
    --num_train_epochs 3 \
    --per_device_train_batch_size 2 \
    --learning_rate 1e-4 \
    --tuner_type lora \
    --lora_rank 16 \
    --lora_alpha 32
```

#### 第 4 步：推理验证

```bash
swift infer --model Qwen/Qwen3-4B-Instruct --adapters output/checkpoint-xxx
```

### 4.6 LoRA 关键参数速查

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `r`（秩） | **16 起步** | 简单任务用 8/16，复杂任务用 32，过大会过拟合 |
| `alpha`（α） | **`α = 2r`** | 最常用安全默认值；`α = r` 更保守 |
| `target_modules` | `q_proj, v_proj` 起步 | 不够加 `o_proj` → 再加 `k_proj` 和 FFN（`gate/up/down_proj`） |
| `learning_rate` | **1e-4 ~ 2e-4** | 最危险的参数，太大 loss 会飞 |
| `num_train_epochs` | **1~3 轮** | 太多会过拟合，看验证集 |

### 4.7 新手第一步

如果你想最快跑通一次微调：

1. 装 **Unsloth**（`pip install unsloth`）
2. 去 [unsloth 官方 Colab](https://github.com/unslothai/unsloth) 复制一个示例 notebook
3. 换成你自己的数据
4. 点 Run All

没有显卡？用魔搭免费 GPU：登录 [ModelScope](https://www.modelscope.cn) → 我的 Notebook → 启动免费实例。

### 4.8 进阶学习路线

`learning/大模型微调/` 目录下有完整笔记，按这个顺序读：

1. **01-09 概念篇**——微调概述 → 全量 vs 高效 → LoRA/QLoRA → SFT → 灾难性遗忘 → 软硬件环境 → 数据集 → 分布式训练 → Function Calling 与 MCP
2. **微调框架/**——四大框架概述 + 各自详解
3. **实战演练/**——Qwen3 环境准备 → ms-SWIFT 安装 → 训练 → 推理 → RLHF
4. **Qwen3 微调经验总结/**——数据集准备 + 数据量经验
5. **模型评测/**——EvalScope 评测框架

---

## 附录：四套工具怎么搭配用

### 场景一：学习一个新技术

```
1. 用 Obsidian 的 /autoresearch 自动联网研究并归档
2. 用 OpenCode + OmO 边学边写代码实践
3. 把实践结论 /save 存回知识库
4. 想深入就微调一个模型来理解原理
```

### 场景二：开发一个 AI 应用

```
1. 用 OpenCode + OmO 写应用代码（ulw 一键搞定）
2. 用 DSH 做 Agent 框架（如果需要 Agent 能力）
3. 微调一个专属模型来提升效果
4. 把开发经验 /save 存进知识库
```

### 场景三：搭建内部工具链

```
1. 用 DSH 搭建定制化 Agent（写自己的插件）
2. 微调模型适配你的业务领域
3. 用 Obsidian 维护文档和知识库
4. 用 OmO 做日常代码开发
```

---

## 速查总表

| 我想... | 用什么 | 怎么触发 |
|---------|--------|---------|
| 查知识库 | Obsidian wiki-query | `什么是…` / `query:` |
| 存对话进知识库 | Obsidian save | `/save` / `存一下` |
| 自动研究一个主题 | Obsidian autoresearch | `/autoresearch [主题]` |
| 改个小代码 | OpenCode 直接对话 | 直接说话 |
| 让 AI 自己搞定一个功能 | OmO ultrawork | `ulw 描述` |
| 做大重构 | OmO plan + start-work | `@plan 描述` → `/start-work` |
| 咨询架构问题 | OmO Oracle | `Tab` → Oracle |
| 用 Web UI 写代码 | DSH Web | `dsh web` |
| 跑自动化任务 | DSH Headless | `dsh --profile headless "任务"` |
| 写自己的 Agent 插件 | DSH 插件开发 | 见第三部分 3.5 |
| 把模型变成客服风格 | 大模型微调（LoRA） | 见第四部分 4.5 |
| 在消费级显卡上微调大模型 | QLoRA | 4-bit 量化 + LoRA |
| 选微调框架 | 按场景选 | 见第四部分 4.4 |

---

## 继续阅读

- [[Obsidian 命令与技能完全指南]]——Obsidian 14 个技能完整详解
- [[Oh-My-OpenAgent-实战搭配使用指南]]——OmO 三种工作模式实战
- [[oh-my-openagent.json-小白配置详解]]——OmO 配置文件逐项解释
- [[00 dsh 概述]]——DSH 完整概述
- [[01 dsh 是怎么运转的——从一条命令说起]]——DSH 核心概念
- [[01 大模型微调概述]]——微调原理详解
- [[03 LoRA 与 QLoRA]]——最主流微调方法
- [[09 Function Calling 与 MCP 原理详解]]——工具调用与 MCP 原理

---

*写于 learning 目录 · 新手教程专题*
