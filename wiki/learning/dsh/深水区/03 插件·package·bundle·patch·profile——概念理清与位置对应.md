---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, 概念, plugin, bundle, patch, profile, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 03 插件·package·bundle·patch·profile——概念理清与位置对应

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - **来源**：`docs/architecture.zh.md`「Profile 与组合包」+ `docs/cordis-primer.zh.md` + `docs/glossary.zh.md`
> - **本篇性质特殊**：它**不是新知识**，是**贯穿全局的基础概念的集中理清**——01/03/04/09 篇都散落用到，这里**一次讲透**

> [!abstract] 本章是什么 / 该记住什么
> **性质**：**基础概念的"归档篇"**——把 5 个总搞混的词（插件/package/bundle/patch/profile）**一次理清**，并**对应到物理位置**。
> **读完该记住**：
> 1. **5 个词的最小定义**（见第一节表）
> 2. **物理位置**：插件=`packages/xxx/`；bundle=`packages/bundle/`；patch=`cordis.patch.yml`；profile=`~/.dsh/profiles/`
> 3. **声明方式**：`package.json` 的 `dsh` 字段（`dsh.profile` / `dsh.bundle`）
> 4. **五层组装**：bundle[0]→bundle[1]→profile patch→home patch→`--patch`

## 这一篇在讲什么

学到现在，你反复听到 **"插件、package、bundle、patch、profile"** 这 5 个词——**但它们的关系一直没一次讲清**。本篇**一次理清 + 对应到物理位置**。

> **为什么记不住**：它们**层级不同**（有的是"东西"、有的是"文件"、有的是"组装"）——**混在一起就像"苹果、篮子、购物清单"混着说**。

---

## 一、5 个概念（各是什么，一句话）

| 概念              | 一句话定义                                                            | 权威出处                    |
| --------------- | ---------------------------------------------------------------- | ----------------------- |
| **插件（plugin）**  | **实现 Service 的对象**——一个带 `inject`/`apply(ctx)` 的函数，或 `Service` 子类 | `cordis-primer.zh.md:9` |
| **package（包）**  | **npm 包**——插件通常打成 npm 包（`package.json` + 代码）                     | 通用（npm 概念）              |
| **bundle（组合包）** | **"配置项 + 挂载代码"的分发格式**（一叠"积木袋"）                                   | `architecture.zh.md`    |
| **patch**       | **按 id 定位条目、替换其 config 或插入新条目的"施工单"**                            | `architecture.zh.md`    |
| **profile**     | **存放在 Harness home 的"具名组装"**（列出叠哪些 bundle + 用户 patch）            | `architecture.zh.md`    |

> **出处**（逐字）：
> - **插件**：`cordis-primer.zh.md:9`——*"插件是实现 Service 的对象。它可以是一个带有可选 `inject` 和 `apply(ctx)` 字段的函数，也可以是一个 `Service` 子类。"*
> - **bundle / profile**：`architecture.zh.md`「Profile 与组合包」——*"**profile** 是存放在 Harness home 中的具名组装…**组合包** 是 Cordis 配置项及其挂载代码的分发格式。"*
> - **patch**：`architecture.zh.md`——*"一条 patch 按 id 定位某个条目并替换其整个 config，或插入新条目。"*

### 先建立直觉：`./start.sh` 那一刻需要决定什么

**为什么要有这 5 个东西？** —— **因为你启动 dsh 时，需要"决定：装哪些零件、怎么装"。**

这 5 个东西，就是**"装 dsh 这台机器"的 5 种角色**。**下面全用你电脑上真实的 dsh 来认。**

---

## 二、用真实的 dsh 逐个拆开讲

> 下面**全部用你电脑上真实的文件**——不类比别的行业，就讲"它在 dsh 里干嘛"。

### ① profile —— **你的"整机配置单"**

**位置**：`~/.dsh/profiles/web/`（你电脑上有 `web` / `headless` / `demo` / `my-agent` 四套）

**它里面装了什么**（真实目录）：
```
~/.dsh/profiles/web/
├── package.json       ← 声明"我要用哪些 bundle"
├── cordis.patch.yml   ← "我自己还想改点什么"
└── node_modules/      ← 装的东西
```

**打开它的 `package.json`**（真实内容）：
```json
{
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"]
    }
  }
}
```
**翻译**：*"我这个 web profile，由 base + web-app 两个 bundle 拼成。"*

| | |
|---|---|
| **它干嘛用** | **它是"容器/清单"**——装"你要哪些能力"。`dsh --profile web` = 用 web 这套启动 |
| **它不能干嘛** | **它自己不提供任何能力**——只是"菜单"，不是"菜" |
| **为什么要它** | **你有好几套方案**（web/headless/my-agent）——**profile 就是"一套方案"** |

### ② bundle —— **"一整套零件包"**

**位置**：`packages/bundle/base/`、`packages/bundle/web-app/`（真实存在）

**真实的 `dsh-base`**（`package.json` 真实内容）：
```json
{
  "name": "@deepseek-ai/dsh-base",
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
```
**翻译**：*"我是 base bundle，我的'零件清单'在那个 `cordis.patch.yml` 里。"*

**`dsh-base` 里装了啥**：**~80 个插件**（llm、session、tools、bash、存储…）——**dsh 核心几乎全在这**。

| | |
|---|---|
| **它干嘛用** | **把"一堆插件"打包成一块**——方便"一键装配"。`base`=公共核心；`web-app`=加浏览器界面 |
| **它不能干嘛** | **它不是"一个功能"**——**是"一包功能"**（一叠装好的零件） |
| **为什么要它** | **没有 bundle，你得手动装 80 个插件**——bundle 让"装 dsh"变成"叠几个 bundle" |

### ③ patch —— **"装配说明书"**

**位置**：`cordis.patch.yml`（**文件**）——bundle 里有、profile 里有、你也能写

**真实的 `dsh-base/cordis.patch.yml`**（真实内容，前几行）：
```yaml
- insert:
    - id: timer
      name: '@deepseek-ai/cordis-plugin-timer'
    - id: session
      name: '@deepseek-ai/dsh-session'
    # ...约 80 个
```
**翻译**：*"往空树里，插入这 80 个插件。"*

**两种写法**：
```yaml
- insert:                        # 装新的
    - id: xxx  name: '...'
- id: system-prompt              # 改已有的
  config:
    personaPrefix: 你是助手
```

| | |
|---|---|
| **它干嘛用** | **它是"施工单"**——告诉 dsh"装哪些插件、改什么" |
| **它不能干嘛** | **它自己不提供能力**——是"指令" |
| **为什么要它** | **bundle / profile 都需要"声明形式"**——patch 就是这个"声明文件" |

### ④ 插件（plugin）—— **"一个具体零件"**

**位置**：`packages/extensions/tool-cordis/`、`packages/llm/llm-deepseek/`（一个 npm 包）

**真实的 `tool-cordis`**：名字 `@deepseek-ai/dsh-tool-cordis`，**没有 `dsh` 字段**（它是普通插件，不是 bundle）。

**它的代码长啥样**（真实）：
```ts
export const name = 'tool-cordis'
export function apply(ctx) {
  ctx.tools.register(defineTool({ name: 'cordis_define', ... }))   // 注册工具
  // ...7 个工具
}
```

| | |
|---|---|
| **它干嘛用** | **提供"一个具体能力"**——如 `tool-cordis` = "7 个 cordis 工具"。它是"零件" |
| **它不能干嘛** | **单个插件能力有限**——一堆插件组合才是完整 dsh |
| **为什么要它** | **dsh 核心思想：一切皆插件**——**功能 = 插件** |

### ⑤ package —— **"插件的包装盒"**

**位置**：每个插件目录里的 `package.json`

**关系**：**插件 = 代码（`apply` 函数）；package = 装着它的"盒子"（文件夹 + `package.json`）**。一个插件通常就是一个 package。

**例**：`packages/extensions/tool-cordis/` 这个文件夹 = **一个 package**；里面的代码 = **一个插件**。

| | |
|---|---|
| **它干嘛用** | **npm 靠它分发**——`npm install @deepseek-ai/dsh-tool-cordis` 装的就是这个 package。`package.json` 的 `dsh` 字段**声明"我是插件还是 bundle"** |
| **它不能干嘛** | **它是个"包装"**——本身不提供功能（功能在插件代码里） |
| **为什么要它** | **npm 生态靠 package 分发**——插件要靠它装出来 |

---

## 三、⭐ 串起来：`./start.sh` 那一刻发生了什么

```
【你：./start.sh --profile web】
        │
        ▼
① profile（~/.dsh/profiles/web/）      ← "我要用 web 这套"
   读 package.json：bundles = [base, web-app]   ← "先装 base，再装 web-app"
        │
        ▼
② bundle（dsh-base）                    ← "base 这块怎么装，看我的 patch"
   读 dsh.bundle.patch = cordis.patch.yml
        │
        ▼
③ patch（base/cordis.patch.yml）        ← "施工单：插入这些插件"
   - insert: [timer, session, tools, ...]  ← 80 个
        │
        ▼
④ 插件（每个 insert 指向一个插件）       ← 装上去的"零件"
   - id: session  name: '@deepseek-ai/dsh-session'
        │
        ▼
⑤ package（每个插件是个 npm 包）         ← 从 node_modules 加载
        │
        ▼
     【dsh 起来了！】
```

**一句话**：**profile（我用哪套）→ bundle（积木袋）→ patch（施工单）→ 插件（零件）→ package（包装）。**

### 为什么要有这 5 个东西（意义）

| 问题 | 答案 |
|---|---|
| **为什么要插件？** | dsh 是"一切皆插件"——**功能靠插件堆** |
| **为什么要 package？** | **npm 靠它分发**——`npm install` 装的是 package |
| **为什么要 bundle？** | **把 80 个插件打包**——不然手动装 80 个，累死 |
| **为什么要 patch？** | **"装配"需要"说明书"**——告诉 dsh 装哪些、改哪些 |
| **为什么要 profile？** | **你有好几套方案**——**profile 就是"一套方案"** |

## 四、⭐ 物理位置对应（核心：放哪）

| 概念 | **物理位置** | 例子 |
|---|---|---|
| **插件** | **`packages/<域>/<名>/`** | `packages/llm/llm-deepseek/`、`packages/extensions/tool-cordis/` |
| **package** | **同上**（插件就是 package，带 `package.json`） | 每个 `packages/*/` |
| **bundle** | **`packages/bundle/<名>/`** | `packages/bundle/{base,web-app,headless,sdk-app,acp-app,sdk-minimal}/` |
| **patch（文件）** | **`cordis.patch.yml`** | `packages/bundle/base/cordis.patch.yml`（bundle 内）、`~/.dsh/profiles/web/cordis.patch.yml`（profile 内）、你写的任意 `--patch` 文件 |
| **profile** | **`~/.dsh/profiles/<名>/`** | `~/.dsh/profiles/{web,headless,demo,my-agent}/` |

> **出处**：本人核对 `ls packages/bundle/`、`ls ~/.dsh/profiles/`（2026-09-16）

### ⚠️ 一个关键区分：**bundle ≠ 插件**

**bundle 和插件是"两种不同的包"**——靠 `package.json` 的 `dsh` 字段区分：

| | **插件**（如 `tool-cordis`） | **bundle**（如 `dsh-base`） |
|---|---|---|
| `dsh` 字段 | **无**（或只有 `dsh.bundle` 之外的） | **有 `dsh.bundle`** |
| 例 | `packages/extensions/tool-cordis/package.json`（无 dsh 字段） | `packages/bundle/base/package.json`（`{"dsh":{"bundle":{"patch":"./cordis.patch.yml"}}}`） |

> **出处**：本人核对（2026-09-16）——`tool-cordis` 的 `dsh` 字段 = `None`；`base` 的 = `{'bundle': {'patch': './cordis.patch.yml'}}`

**所以**：**`tool-cordis` 是"插件"，不是"bundle"**（这个坑你刚问过）。

---

## 五、声明方式：`package.json` 的 `dsh` 字段

> **出处**：`architecture.zh.md`（逐字）——*"两者都在各自的 `package.json` 中通过 `dsh` 字段声明自己：`dsh.profile` 列出一个 profile 的组合包，`dsh.bundle` 指向一个组合包的 patch 文件。"*

| 声明在 | 字段 | 含义 | 例子 |
|---|---|---|---|
| **profile 的 `package.json`** | `dsh.profile.bundles: [...]` | 这个 profile 叠哪些 bundle | `["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"]` |
| **bundle 的 `package.json`** | `dsh.bundle.patch: './cordis.patch.yml'` | 这个 bundle 的 patch 文件 | — |

**实测例**（`~/.dsh/profiles/web/package.json`）：
```json
{
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"],
      "patchReload": "live"
    }
  }
}
```

> **出处**：本人实测（2026-09-16）

---

## 六、五层组装顺序（回扣 09 篇）

> **出处**：`architecture.zh.md`（逐字）——*"各层按此顺序应用在空条目列表之上：先按 profile 列出的顺序应用每个组合包，然后是 profile 的 `cordis.patch.yml`，然后是 home 级的那份，最后是任意 `--patch` overlay。"*

```
空条目列表
  + ① profile.dsh.bundles[0]    的 patch   （如 dsh-base）
  + ② profile.dsh.bundles[1]    的 patch   （如 dsh-web-app）
  + ③ profile 的 cordis.patch.yml          （用户层）
  + ④ home 级 cordis.patch.yml             （全局用户层）
  + ⑤ 任意 --patch overlay                 （命令行）
= 最终插件树
```

**"后叠的覆盖先叠的"**——同 id 的行，**最后写的赢**。

> **出处**：`packages/bundle/base/cordis.patch.yml` 头注——*"the last write winning per row"*

---

## 七、关系图（一图记住）

```
┌─────────────────────────────────────────────┐
│ profile（~/.dsh/profiles/web/）              │  ← 你的"作品"
│   package.json: dsh.profile.bundles = [...]  │
└───────────────────┬─────────────────────────┘
                    │ 声明（叠哪些 bundle）
                    ▼
┌─────────────────────────────────────────────┐
│ bundle（packages/bundle/base/）              │  ← "积木袋"
│   package.json: dsh.bundle.patch = ./cordis.patch.yml │
└───────────────────┬─────────────────────────┘
                    │ 指向（哪里是它的 patch）
                    ▼
┌─────────────────────────────────────────────┐
│ patch（cordis.patch.yml）                    │  ← "施工单"
│   insert: [...] / - id: xxx  config: {...}   │
└───────────────────┬─────────────────────────┘
                    │ 插入 / 覆盖
                    ▼
┌─────────────────────────────────────────────┐
│ plugin（packages/xxx/ = package）            │  ← 一块块"积木"
│   apply(ctx) { ctx.tools.register(...) }     │
└─────────────────────────────────────────────┘
```

**一句话串起来**：
> **profile（你的组装）→ 声明用哪些 bundle（积木袋）→ 每个 bundle 有 patch（施工单）→ patch 往树里插入 plugin（积木，= package）。**

---

## 一页纸总结

| 概念 | 一句话 | 物理位置 | 出处 |
|---|---|---|---|
| **插件** | 实现 Service 的对象（`apply(ctx)`/`Service` 子类） | `packages/<域>/<名>/` | `cordis-primer:9` |
| **package** | npm 包（插件就是 package） | `packages/*/` | npm |
| **bundle** | 配置项+挂载代码的分发格式 | `packages/bundle/*/` | `architecture` |
| **patch** | 按 id 定位条目、替换/插入 | `cordis.patch.yml` | `architecture` |
| **profile** | Harness home 里的具名组装 | `~/.dsh/profiles/*/` | `architecture` |
| **声明** | `dsh` 字段 | `package.json` | `architecture` |
| **五层组装** | bundle[0]→[1]→profile→home→`--patch` | — | `architecture` |

## 踩坑预防

- **⚠️ `bundle` ≠ 插件**：靠 `package.json` 的 `dsh.bundle` 字段区分。（出处：实测）
- **⚠️ patch 是"替换"不是"合并"**：整行 config 被替换，要重述（09 篇踩过）。（出处：`architecture`）
- **⚠️ 同 id 的行"后叠赢"**：`--patch` 能盖过 profile patch。（出处：`base/cordis.patch.yml` 头注）
- **⚠️ profile 在 `~/.dsh/`，不在仓库里**：它是"用户环境产物"。（出处：`architecture`）

## 下一步

- **回扣各篇**：01 篇（插件即 `apply`）、03 篇（patch 叠层）、09 篇（profile 定制）
- **深水区 ③ 续**：多 Agent 协作
