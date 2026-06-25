---
type: concept
status: developing
area: growth
title: "Obsidian 命令与技能完全指南"
question: "帮我写一篇文章，介绍 Obsidian 的所有命令、所有技能的使用。"
created: 2026-06-25
updated: 2026-06-25
tags:
  - learning
  - obsidian
  - 工具
  - 知识管理
  - claude-obsidian
related:
  - "[[overview]]"
  - "[[index]]"
sources:
  - "本地已安装插件 claude-obsidian（14 个 SKILL.md，已逐个核对）"
  - "https://github.com/AgriciDaniel/claude-obsidian （插件官方仓库，作者 Daniel Agrici，MIT）"
  - "https://github.com/kepano/obsidian-skills （Steph Ango 官方 Obsidian 技能）"
  - "https://jsoncanvas.org/ （JSON Canvas 开放标准）"
  - "https://help.obsidian.md/bases/syntax （Obsidian Bases 官方文档）"
---

# Obsidian 命令与技能完全指南

> 本文分两大部分：**上半部分**讲 **Obsidian 软件自身**的命令体系（命令面板、快捷键、核心命令）；**下半部分**讲你这套环境里真正在用的 **`claude-obsidian` 插件（v1.9.0）的 14 个 AI 技能（Skills）**——也就是你输入 `/obsidian/wiki-query`、`/obsidian/autoresearch` 等斜杠命令时背后调用的东西。
>
> 一句话先记住：**Obsidian 的"命令"是给人用的（键盘驱动笔记软件）；`claude-obsidian` 的"技能"是给 AI 用的（让 AI 帮你建/查/维护知识库）。** 两套体系，目标都是"少点鼠标，多产出知识"。

---

## 第一部分：Obsidian 软件自身的命令

### 1. 命令面板（Command Palette）—— 一切的入口

> [!key-insight] 记住一个快捷键就够了
> **`Cmd/Ctrl + P`** 打开命令面板，输入关键词模糊搜索，回车执行。Obsidian 里几乎所有功能（核心 + 插件）都注册成"命令"，都能在这里搜到并执行。**不用记几百个快捷键，记住 `Cmd+P` 这一个就能找到其余所有。**

命令面板的特点：
- **模糊搜索**：输入 `tp` 能匹配到 `Toggle Preview`。
- **显示快捷键**：每条命令右侧会标出它绑定的快捷键，顺便帮你记忆。
- **最近使用置顶**：常用命令会排到前面。

### 2. 必知的核心命令（按使用频率）

| 命令（英文） | 默认快捷键 (Mac / Win) | 作用 |
|---|---|---|
| Open command palette | `Cmd+P` / `Ctrl+P` | 打开命令面板（入口中的入口） |
| Quick switcher | `Cmd+O` / `Ctrl+O` | 快速跳转/打开任意笔记（按文件名搜索） |
| Search in all files | `Cmd+Shift+F` / `Ctrl+Shift+F` | 全库全文搜索 |
| Toggle edit/preview | `Cmd+E` / `Ctrl+E` | 编辑模式 ↔ 阅读模式切换 |
| Create new note | `Cmd+N` / `Ctrl+N` | 新建笔记 |
| Open today's daily note | （需绑定） | 打开/创建当天的日记 |
| Insert link / wikilink | `[[` 触发 | 输入 `[[` 自动弹出笔记选择器 |
| Open graph view | （需绑定） | 打开关系图谱 |
| Follow link under cursor | `Cmd+点击` | 跟随光标处的链接跳转 |
| Navigate back / forward | `Cmd+Alt+←/→` | 后退/前进（像浏览器） |
| Toggle left/right sidebar | `Cmd+Alt+L/R` 等 | 收起/展开侧边栏 |
| Open settings | `Cmd+,` / `Ctrl+,` | 打开设置 |

> [!tip] 快捷键都能自定义
> 设置 → **快捷键（Hotkeys）** 里可以给任意命令绑定/改键。搜命令名 → 点 `+` → 按下你想要的组合键即可。冲突会提示。

### 3. 命令的三个来源

1. **核心命令**：Obsidian 内置（新建、搜索、切换视图等）。
2. **核心插件命令**：官方功能模块（日记 Daily Notes、模板 Templates、关系图谱、画布 Canvas、Bases 等），在"设置 → 核心插件"开关。
3. **社区插件命令**：第三方插件注册的命令（如 Dataview、Templater、QuickAdd），装了就出现在命令面板里。

### 4. 两个值得专门了解的核心功能

- **Canvas（画布）**：无限画布，把笔记/图片/卡片摆在一张空间板上。底层是 **JSON Canvas 开放标准**（`.canvas` 文件，本质是 JSON，遵循 [jsoncanvas.org](https://jsoncanvas.org/) 规范，MIT 开源，源于 Obsidian）。
- **Bases（数据库视图，2025 推出）**：把笔记变成可查询的动态表格/卡片/列表视图，用 `.base` 文件（YAML 定义 `filters / formulas / properties / views`）。**无需插件，是 Obsidian 核心功能。**

---

## 第二部分：`claude-obsidian` 插件的 14 个 AI 技能

> 这才是你日常输入 `/obsidian/...` 时真正运行的东西。`claude-obsidian` 是一个 **Claude / Agent-Skills 插件**，把 Obsidian Vault 变成一个**会自我增长的知识库（compounding wiki）**。核心理念：**Wiki 才是产品，聊天只是接口（"The wiki is the product. Chat is just the interface."）**——AI 不只回答问题，还会把答案写回知识库，越用越厚。
>
> 当前版本 **v1.9.x**，共 **14 个核心技能 + 1 个思考元技能**。下面按"日常使用频率 + 逻辑分组"介绍。

> [!note] 插件背景（已联网核对）
> - **仓库**：[github.com/AgriciDaniel/claude-obsidian](https://github.com/AgriciDaniel/claude-obsidian)（作者 Daniel Agrici，MIT 协议，~7.8k stars）。
> - **灵感来源**：Andrej Karpathy 的「LLM Wiki」模式——让大模型把知识沉淀成一个持续生长的 wiki。
> - **与官方技能的关系**：Obsidian 创始人 Steph Ango（kepano）维护着官方的 [`kepano/obsidian-skills`](https://github.com/kepano/obsidian-skills)（5 个参考技能：markdown / bases / json-canvas / cli / defuddle）。`claude-obsidian` **不是它的 fork**，而是**遵循同一套 Agent Skills 规范**、在其之上扩展出整套"复合知识库"工作流（多出研究、查询、维护、思考等 10 个技能）。两者可并存。

### 关键版本里程碑（已核对 CHANGELOG）

| 版本 | 代号 | 新增 |
|---|---|---|
| **v1.7** | Compound Vault | `wiki-cli`（Obsidian CLI 传输层）+ `wiki-retrieve`（混合检索）+ 多写并发锁 |
| **v1.8** | Methodology Modes | `wiki-mode`（LYT/PARA/Zettelkasten/Generic 四种方法论） |
| **v1.9** | Thinking Framework | `think`（10 原则思考元技能）+ 给其余 14 个技能各加"How to think"附录 |

### 架构速览：知识库的三层结构

```
vault/
├── .raw/       # 第 1 层：不可变的原始素材（点号开头，Obsidian 里隐藏）
├── wiki/       # 第 2 层：AI 生成的知识库（你看到的所有页面）
└── CLAUDE.md   # 第 3 层：schema 与指令（插件本体）
```

`wiki/` 内部约定目录：`index.md`（总目录）、`hot.md`（热缓存/最近上下文）、`log.md`（操作日志）、`overview.md`（总览）、`sources/`（来源页）、`concepts/`（概念）、`entities/`（人/组织/产品）、`questions/`（问答归档）、`meta/`（仪表盘/lint 报告）等。

---

### A 组：日常高频技能（查 / 存 / 录）

#### 1. `wiki-query` — 查询知识库 ⭐最常用

**触发词**：`什么是…`、`query:`、`解释…`、`总结…`、`search the wiki`、`wiki query quick/deep`。

按问题复杂度分**三档**，控制读取量和成本：

| 模式 | 触发 | 读取范围 | Token | 适用 |
|---|---|---|---|---|
| **Quick（快）** | `query quick:` 或简单事实题 | 仅 `hot.md` + `index.md` | ~1,500 | "X 是什么"、查日期、快速事实 |
| **Standard（标准，默认）** | 不加标记 | hot + index + 3-5 个页面 | ~3,000 | 大多数问题 |
| **Deep（深）** | `query deep:` 或"全面""详尽" | 整个 wiki + 可选联网 | ~8,000+ | 跨页综合、对比、查缺补漏 |

工作流：**先读 `hot.md` → 再读 `index.md` 定位 → 打开相关页面 → 带引用 `(Source: [[页面]])` 作答 → 好答案回存为 wiki 页面**。它就是刚才帮你找"Qwen 训练命令"用的技能。

#### 2. `save` — 把对话/答案存进知识库

**触发词**：`save this`、`/save`、`存一下`、`归档这段`、`file this`。

把刚聊的内容分析后，**自动判定笔记类型**（synthesis→`questions/`、concept→`concepts/`…）、生成 frontmatter、归档到正确目录，并更新 `index.md`、`log.md`、`hot.md`。v1.7+ 支持写锁（并发安全），v1.8+ 支持按"知识库方法论模式"决定存放路径。

#### 3. `wiki-ingest` — 摄取外部素材建页

**触发词**：`ingest`、`处理这个素材`、`把这个加进 wiki`、`batch ingest`、`ingest this url`。

读一个素材（文件/URL/批量），抽取实体与概念，**创建或更新 wiki 页面并交叉引用**。一个素材通常会牵动 **8-15 个页面**。是知识库"长肉"的主力技能。

---

### B 组：自动研究与可视化

#### 4. `autoresearch` — 自主联网研究并归档

**触发词**：`/autoresearch`、`research [主题]`、`深入研究…`、`调研…`、`build a wiki on`。

基于 Karpathy 的 autoresearch 模式：给一个主题，AI **自动多轮联网搜索 → 抓取 → 综合 → 直接写成 wiki 页面**（你得到的是页面，不是聊天回复）。
- 循环：**Round 1 广搜（3-5 个角度）→ Round 2 补缺 → Round 3 综合**，最多 3 轮。
- 产出：`sources/` 每个来源一页 + `concepts/` 概念页 + `entities/` 实体页 + `questions/Research: [主题].md` 总综合页。
- ⚠️ **成本提示**：一次满负荷跑约 `3 轮 × 5 源 × 3 角度 ≈ 45 次 WebFetch`，开跑前会先告知预算。
- 你的 `my-note` 库里那篇 [[Research: 大模型微调]] 就是它生成的。

#### 5. `canvas` — 可视化参考层

**触发词**：`/canvas`、`canvas new/add image/add text/add pdf`、`put this on the canvas`。

向 Obsidian 画布（`.canvas` JSON 文件）添加图片、文字卡片、PDF、wiki 页面，并**自动按"区域(zone)"定位排版**。默认画布 `wiki/canvases/main.canvas`。与三种捕获层并列：`/save`→文字综合、`/autoresearch`→结构化知识、`/canvas`→视觉参考。

#### 6. `defuddle` — 网页正文清洗

**触发词**：`defuddle`、`clean this page`、`strip this url`、`fetch and clean`。

抓网页前先去广告/导航/页脚/cookie 横幅，**只留正文转成干净 markdown，省 40-60% token**。依赖 `defuddle-cli`（`npm install -g defuddle-cli`）。建议在 URL 摄取前先跑它。

---

### C 组：知识库维护与检索

#### 7. `wiki-lint` — 知识库健康体检

**触发词**：`lint`、`health check`、`检查 wiki`、`find orphans`、`wiki audit`。

每 10-15 次摄取或每周跑一次。检查项：**孤儿页面、死链、过时论断、缺失页面、缺失交叉引用、frontmatter 缺字段、空小节、过时索引项**等，输出报告到 `wiki/meta/lint-report-YYYY-MM-DD.md`。**修改前会先征求同意。**

#### 8. `wiki-retrieve` — 混合检索（v1.7+，需手动开启）

**触发词**：`retrieve`、`hybrid retrieval`、`BM25`、`rerank`、`semantic search`、`chunk search`。

把"页面级"检索升级为"**段落(chunk)级**"：**上下文前缀 + BM25 稀疏检索 + cosine 重排**，源自 Anthropic 2024.9 的 Contextual Retrieval 研究（检索失败率降 35-67%）。
- 开启：`bash bin/setup-retrieve.sh`；用法：`python3 scripts/retrieve.py "<问题>" --top 5`。
- 开启后会被 `wiki-query`、`autoresearch` 自动优先调用；不开则零影响。

#### 9. `wiki-fold` — 日志归卷（Rollup）

**触发词**：`fold the log`、`run wiki-fold`、`log rollup`、`日志归卷`。

把 `wiki/log.md` 最近 `2^k` 条日志**抽取式汇总**成一个 fold 页面（写到 `wiki/folds/`），并链回子条目。**纯抽取、不编造**；默认 dry-run 预览，确认后才 commit。

---

### D 组：配置与底座（一般不直接调，由其他技能内部使用）

#### 10. `wiki` — 知识库总管 / 脚手架

**触发词**：`set up wiki`、`scaffold vault`、`create knowledge base`、`/wiki`、`second brain setup`。

**初始化和搭建知识库**：从一句话描述生成目录结构、管理 `hot.md` 热缓存、做跨项目引用。是整套体系的"路由器"，会把请求分发给上面那些子技能。

#### 11. `wiki-cli` — 默认传输层（v1.7+）

**触发词**：`obsidian cli`、`obsidian read/write/search`、`transport detection`。

v1.7+ 统一用 **Obsidian CLI（Obsidian 1.12 自带）** 作为读写 Vault 的首选通道——无需 MCP server、无需 REST API 插件。常用命令：
```bash
obsidian-cli read   "$VAULT" "$NOTE"      # 读笔记
obsidian-cli write  "$VAULT" "$NOTE" < content.md   # 写笔记
obsidian-cli search "$VAULT" "<query>"    # 搜索（Obsidian 原生排序）
obsidian-cli backlinks "$VAULT" "$NOTE"   # 反向链接
```
检测：`bash scripts/detect-transport.sh`（写入 `.vault-meta/transport.json`）。**回退链**：`cli → mcp-obsidian → filesystem`（CLI 不可用时自动降级到普通文件读写，永不中断）。

#### 12. `wiki-mode` — 知识库方法论模式（v1.8+）

**触发词**：`set vault mode`、`switch to PARA`、`use LYT`、`zettelkasten setup`、`what's my vault mode`。

让知识库声明一种组织风格，其他技能据此决定新页面归档到哪：

| 模式 | 理念 | 归档约定 |
|---|---|---|
| **LYT**（Nick Milo） | 笔记互链、靠 MOC 导航，不靠文件夹 | `mocs/<topic>-moc.md` + `notes/<原子笔记>.md` |
| **PARA**（Tiago Forte） | 按"可执行性"分类 | `projects/ / areas/ / resources/ / archives/` |
| **Zettelkasten**（卢曼卡片盒） | 原子笔记 + 时间戳唯一 ID + 双向密链 | `wiki/<20位时间戳ID>-<slug>.md` |
| **Generic（默认）** | 不强加方法论，保持 v1.7 行为 | `sources/ / entities/ / concepts/ / <domain>/` |

设置后写入 `.vault-meta/mode.json`；不设则默认 `generic`。

---

### E 组：写作规范与思考底座

#### 13. `obsidian-markdown` — Obsidian 风味 Markdown 规范

**触发词**：`write obsidian note`、`wikilink`、`callout`、`embed`、`obsidian syntax`。

写任何 wiki 页面时的语法参考。关键语法：

| 语法 | 作用 |
|---|---|
| `[[笔记名]]` | 内部链接（wikilink） |
| `[[笔记名\|显示文字]]` | 别名链接 |
| `[[笔记名#标题]]` / `[[笔记名#^块ID]]` | 链到标题 / 块 |
| `![[文件]]` | 嵌入（图片/笔记/PDF） |
| `> [!type] 标题` | callout 提示框（note/tip/warning/key-insight…） |
| `--- ... ---`（YAML） | properties / frontmatter 属性 |
| `#tag` | 标签 |
| `==高亮==` | 高亮 |

#### 14. `obsidian-bases` — Bases 数据库视图

**触发词**：`create a base`、`obsidian bases`、`database view`、`dynamic table`、`task tracker base`。

写 `.base` 文件（YAML），把笔记变成动态表格/卡片/列表。根键：`filters / formulas / properties / summaries / views`。示例：
```yaml
filters:
  and:
    - file.hasTag("wiki")
    - 'status != "archived"'
formulas:
  age_days: '(now() - file.ctime).days.round(0)'
```

#### 15.（贯穿全局）`think` — 10 原则思考循环

**触发词**：`think this through`、`/think`、`deep think`、`audit my thinking`、`am I thinking about this right`。

> [!note] 它是"元技能"
> v1.9.0 新增的 **meta-skill**，不直接产出页面，而是**指导其余 14 个技能怎么思考**。10 个阶段：**OBSERVE(外部)→OBSERVE(内省)→LISTEN→THINK→CONNECT(横向)→CONNECT(系统)→FEEL→ACCEPT→CREATE→GROW**。用于架构决策、复盘、模糊需求、审计等非琐碎问题。

---

## 速查总表：14 个技能一览

| # | 技能 | 一句话 | 典型触发 |
|---|---|---|---|
| 1 | **wiki-query** | 查知识库（quick/standard/deep 三档） | `什么是…`、`query deep:` |
| 2 | **save** | 把对话存成 wiki 页 | `/save`、`存一下` |
| 3 | **wiki-ingest** | 摄取素材建页 | `ingest this url` |
| 4 | **autoresearch** | 自动联网研究并归档 | `/autoresearch [主题]` |
| 5 | **canvas** | 往画布加图/卡片/PDF | `/canvas add image` |
| 6 | **defuddle** | 网页正文清洗省 token | `clean this url` |
| 7 | **wiki-lint** | 知识库体检（孤儿/死链…） | `lint`、`wiki audit` |
| 8 | **wiki-retrieve** | 段落级混合检索（需开启） | `hybrid retrieval` |
| 9 | **wiki-fold** | 日志归卷汇总 | `fold the log` |
| 10 | **wiki** | 初始化/搭建/总路由 | `/wiki`、`set up wiki` |
| 11 | **wiki-cli** | 默认读写传输层 | `obsidian cli` |
| 12 | **wiki-mode** | LYT/PARA/Zettel/Generic 模式 | `switch to PARA` |
| 13 | **obsidian-markdown** | OFM 语法规范 | `wikilink`、`callout` |
| 14 | **obsidian-bases** | `.base` 数据库视图 | `create a base` |
| ★ | **think** | 10 原则思考元技能 | `/think` |

---

## 怎么搭配用（推荐工作流）

> [!key-insight] 一个典型的"知识增长循环"
> 1. **建库**：`/wiki set up`（一次性，已建好可跳过）。
> 2. **进料**：看到好文章 → `defuddle` 清洗 → `wiki-ingest` 摄取建页。
> 3. **深挖**：对某主题不熟 → `/autoresearch [主题]` 自动研究归档。
> 4. **取用**：随时 `wiki-query`（如 [[Obsidian 命令与技能完全指南|本文]] 就是查询+综合的产物）。
> 5. **沉淀**：聊出好结论 → `/save` 存回库。
> 6. **维护**：每周 `wiki-lint` 体检；日志多了 `wiki-fold` 归卷。
> 7. **可视化**：需要全局视图 → `/canvas` 摆成图。
>
> 配置类（`wiki-cli`/`wiki-mode`/`wiki-retrieve`）和写作规范类（`obsidian-markdown`/`obsidian-bases`）大多在背后自动生效，按需手动调。

---

## 已核对要点（Verified Facts）

> [!key-insight] 本次已联网交叉验证
> - 14 个技能的功能描述：**本地 `SKILL.md` 逐个核对**（最权威，就是你机器上运行的版本）。
> - 插件仓库 / 作者 / 版本历史 / 与 kepano 的关系：经 GitHub 一手来源核对（见下方来源）。
> - JSON Canvas（`.canvas`，MIT，源于 Obsidian 2022.12，2024.3 独立成开放标准）与 Obsidian Bases（自 Obsidian v1.9.10 / 2025.8 起为核心功能）均已确认。

## 仍待补充（Open Questions）

- **Obsidian 默认快捷键全表**：`help.obsidian.md` 命令面板页为 JS 渲染未能抓全；本文核心命令表基于通用稳定事实，个别默认快捷键可能随版本/平台略变，**以本地"设置 → 快捷键"为准**。
- **`think` 元技能的 10 阶段细节**：本文给了阶段名，完整方法论可进一步从 `think/SKILL.md` 展开单独成页。

## 来源（Sources）

- 本地插件 `claude-obsidian`：14 个 `SKILL.md`（`~/.config/opencode/skills/obsidian/`，逐个读取核对）
- [github.com/AgriciDaniel/claude-obsidian](https://github.com/AgriciDaniel/claude-obsidian)：仓库 / README / CHANGELOG（作者 Daniel Agrici，MIT）
- [github.com/kepano/obsidian-skills](https://github.com/kepano/obsidian-skills)：Steph Ango 官方 Obsidian 技能（上下游关系核对）
- [JSON Canvas 开放标准](https://jsoncanvas.org/)（`.canvas` 格式，MIT，源于 Obsidian）
- [Obsidian Bases 文档](https://help.obsidian.md/bases/syntax)
- [Karpathy 的 LLM Wiki 模式](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)（插件灵感来源）

## 继续阅读

- [[Oh-My-OpenAgent-实战搭配使用指南]] — learning 区另一篇"工具用法"学习页（OpenCode 生态）
- [[Research: 大模型微调]] — 同样由 autoresearch 技能生成的综合页示例
- [[index]] — 知识库主目录
