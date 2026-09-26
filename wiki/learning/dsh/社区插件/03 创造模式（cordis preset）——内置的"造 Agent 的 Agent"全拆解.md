---
type: reference
status: done
area: growth
tags: [learning, dsh, cordis, agent-preset, 创造模式, 内置, 自引用, 有出处]
created: 2026-09-26
updated: 2026-09-26
---

# 03 创造模式（cordis preset）——内置的"造 Agent 的 Agent"全拆解

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（本机 master，2026-09 fetch）
> - preset 目录：`packages/preset/agent-presets/presets/cordis/`
> - 工具集：`packages/extensions/tool-cordis/`
> - 触发：dsh Web UI 的 Agent 选择器里那张「创造模式（内置）」卡片

## 这篇在讲什么

UI 里的「创造模式」卡片（namespace 是 `cordis`）：

> **用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。**

它**不是社区插件**——是 dsh 官方内置的 4 个 Agent preset 之一。但它是整个 preset 体系里最特殊的一个：**一个能读取并修改自己所在运行时的 Agent**，官方给它的定位就是"让 Agent 帮你造另一个 Agent"。

本文把它在源码里的**全部家当**扒出来：组装文件、人格提示词、7 个工具、2 个 skill、信任边界声明。

> **Go 类比**：普通 preset 是"按 docker-compose 起一个容器"；创造模式是**给容器里塞了一个能读写这份 docker-compose、还能当场挂新 sidecar 的运维 Agent**。自引用（self-referential）是它和标准模式唯一的本质区别。

---

## 一、全景：dsh 内置 4 个 preset

> **出处**：`packages/preset/agent-presets/presets/` 目录——`cordis`、`minimal`、`ptc`、`standard` 四个目录各一个 preset；README——*"The shipped Web `standard`, `ptc`, and `cordis` presets include explicit file delivery. The `minimal` preset keeps its fixed two-tool training configuration."*

| preset | 定位 |
| --- | --- |
| `standard` | 标准编码 Agent（全量能力的基准） |
| `ptc` | 带 PTC（Programmatic Tool Calling）工作流 |
| `minimal` | 固定双工具的极简训练配置 |
| **`cordis`（创造模式）** | **standard 全量 + 自引用 cordis 工具集 + 组装创作 skill** |

官方源码注释（`agent.cordis.yml` 头部）原话：

> *"The `cordis` agent preset: the standard coding agent, plus the ability to read and write the runtime it is running in. **It exists so a person can ask an agent to author another agent.** Everything in `standard` is here unchanged; what is added is the self-referential Cordis toolset, a skill that teaches composition authoring, and a persona that says which of the two planes an edit belongs to."*

**翻译**：cordis preset = standard 原封不动 + 三样增量——①自引用工具集 ②教写组装的 skill ③讲清"两架飞机"的人格提示词。

---

## 二、文件构成：一个 preset 目录里有三样东西

```
packages/preset/agent-presets/presets/cordis/
├── preset.yml                  # 元数据（UI 卡片显示的名称/描述）
├── agent.cordis.yml            # 组装本体（273 行，插件的逐行清单）
└── skills/
    ├── cordis-plugin-development/SKILL.md      # 420 行：动态插件开发指南
    └── editing-cordis-compositions/SKILL.md    # 165 行：preset/组装创作指南
```

> **出处**：`editing-cordis-compositions` skill——*"A preset is a directory holding one `agent.cordis.yml`, optionally beside a `preset.yml` carrying display metadata — `name` and `description` (and, for shipped presets, a roster `order`). A preset without it shows up in every picker as its bare directory name."*

### preset.yml（完整原文，就 3 行）

```yaml
name: 创造模式
description: 用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。
order: 4
```

这就是 UI 卡片上那两行字的出处。`order: 4` 决定它在选择器里的排序。

---

## 三、agent.cordis.yml：插件清单逐行解析

这个文件是 **Cordis 组装（composition）**——每个能力都是一行插件。官方注释直接写明结构原则：

> *"Two planes decide where an edit belongs. The **HOST composition** holds the registries and anything shared across sessions — persistence, the sandbox and approval stack, the model route, the subagent registry and its backends. An **AGENT PRESET** holds what one session contributes to those registries: its tools, its persona, its prompt sections."*

### 两架飞机（Two Planes）——读懂这份清单的钥匙

| | HOST 组装 | AGENT PRESET |
| --- | --- | --- |
| **生命周期** | 进程级，一份 | 会话级，随会话挂载/卸载 |
| **放什么** | 注册表本身、持久化、沙箱/审批栈、模型路由、subagent 注册表 | 该会话贡献的工具、人格、提示词段落、压缩策略 |
| **判断标准** | 跨会话共享的、有会话外消费者的 | 只有这个 Agent 自己用的 |

> **Go 类比**：HOST 是 `main()` 里装配好的全局单例（连接池、注册表）；preset 是每个请求传入的 handler 依赖包。**判据不是"感觉上像不像 Agent 相关"，而是"是否必须共享"**——skill 原话：*"the choice is not about how 'agent-related' something feels — it is about whether the thing must be shared."*

### 全部行清单（按文件顺序）

| id | 包名 | 架（isolate realm） | 说明 |
| --- | --- | :---: | --- |
| `persona` | `dsh-persona` | — | 人格提示词（见第四节） |
| `agent-instructions` | `dsh-agent-instructions` | — | 用户自定义指令，`maxBytes: 65536` |
| `tool-bash` | `dsh-tool-bash` | — | bash 工具（win32 禁用） |
| `tool-pwsh` | `dsh-tool-pwsh` | — | pwsh 工具（仅 win32） |
| `tool-fs` | `dsh-tool-fs` | — | 文件读写 |
| `tool-fs-search` | `dsh-tool-fs-search` | — | 文件搜索，`sampleOverCapGlobResults: false` |
| `tool-jobs` | `dsh-tool-jobs` | — | 后台任务控制（**注册表留在 HOST**） |
| `command-goal` / `tool-goal` | `dsh-command-goal/-tool` | — | 目标系统（服务留在 HOST） |
| `planning`（group） | `dsh-plan-mode` | ✅ `planMode` | 计划模式，内嵌 6 段规则提示词 |
| `compaction`（group） | `dsh-compaction-basic` + `command-compact` + `tool-result-pruner` | ✅ `compaction` + `toolResultPruner` | 压缩策略；pruner 阈值 8192/4096/1024 字符 |
| `delegation`（group） | subagent 三件套 + workflow 两件套 + ralph | ✅ `workflowEngine` | 委派与工作流（见下） |
| `tool-ask-user` | `dsh-tool-ask-user` | — | 向用户提问 |
| `tool-todo` | `dsh-tool-todo` | — | 待办，`allowParallelInProgress: true` |
| `tool-web` | `dsh-tool-web` | — | `fetch: true`、`searchTimeoutMs: 60000` |
| **`tool-cordis`** | **`dsh-tool-cordis`** | — | **自引用工具集（本 preset 的灵魂，见第五节）** |
| `skill-filesystem` | `dsh-skill-filesystem` | — | 挂载本 preset 自带的 `skills/` 目录 |
| `tool-skill` | `dsh-tool-skill` | — | 技能加载工具 |
| `present` | `dsh-tool-present` | — | 文件交付 |

### delegation 组的细目（7 行）

| id | 配置 | 状态 |
| --- | --- | :---: |
| `tool-subagent-control` | 子代理控制 | 启用 |
| `tool-subagent-list-agents` | 列出可用 Agent | 启用 |
| `tool-subagent`（spawn） | `toolName: subagent`，可选模型，后台可续 | 启用 |
| `tool-subagent-fork`（fork） | `toolName: subagent_fork`，**不选模型**——保持与父会话同模型，历史可复用 KV Cache | 启用 |
| `tool-subagent-codex` | Codex 后端 | **禁用** |
| `tool-subagent-claude-code` | Claude Code 后端 | **禁用** |
| `tool-ralph` | Ralph 循环，`maxRounds: 64` | **禁用** |

> **出处**：文件注释——*"Fork omits model selection so provider/model stay equal to the parent and the inherited history remains eligible for KV Cache reuse."* / *"Production dsh does not install these optional providers. Install the matching Bundle in this Profile and restart the Host, then copy this preset and remove `disabled`."* / *"the tool description restricts `ralph` to runs the human explicitly asked for, and completion is a worker self-report, not an independent evaluation."*

### 架（isolate realm）为什么只在三处出现

这是 `editing-cordis-compositions` skill 里"**最能抓人的规则**"：

> *"**A row that publishes a service may not sit loose in a preset.** Registering a service without an isolate realm puts it in the process-global realm, so the second session mounting that preset collides with the first. The mount rejects it rather than letting the collision surface later."*

- **提供服务的行必须包进 group + isolate**（如 `planning` 提供 planMode、`compaction` 提供压缩策略、`delegation` 提供 workflowEngine）——否则第二个挂载该 preset 的会话会在进程全局 realm 里撞车
- **只消费的行必须留在 realm 外**（如 `tool-bash`、`tool-jobs`、`tool-goal`）——包进 realm 反而解析不到 HOST 上的实例，"contributes nothing"
- `isolate: true` = 每个挂载会话一份私有实例；字符串标签 = 多个 subtree 共享一个命名 realm（**preset 不需要这个**，因为 provide() 第二次注册仍会抛错）

> **Go 类比**：isolate realm 就是**每请求一个依赖注入容器**。提供者（`fx.Provide`）必须放在请求作用域容器里；只消费全局单例的 handler 要留在容器外，否则它拿到的是容器里那个永远没被塞进去的空槽。

---

## 四、persona：人格提示词全文要点

`persona` 行的 prefix 逐段翻译（源码 L21-30）：

1. **身份**："You are a coding agent powered by the `{{model}}` model, running on the DeepSeek Harness."（`{{model}}`/`{{cwd}}` 从 Agent 自己的路由和工作区解析）
2. **自引用声明**："You can read and modify the harness you run on. Its composition is Cordis: **every capability is a plugin row in a `cordis.yml`, and an agent preset is one such file mounted for a single session.**"
3. **两架飞机判据**（同上表）
4. **preset 的家**："Presets you author live one directory per preset under `${DSH_HOME:-$HOME/.dsh}/.agent-presets/<id>/`; the roster reports each preset's real path…"
5. **红线**："**NEVER edit or delete the shipped preset install** … corrupting the `cordis` preset would disable this very mode. To change what a shipped preset does, **copy its composition into a new preset directory and edit the copy.**"
6. **动手前**："Load the `editing-cordis-compositions` skill before writing or changing a composition."

---

## 五、tool-cordis：自引用工具集（7 个工具）

> **出处**：`packages/extensions/tool-cordis/src/index.ts`；`docs/tool-catalog.zh.md` L30——*"不在任何随产品发布的树中，需要显式选择启用；动态 Package 代码可以访问真实运行时…该工具集注入 `@deepseek-ai/dsh-cordis-host-runner` 提供的 `ctx.dynamicCordisRunner`，后者拥有定义注册表和 vm 沙箱；组合缺少它时这些工具不会激活。"*

| 工具 | 用途 | 关键参数/行为 |
| --- | --- | --- |
| `cordis_inspect_list` | 一次性列出 Host/Client 全部 Inspect Provider、方法与 schema | 禁止硬编码 Provider 名 |
| `cordis_inspect_query` | 按精确 `platform + provider + method` 查 Service 方法、Event mode、Builtin 签名、Slot 树、Theme token、Tool schema | Client 查询等首个有效页面响应，保持 pending |
| `cordis_inspect_self` | 列当前 Plugin、看版本指针、读精确 Package 源码与诊断 | `pluginId + packageId` 都传才返回源码 |
| `cordis_define` | 为新 Plugin 建首个 Package，或给既有 Plugin **追加不可变 Package** | **只定义不运行**；`idPrefix` 3-6 个小写字母 |
| `cordis_run` | 激活精确 Package：`run` = 首次激活/重启/回滚，`update` = 切版本 | 未授权 → `awaiting-approval`；已授权 → `starting` 异步完成 |
| `cordis_stop` | 暂停当前 Run，保留定义、授权、版本指针 | 不等于删除 |
| `cordis_undefine` | **永久**删除 Plugin 及全部 Package | 确认不再需要才用 |

### 版本模型（tool-cordis 的核心概念）

| 标识 | 含义 |
| --- | --- |
| `pluginId` | Plugin 稳定实例，可长期修改 |
| `packageId` | 一个**不可变**的 Host/Client 代码版本；改代码 = 新增 Package，永不覆盖 |
| `pluginRunId` | 一次激活尝试，串联审批、加载、私有 RPC、Run 卡片、错误 |
| `currentPackageId` | 最近一次**完整成功**的 Package；停止/更新失败不清除 |
| `nextPackageId` | 待审批/尝试中/待 Client 激活/最近失败的 Package |

run/update 模式决策表（源码 `cordis-plugin-development` skill）：

| 当前状态 | 目标 | mode |
| --- | --- | --- |
| 无 current | 任意 Package | `run` |
| 有 current | 同一 Package | `run` |
| 有 current | 不同 Package | `update` |
| 更新失败 | `nextPackageId` | `update` 重试 |
| 更新失败 | `currentPackageId` | `run` 回滚 |

> **历史沿革**：这套 7 工具 API 之前是 `cordis_inspect` / `cordis_mount` / `cordis_unmount` 三件套（设计笔记 `2026-07-08-self-referential-cordis-toolset.zh.md`）——mount 直接在 `node:vm` 沙箱求值临时插件，挂内部 `cordis-dynamic` 分组，id 形如 `dyn-1`。现版本演进为 define/run 版本化模型 + 持久化审批，但设计笔记里的**沙箱语义、信任姿态、替代方案论证**仍然有效。

### 信任边界（TRUST）——官方红字

`agent.cordis.yml` 头部注释：

> *"**TRUST**: `cordis_mount` evaluates model-written JavaScript against the live runtime, and a composition this agent writes becomes a preset other sessions mount. **Treat a session on this preset as shell access** — the toolset's own documentation makes the same statement."*

设计笔记（中文版）：

> *"vm 隔离了意外的全局污染…但二者都不限制已暴露服务的权限：临时插件可以调用 `ctx.shell` 以宿主执行器的权限运行命令，也能访问真实的文件系统和网络服务…这是一个需要显式启用的开发工具，**信任等级与 bash 相当，不是安全边界**，也不是产品默认配置。"*

> **Go 类比**：这等于给 Agent 一个 `go plugin.Open()` 但没有 seccomp——它能干什么取决于你的进程能干什么。**挂在创造模式下的会话 = 把 shell 交出去**，官方在三个地方（preset 头注释、tool 描述、skill）重复了同一句话。

---

## 六、两个内置 skill

### ① `cordis-plugin-development`（420 行）——动态插件开发指南

面向"用 tool-cordis 写临时插件"的完整手册，核心内容：

- **标准工作流七步**：`inspect_list` 摸底 → `inspect_query` 查精确契约 → `inspect_self` 读基线 → 写 JS → `define` → `run` → 处理审批/等待/渲染失败 → `stop`/`undefine`
- **平台选择表**：文件/命令/进程/网络/Agent/Session → Host；主题/布局/页面状态/Tool 卡片 → Client；Host 取数 Client 展示 → 两者（`harness.handle` + `host.call`）
- **六个 Inspect Provider 导航**：`Service.listService`、`Event.listEvents`、`Builtin.listBuiltins`、`Slots.listSubTree`、`Theme.listTokens`、`Tool.listTools`
- **代码规约**：纯 JavaScript（禁 TS/JSX/import/require，React 必须 `React.createElement`）；`ctx.get()` 默认 + 判空，`inject` 只给硬依赖；副作用必须可释放（`ctx.effect()`/`ctx.on()`）；定时器是 Service 不是全局（`inject: ['timer']`）；Waterfall 监听器必须调 `next()`
- **Slot 注册协议**：先查 compact 树选目标，再查精确 root 拿 `single/list/keyed/chain` 协议与 props；禁止默认抢 `root`/`sidebar`/`conversation` 整块
- **高频失败检查表**：`service "x" is not declared` → 忘了 inject；Client 解析失败 → 用了 JSX/TS；UI 报错 → 查 `client-render` 诊断并 define 新 Package 修复

### ② `editing-cordis-compositions`（165 行）——组装/preset 创作指南

面向"造一个新 preset"的流程手册，核心内容：

- **Off-limits**：永远不编辑/删除/覆盖随部署发布的 preset（`standard`/`ptc`/`minimal`/`cordis`）——升级会覆盖、写坏 cordis 会废掉创造模式本身；**要改就 copy 一份改副本**
- **作者流程五步**：`copy(from, id, name)` 起步（校验 id `[a-z0-9][a-z0-9-]*`、自动改写 `preset.yml`、失败回滚）→ 预期文件沙箱对每次写入要求提权（批量写，一个 heredoc 一个文件）→ 补 `description` → 逐行编辑 `agent.cordis.yml` → 挂载验证
- **roster 服务**：`ctx.agentPresets` 的 `list()` / `read(id)` / `copy()` / `standingKeyFor(id)`；用 `cordis_mount` 临时插件注册自用工具把结果带回来
- **验证手段**：`standingKeyFor(id)` 真实组装子树，能抓四类失败——包解析失败 / 配置非法 / 行未激活 / 服务发布进全局 realm（两种报错文案都点名服务）；**别信 `list()` 的 `broken` 字段**（只是文件形状检查）；`cordis_inspect` 只报**当前会话**的组装，验证不了你的新 preset
- **产品级 subagent**：Codex/Claude Code 是独立可选 Bundle，装了并重启 Profile 才有 provider；preset 里只放禁用模板行，按需去 `disabled`

> **Go 类比**：skill ① 是"如何用反射在运行时给自己注册新 handler"的说明书；skill ② 是"如何改 go.mod + wire 的 provider set 再起一个新服务"的说明书。两者的共同前提：**动手前先 inspect，禁止靠名字猜 API**。

---

## 七、CORDIS_SYSTEM_PROMPT：工具集注入的系统提示词

`packages/extensions/tool-cordis/src/prompt.ts`（107 行）注入 `TOOL_CORDIS` 提示词段，要点：

- **定位**："Dynamic Cordis plugins temporarily extend the current DSH process…definitions do not survive a process restart"；"The restricted execution environment prevents accidental misuse; **it is not a security boundary**"
- **别滥用**："Dynamic Cordis Plugins are **one available implementation mechanism, not the default for every request**"——只有用户想设计/创造东西、或临时界面确实有实质帮助时才考虑；出现这些工具/讨论 Cordis 本身 ≠ 这是个 Cordis 任务
- **问一次就动手**：意图/Lifetime 模糊时最多问一个简短问题；设计方向影响结果时最多问一个方向性选择题，禁止多轮访谈
- **审批协议**：`awaiting-approval` → 告知用户去 UI 批准，**不要等待/重试/谎称在跑**；`starting` ≠ 成功；用户拒绝后**不得再次申请**；技术失败后从诊断修复同一个 Plugin，不悄悄另起炉灶
- **@pluginId 协议**：注入的上下文只有身份/版本指针/默认基线 Package，**没有源码**——先 `inspect_self` 读源码，再 `define kind:'existing'` 追加 Package，绝不静默新建同名 Plugin

---

## 八、UI 入口与使用路径

> **出处**：`packages/client/ui-agent-preset/src/client/locales.ts`

| UI 文案 | 场景 |
| --- | --- |
| "预设即一个会话的 Agent 所运行的插件组装——它的工具、提示词与能力。复制一份既有预设改成自己的，或**用「创造模式」让 Agent 帮你创建**。" | preset 管理页 |
| "**用「创造模式」创作自定义预设**" | 创建按钮 |
| "**请先开启 Agent 模式选择，再启动创造模式**" | 前置条件提示 |

端到端流程：开启 Agent 模式选择 → 选「创造模式」起会话 → 对 Agent 说"帮我造一个 xxx 的 preset" → Agent 加载 `editing-cordis-compositions` skill → `copy()` 复制 standard → 逐行改组装 → `standingKeyFor` 挂载验证 → 让你起一个真会话确认工具清单。

---

## 九、一图总结

```
创造模式（cordis preset）
├── = standard 全量 + 三样增量
│   ├── tool-cordis：7 工具（inspect_list/query/self, define/run/stop/undefine）
│   │     └── 版本模型：pluginId → packageId（不可变）→ pluginRunId
│   ├── 2 个 skill：写临时插件（420 行）/ 改组装造 preset（165 行）
│   └── persona：两架飞机（HOST 组装 vs AGENT PRESET）+ 复制再改红线
├── 架（isolate realm）规则
│   ├── 提供服务的行 → 必须 group + isolate（planning/compaction/delegation）
│   └── 只消费的行 → 必须留在 realm 外（tool-bash/tool-jobs/tool-goal）
└── 信任姿态：TRUST——「挂载中的会话 ≈ shell 访问」，不是安全边界
```

**一句话**：**创造模式 = dsh 把"元工具"做成了官方 preset——Agent 能读写它自己脚下的运行时，并用这套能力替你造下一个 Agent**。它和 [[02 modlens 视觉插件——为什么 dsh-learn 不需要它|modlens]] 这类社区插件的区别在于：社区插件给 Agent 加"一种能力"，创造模式给 Agent 加"获得任意能力的元能力"。

---

## 出处汇总

| 内容 | 路径 |
| --- | --- |
| preset 元数据 | `packages/preset/agent-presets/presets/cordis/preset.yml` |
| 组装本体（273 行） | `packages/preset/agent-presets/presets/cordis/agent.cordis.yml` |
| 动态插件开发 skill | `presets/cordis/skills/cordis-plugin-development/SKILL.md` |
| 组装创作 skill | `presets/cordis/skills/editing-cordis-compositions/SKILL.md` |
| tool-cordis 源码 | `packages/extensions/tool-cordis/src/index.ts` + `prompt.ts` |
| 自引用工具集设计笔记 | `.agents/notes/implemented/feature/2026-07-08-self-referential-cordis-toolset.zh.md` |
| 工具目录 | `docs/tool-catalog.zh.md`（L30、L744 起） |
| agent-presets README | `packages/preset/agent-presets/README.md` |
| UI 文案 | `packages/client/ui-agent-preset/src/client/locales.ts` |
| 相关笔记 | [[00 社区插件全景——4312 个插件、23 个分类]] |