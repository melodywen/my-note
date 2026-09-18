---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 深水区, dynamic-cordis, 自扩展, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 02 dynamic-cordis——让 Agent 运行时"自己写插件"

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：**阶段一（Cordis 内核）**——本块把内核能力"暴露到运行时"；回顾 08 篇（seam）
> - **本篇是深水区第 ② 块**：dynamic-cordis（运行时自扩展）
> - 写法说明：本系列采用**完整重讲式**；**已全流程实测成功**（含失败重试，见第八节）

> [!abstract] 本章是什么 / 该记住什么
> **性质**：**dsh 的"自引用"能力**——Agent 在**运行时**用工具**挂载/卸载"模型自己写的插件"**。
> **读完该记住 5 点**：
> 1. **它为什么存在**：dsh 一切皆插件，**但模型看不见自己身处的运行时**——这工具给了它"眼睛+手"（**自省 + 自改造**）
> 2. **日常用途**：**临时**工具/界面/自省——**"Agent 的临时草稿本"**（像 REPL，不是日常默认）
> 3. **代码放哪**：**内存**（能跑的）；**会话日志**（代码原文）——重启后能跑的没了，**要重新 define+run**（可**固化**成真插件）
> 4. **两个包配合**：`cordis-host-runner`（运行时/沙箱，**web 已自带**）+ `tool-cordis`（7 个 `cordis_*` 工具，**要显式加**）
> 5. **⚠️ 沙箱 ≠ 安全边界**：*"对待动态包要像对待 bash 访问一样"*

## 这一篇在讲什么

阶段一你学的 **Cordis 内核**（插件、`ctx`、effect）——那是"**开发者写插件**"。本篇是它的**自引用版本**：**让 Agent 在运行时，自己写插件、自己挂上**。

> **出处**：`practice/dynamic-cordis.zh.md`（逐字）——*"智能体可以检查当前 Cordis 进程，并在内存中挂载或卸载模型编写的插件。临时插件会在卸载或进程退出时消失。"*

**一句话**：**Agent 能"给自己加技能"**——写的插件**临时**（内存里），用完就消失。

> **Go 类比**：像**运行中的服务能动态 `Plugin.Open()` 加载 `.so`**——不重启就加能力。只不过这里"插件"是**模型现写的 JS**。

---

## 一、它为什么存在（意义）

**背景（一个讽刺）**：**dsh 里"一切都是 Cordis 插件"**——**但模型自己也跑在插件运行时里，却看不见、动不了它**。

> **出处**：Agent Note `2026-07-08-self-referential-cordis-toolset.zh.md`「问题」（逐字）——*"本 harness 中的一切都是 cordis 插件，**但运行在该插件运行时内部的 agent（智能体）既看不到也碰不到它**：它无法枚举周围的服务和事件，**无法在会话中途为自己添加新工具**，也无法组合自己发明的能力。赋予模型这种能力值得探索——**一个能审视并修改自身运行时的自引用 agent**。"*

**dynamic-cordis 就是补这个缺**：

| 为什么需要它       | 说明                                             |
| ------------ | ---------------------------------------------- |
| **① 补"盲区"**  | 模型**看不见自己身处的运行时**——这工具给了它"**眼睛**"（`inspect`）   |
| **② 临时扩展**   | "**对当前工作有用、但不该成为仓库插件**"的能力——**会话内现造现用**（不污染仓库） |
| **③ 自省/自进化** | **"审视并修改自身运行时"**——**Agent 自进化的雏形**（深水区第 ⑧ 块）   |

> **⚠️ 它不是"让模型随便执行代码"**（Agent Note 逐字）：*"本设计的核心正是回答这三个问题（注册时校验 / 先查约定 / 完全可释放），**而非单纯的「让模型执行代码」机制**。"*
> ——**精髓是"有约束的自改造"**，不是"裸执行"。

---

## 二、日常中它能干什么（实际用途）

**它是个"特种工具"**——**只在"临时扩展运行时"时用**，不是日常聊天就上。

### 官方划的**适用场景**

> **出处**：`tool-cordis/src/prompt.ts`（逐字）——*"考虑它是否有帮助，**仅当**用户**有意设计或创造某物**，或**一个临时界面能实质帮助当前工作**时。"*

| 日常场景     | 例子                                     |
| -------- | -------------------------------------- |
| **临时工具** | "做个**只在这个会话用**的小工具，把 X 转成 Y"           |
| **临时界面** | "给我个**临时面板**看这个数据的实时变化"（浏览器半）          |
| **自省**   | "看看现在 dsh 里有哪些服务 / 事件 / 工具"（`inspect`） |
| **试错探索** | "我想**试试**给 dsh 加个 X 能力"——**不用改仓库**     |

### ⚠️ 官方明确**"不该用"**的

> **出处**：`prompt.ts`（逐字）——*"Dynamic Cordis Plugins 是一种**可选的实现机制，不是每个请求的默认**。这些指令或工具的存在、以及关于 Cordis 本身的讨论，**不使一个请求成为动态插件任务**。"*

**所以**：**别把它当"万能"**——**只在"临时扩展运行时"时用它**。

### 一句话总结

> **当你想"临时给 dsh 加点能力 / 界面 / 工具，用完就扔、不改仓库"时用它。**
> **它就是"Agent 的临时草稿本"。**

> **Go 类比（回到你熟的）**：**像 REPL**——
> - 想试个函数 → **REPL 里现敲现用**（dynamic-cordis）
> - 确定要留 → **写进 `.go` 文件**（固化成插件，见第六节）
> - **REPL 一关 → 临时函数就没了**（内存、用完即弃）

---

## 三、动态插件的代码放哪？（内存 vs 磁盘）

**这是关键问题**：模型写的插件代码，**存哪了？重启还在吗？**

### 答案：**能跑的存内存；代码原文存"会话日志"**

> **出处**：`cordis-host-runner/README.zh.md:12`（逐字）——*"定义**只存在于进程内存中**，因此 **DSH 重启即清空，也不会向磁盘写任何东西**。"*

| 东西 | 放哪 | 重启后 |
|---|---|---|
| **能"跑"的定义**（内存注册表） | **内存** | ❌ **没了** |
| **代码"原文"** | **内存 + 会话日志**（`~/.dsh/sessions/*.jsonl`） | ✅ 日志还在（**历史记录**） |

> **出处**：`cordis-host-runner/README.zh.md:50`（逐字）——*"**会话日志保留一次 define 调用的参数——包括它提交的代码——以及回执；解析出的定义只存于内存注册表。**"*

**关键区别**：
- **日志里的代码** = **历史记录**（像"聊天记录里存了你发的一段代码"）
- **内存里的定义** = **真正在跑的插件**（**重启即消失**）

**重启后**：日志还在（能翻到"当时写过这个"），**但插件没了**——**要重新 `define` + `run`**。

> **⚠️ 官方明确**：*"系统绝不会自动恢复它们"*（README）。

### 能不能"固化"？（动态 → 静态）

**✅ 能**——**动态插件代码 = 一段标准 Cordis 插件代码**，可以"固化"成**真插件**（落盘、进仓库）。

**怎么做**（三步）：

| 步 | 做什么 |
|---|---|
| **① 拿到代码** | 从**会话日志**里读（`cordis_define` 提交的原文就在日志里） |
| **② 改写** | **`harness.defineTool(...)` → `ctx.tools.register(defineTool(...))`**（沙箱 facade → 真 API） |
| **③ 落盘 + 挂载** | 写进 `example/.../xxx.ts`，加 patch 层 |

**例**：你实测的 `hello_dynamic`，日志里的原文是：
```js
harness.defineTool({
  name: 'hello_dynamic',
  description: '返回来自动态插件的问候。',
  parameters: { type: 'object', properties: {}, additionalProperties: false },
  async execute(...) { ... }
})
```
**固化时改成**：
```ts
export const name = 'hello-dynamic'
export const inject = ['tools']
export function apply(ctx) {
  ctx.tools.register(defineTool({
    name: 'hello_dynamic',
    description: '返回来自动态插件的问候。',
    parameters: { type: 'object', properties: {} },
    async execute() { return '来自动态插件的问候！' },
  }))
}
```

**什么时候该固化**：

| 场景 | 该动态还是固化 |
|---|---|
| **一次性、试玩** | **动态**（临时，用完消失） |
| **确定要长期用** | **固化**（写进仓库/插件，永久） |

> **一句话**：**动态 = 内存里的"临时版"；固化 = 落盘的"永久版"。**

---

## 四、两个包（组合才有效）

> **出处**：`tool-cordis/README.zh.md`（逐字）——*"请与 host runner 一同组合；没有 runner，这些工具永远不会激活…web profile 已挂载 host runner 与浏览器侧组件，所以要显式地添加工具行。"*

| 包                              | 角色                                  | 默认挂了吗                                            |
| ------------------------------ | ----------------------------------- | ------------------------------------------------ |
| **`dsh-cordis-host-runner`**   | **运行时本体**：注册表 + `node:vm` 沙箱 + 运行往返 | ✅ **web-app 自带**（`web-app/cordis.patch.yml:122`） |
| **`dsh-cordis-client-runner`** | 浏览器半（装载页面代码）                        | ✅ web-app 自带（`:198`）                             |
| **`dsh-client-ui-cordis`**     | UI 面板（运行控件）                         | ✅ web-app 自带（`:269`）                             |
| **`dsh-tool-cordis`**          | **面向模型的 7 个工具**                     | ❌ **要显式加**                                       |

> **出处**：本人核对 `~/.nvm/.../dsh-web-app/cordis.patch.yml`（实测）

**关键结论**：**web profile 已自带 runner + UI，你只需加 `tool-cordis` 一行。**

### 官方 overlay（也加了端口）

> **出处**：`apps/cli/config/examples/cordis/cordis.yml`

```yaml
- id: webserver
  config: { host: 127.0.0.1, port: 3081 }   # 避开 3080
- insert:
    - id: cordis-host-runner
      name: '@deepseek-ai/dsh-cordis-host-runner'
    - id: tool-cordis
      name: '@deepseek-ai/dsh-tool-cordis'
```

**注意**：官方 overlay **重复挂了 host-runner**（web 已自带）——**最小化的话，只需加 `tool-cordis`**（见案例）。

---

## 五、7 个工具

> **出处**：`tool-cordis/README.zh.md`「工具能做什么」；源码 `tool-cordis/src/index.ts:45-355`

**3 个检查（只读）**：

| 工具 | 作用 | 源码行 |
|---|---|---|
| `cordis_inspect_list` | 列 Inspect Provider（host + client）及其查询方法 | `:45` |
| `cordis_inspect_query` | 查：服务方法 / 事件模式 / builtin 签名 / slot 树 | `:64` |
| `cordis_inspect_self` | 本会话的动态插件：版本指针 / 最近运行 / 源码诊断 | `:100` |

**4 个生命周期**：

| 工具 | 作用 | 源码行 |
|---|---|---|
| `cordis_define` | **登记一个包**（只校验参数+语法，**不运行、不审批**） | `:152` |
| `cordis_run` | **激活**（`mode: run' 首次/重启，'update' 切版本） | `:244` |
| `cordis_stop` | 停止运行（**保留**定义） | `:333` |
| `cordis_undefine` | 停止并**彻底移除** | `:355` |

**`cordis_define` 的两种模式**（README）：
- `plugin.kind: "new"` —— 新插件（配 3–6 字母的 `idPrefix`）
- `plugin.kind: "existing"` —— 既有插件的新版本（配 `pluginId`）

> **⚠️ 一个易混点**：源码里还有 `<cordis_dynamic_plugin_context>` 标签（`:514`）——**它不是工具**，是**用户输入 `@pluginId` 时注入的上下文消息**（让模型知道引用了哪个插件）。

---

## 六、典型工作流

> **出处**：`tool-cordis/README.zh.md`（逐字）——*"先检查、再定义、后运行"*

```
① cordis_inspect_query   ← 读包要用的服务/slot 的精确约定
② cordis_define          ← 记录源码（会话里出现 define 卡片）
③ cordis_run             ← 激活
   （失败后：cordis_inspect_self 读诊断 → 追加修正版 → update 到新版本）
```

**`@pluginId` 引用**：用户输入 `@pluginId` → 本包注入上下文消息，**钉住**所引用的插件 + 基准包 + 更新路径。

> **Go 类比**：像 **REPL 里 `:load`/`:reload`**——先看文档（inspect）、定义（define）、加载（run）、出错重载。

---

## 七、⭐ 边界（必须记住）

> **出处**：`tool-cordis/README.zh.md`「需要规划的边界」

| 边界 | 含义 |
|---|---|
| **会话为界、进程为本** | 包**只在定义它的会话**可见可控；**运行时可能影响同进程其他会话** |
| **只存内存** | **不写磁盘**；DSH 重启即清空 |
| **停止/移除/重启**都会清除 | — |
| **⚠️ 沙箱 ≠ 安全边界** | *"对待动态包要像对待 **bash 访问**一样，加载本插件时也要像授予 bash 工具那样慎重"* |

**沙箱做了什么**（`cordis-host-runner/README.zh.md`「信任立场」）：
- **Node 全局变量不存在**，或**重定向到 Cordis 服务**（`ctx.fs` / `ctx.web` / `ctx.bash` / 定时器 helper）
- host 半收到**不含框架内部机制的 façade**
- 但**它声明的服务仍会触达存活运行时**——所以**不是安全边界**

> **⚠️ 别把它当沙箱安全**：能触及 live 运行时 → 视同 **shell 访问权限**。

**`vmTimeoutMs`**：限制同步沙箱求值时长，默认 **`5000`**（`cordis-host-runner/src/index.ts:128`）。

---

## 八、动手：让模型写一个动态插件（已全流程实测成功）

> **规则（AGENTS.md）**：动手环节"你动手"。**本节已实测成功**（含失败重试，2026-09-16）。

### ✅ 第一步：基础设施加载成功

**最小组合**（只需加 `tool-cordis`，web 已自带 runner + UI）：

```yaml
# tool-cordis.patch.yml
- insert:
    - id: tool-cordis
      name: '@deepseek-ai/dsh-tool-cordis'
```

**实测**（`--dump-config`）：`tool-cordis` + `cordis-host-runner` + `cordis-client-runner` + `ui-cordis` **都在树里**；web 正常启动。

### 🔧 第二步：网页里让模型写插件

```sh
cd ~/ai-work/dsh/dsh-learn
./start.sh --patch "$PWD/example/deepwater/plugins/dynamic-cordis/tool-cordis.patch.yml"
```

**在网页对话框输入**：

> [!important] 📋 网页对话框输入这段（复制）
> ```
> 请用 cordis 工具做一个实验：
> 1. 先用 cordis_inspect_list 看看有哪些可查询的能力
> 2. 用 cordis_define 定义一个【新插件】，它注册一个工具 hello_dynamic，调用时返回 "来自动态插件的问候！"
> 3. 再用 cordis_run 激活它
> 4. 用 cordis_inspect_query 确认工具是否注册
> 5. 实际调用 hello_dynamic 验证返回值，最后汇总
> ```

### ✅ 第三步：实测结果（成功 + 完整的失败重试）

**模型自己走完了全流程**——含**3 次失败、第 4 次成功**：

| 包 | 结果 |
|---|---|
| `pkg-1` / `pkg-2` / `pkg-3` | ❌ **失败**（`parameters` schema 写错） |
| **`pkg-4`** | ✅ **成功** → `hello-1/pkg-4 is running (run-4).` |

**模型的原话（日志逐字）**：
> *"…error plus the first `additionalProperties` error tell me **`parameters` must be a proper object schema (omit `additionalProperties`)**. Let me define `pkg-4`:"*

**翻译**：`cordis_define` 报错说"parameters 必须是合法 object schema"——**模型自己看懂报错 → 修正 → 第 4 次成功**。

**最终**：`cordis_inspect_query` 确认 **`hello_dynamic` 出现在工具列表**；模型**实际调用它**，返回问候。

**模型用到的工具**（7 个全用了）：

| 工具 | 调用次数 |
|---|---|
| `cordis_inspect_list` | 6 |
| `cordis_inspect_query` | 26 |
| `cordis_inspect_self` | 2 |
| `cordis_define` | **22**（含重试） |
| `cordis_run` | 18 |
| `cordis_stop` | 2 |
| `cordis_undefine` | 2 |

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）；数据来自会话日志 `~/.dsh/sessions/.../session.v3.jsonl.zstd`

### 📖 这次实测教了我们什么

1. **"模型写插件"会失败几次**——但**机制容错**（`cordis_define` 报错**可读** + **可重试**）——**第 4 次成功**。
2. **报错质量很关键**：`"omit additionalProperties"` 这种**可指导**的报错，让模型**自己修**（这正是 Agent Note 说的"注册时校验"）。
3. **模型的"自省"很自然**：它**主动** `inspect_query`（26 次）**查约定**——**不用人教**（印证"先查后写"工作流）。

> **⚠️ 一个真实踩坑**：第一次 `define` 很容易把 `parameters` 写成非法 schema（多写了 `additionalProperties`）——**报错会指出**，改掉即可。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **dynamic-cordis** | Agent 运行时自写插件 | 动态加载 `.so` | `practice/dynamic-cordis` |
| **host-runner** | 运行时 + vm 沙箱（web 自带） | 插件宿主 | `web-app/cordis.patch.yml:122` |
| **tool-cordis** | 7 个 `cordis_*` 工具（要显式加） | — | `tool-cordis/src/index.ts` |
| **3 检查工具** | inspect_list/query/self | 查文档 | `:45/64/100` |
| **4 生命周期** | define/run/stop/undefine | load/reload/unload | `:152/244/333/355` |
| **工作流** | inspect → define → run | REPL `:load` | README |
| **边界** | 会话为界/内存/重启清空 | — | README |
| **沙箱 ≠ 安全边界** | 视同 bash 访问 | — | `cordis-host-runner` README |
| `vmTimeoutMs` | 同步求值上限，默认 5000 | — | `:128` |
| **为什么存在** | 补"模型看不见自己运行时"的盲区（自省+自改造） | — | Agent Note |
| **日常用途** | 临时工具/界面/自省——"Agent 的临时草稿本" | REPL | `prompt.ts` |
| **代码放哪** | 内存（能跑的）+ 会话日志（原文）；可固化 | REPL→写 `.go` | `host-runner` README |
| **实测** | ✅ 全流程成功（`pkg-1~3` 失败 → `pkg-4` 成功） | — | 本人实测 |

## 踩坑预防

- **⚠️ 沙箱不是安全边界**：能触及 live 运行时，**按 bash 权限对待**。（出处：`cordis-host-runner` README）
- **⚠️ web 已自带 runner**：别重复挂 `cordis-host-runner`（官方 overlay 挂了，会重复但要避免）——**只加 `tool-cordis` 即可**。（出处：实测）
- **⚠️ 只存内存**：重启即消失，别指望持久化（要持久用 03 篇的 storage）。（出处：README）
- **⚠️ `cordis_define` 不运行**：它只校验语法——**要 `cordis_run` 才激活**。（出处：README）
- **⚠️ `parameters` schema 极易写错**（实测）：多写 `additionalProperties` 会报 `"parameters must be a proper object schema (omit additionalProperties)"`——**报错会指出，改掉即可**（模型自己修了 3 次）。（出处：本人实测）
- **⚠️ 动态插件"重启即消失"**：别指望它持久；要长期用就**固化**成真插件。（出处：README + 第三节）

## 下一步

- **深水区 ③**：多 Agent 协作（Subagent / Goal / Workflow）
- **深水区 ④**：mini-dsh 从零（综合检验）
