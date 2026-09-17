---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 动手实验, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 实验07 亲手跑通《进入 Harness》——把前六章的模式用到真实工具系统上

> [!info] 版本锚点
> - 对应官方：`docs/cordis-tutorial/07-into-the-harness.zh.md`
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 本次实测依赖：`dsh-brand` / `dsh-tools` / `dsh-llm` / `dsh-system-prompt` 均 `0.0.1-rc.1`（+ 若干 peer）
> - 前置：读完《01》《附》《附2》《实验02–06》
> - **本文是动手文档**：你照着**贴代码、跑命令**，我负责讲清楚每个现象为什么发生
> - **本讲是七讲收官**——把前面所有模式用到真实的 harness 服务上

## 这个实验要验证什么

一句话：**验证"前六章学的模式，组合起来就能接入真实 harness"——注册一个模型可调用的工具，走真实工具流水线，用事件观察结果。**

官方原话：

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`——*"本章会向 harness 的 `tools` 服务注册一个可由模型调用的工具，通过 harness 工具流水线执行它，并观察结果事件。整个示例无需密钥，也不会调用模型。"*

**收官的意义**：`greet-tool.ts` 里的**每个模式都来自前几章**（官方第 50 行明说）。这一章就是把前面所有积木**拼成一个真实能力**。

| 前几章学的 | 在 07 讲哪用到 |
|---|---|
| 03 服务 + `inject` | `inject: ['tools']` 等待工具注册表就绪 |
| 02 effect | `ctx.tools.register(...)` 的 disposer 附着插件，卸载即注销 |
| 04 事件 | `ctx.on('tools/result', ...)` 观察工具调用 |
| 04 声明合并 | `import type {} from '@deepseek-ai/dsh-tools'` |

用你的 Go 经验类比：前面几章像学**单独的语法特性**，07 讲是**写一个完整的接口实现**（注册一个真实的 service/tool）。

---

## 先讲理论（动手前必读）

### 概念① 工具 = 注册到 `tools` 服务的具名能力

```ts
export const inject = ['tools']              // ← 03 讲：等工具注册表就绪

export function apply(ctx: Context) {
  ctx.tools.register(defineTool({            // ← 02 讲：注册即 effect
    name: 'greet',
    description: 'Greet the named person.',
    parameters: {
      name: { type: 'string', required: true, description: 'Who to greet' },
    },
    output: {
      schema: { type: 'string' },
      render: (_args, value) => [{ type: 'text', text: value }],
    },
    async execute(args) {
      return `Hello, ${args.name}!`
    },
  }))
}
```

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`——*"`inject: ['tools']`（第 3 章）会让插件等待工具注册表就绪；`ctx.tools.register(...)` 会把注册 disposer 附着到插件（第 2 章），因此卸载时会注销工具。"*

**三条要点**（官方第 50 行）：
- `defineTool` 把 `parameters` 规约**转成向模型展示的 JSON Schema**，并**推导 `args` 类型**；
- 在 `execute` 运行前**校验模型提供的参数**；
- 工具返回 `output.schema` 声明的**规范值**，`output.render`（Native renderer）另行生成**可持久化的结果内容**。

Go 类比：`defineTool` 像**一个带 JSON Schema 校验 + 类型推导的 handler 定义**——比裸写 HTTP handler 多了"给模型看的 schema"和"结果渲染"两层。

### 概念② 事件观察：`tools/result`

```ts
ctx.on('tools/result', (exec, result) => {   // ← 04 讲：事件监听
  const text = result.content
    .map(block => (block.type === 'text' ? block.text : ''))
    .join('')
  console.log(`[tool-logger] ${exec.name} -> ${text}`)
})
```

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`——*"`import type {} from '@deepseek-ai/dsh-tools'` 行会引入该包的声明合并，使 `'tools/result'` 及其 payload 具有类型。这与第 4 章导入 `stats.ts` 的做法相同，只是扩展到了包级别。"*

**关键**：`tool-logger` 和 `greet-tool` **互不知道对方存在**——它们由**注册表服务 + 事件**连接（官方第 95 行）。这正是 03（服务）+ 04（事件）组合的价值。

### 概念③ 组合运行：`tools` 需要 `systemPrompt` 提供方

```yaml
- name: '@deepseek-ai/dsh-system-prompt'
- name: '@deepseek-ai/dsh-tools'
- name: './tool-logger.ts'
- name: './greet-tool.ts'
```

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`——*"`@deepseek-ai/dsh-tools` 会注入 `systemPrompt` 服务，因为工具需要向系统提示词贡献 schema，所以组合中也要列出该服务的提供方。缺少提供方时，工具插件会像第 6 章所述那样保持 PENDING。"*

**回环**：这句话直接把 06 讲的 PENDING 机制用上了——**忘了挂 `system-prompt`，工具插件就静默 PENDING**。

### 概念④ 从这里到完整 agent

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`——*"真实 agent 就是这套组合再加上更多插件：LLM 适配器、agent loop、持久化和应用入口。"*

即：**你刚跑通的，就是 agent 的"工具层"骨架**；完整 agent = 这个 + LLM + 循环 + 存储。

---

## 第 1 步：准备课时目录（本讲依赖最多，有坑）

```sh
cd ~/ai-work/dsh/test_workspace/cordis-tutorial
mkdir -p lesson-07-harness && cd lesson-07-harness
cp ../lesson-02-lifecycle/{bin.js,package.json,package-lock.json} .
```

本讲依赖 `dsh-*` 系列包，**npm 直接装会连遭两个坑**：

### 坑 A：peer 依赖冲突 → 必须 `--legacy-peer-deps`

```sh
npm install --legacy-peer-deps \
  @deepseek-ai/dsh-brand@0.0.1-rc.1 \
  @deepseek-ai/dsh-tools@0.0.1-rc.1 \
  @deepseek-ai/dsh-llm@0.0.1-rc.1 \
  @deepseek-ai/dsh-system-prompt@0.0.1-rc.1
```

> **根因**：`dsh-tools@0.0.1-rc.1` peer 要 `dsh-agent@^0.0.1-rc.1`，但 npm 上 `dsh-agent` 只有 `0.1.0-rc.6`——**版本链对不上**（Developer Preview 迭代快的通病）。
> **出处**：本人实测（2026-09-16）——不加 `--legacy-peer-deps` 报 `ERESOLVE unable to resolve dependency tree`

### 坑 B：peer 依赖要手动补（npm 不会自动装 peer）

`--legacy-peer-deps` 装完后，运行时仍报 `Cannot find package '@deepseek-ai/dsh-xxx'`。需**循环补齐**所有缺失 peer：

```sh
npm install --legacy-peer-deps \
  @deepseek-ai/dsh-scope@0.0.1-rc.1 \
  @deepseek-ai/dsh-session@0.0.1-rc.1 \
  @deepseek-ai/dsh-invariants@0.0.1-rc.1 \
  @deepseek-ai/dsh-code-runtime@0.0.1-rc.1 \
  @deepseek-ai/dsh-user-approval@0.0.1-rc.1 \
  @deepseek-ai/dsh-timeout@0.0.1-rc.1
```

> **出处**：本人实测（2026-09-16）——缺失项是递进的：`dsh-scope` → `dsh-timeout`，需逐个补齐
> **提示**：遇到 `Cannot find package '@deepseek-ai/dsh-xxx'`，就 `npm install --legacy-peer-deps @deepseek-ai/dsh-xxx@0.0.1-rc.1`，重复直到不再报。

---

## 第 2 步：写工具插件 `greet-tool.ts`

**⚠️ 官方代码用了 npm 版不存在的 API，需改一处**（见下方说明）：

```ts
import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'
import { CallId } from '@deepseek-ai/dsh-llm'   // ← 官方是 brandString<ToolCallId>，见下

export const name = 'greet-tool'
export const inject = ['tools']

export function apply(ctx: Context) {
  ctx.tools.register(defineTool({
    name: 'greet',
    description: 'Greet the named person.',
    parameters: {
      name: { type: 'string', required: true, description: 'Who to greet' },
    },
    output: {
      schema: { type: 'string' },
      render: (_args, value) => [{ type: 'text', text: value }],
    },
    async execute(args) {
      return `Hello, ${args.name}!`
    },
  }))

  void (async () => {
    const result = await ctx.tools.execute({
      callId: CallId('demo-1'),          // ← 官方：brandString<ToolCallId>('demo-1')
      name: 'greet',
      arguments: { name: 'Cordis' },
      signal: new AbortController().signal,
    })
    console.log('tool replied:', JSON.stringify(result.content))
  })()
}
```

> [!warning] ⚠️ 版本差异：`brandString` / `ToolCallId` 的可用性**随版本变化**（重要教训）
> 官方示例写：
> ```ts
> import { brandString } from '@deepseek-ai/dsh-brand'
> import type { ToolCallId } from '@deepseek-ai/dsh-llm'
> // ...
> callId: brandString<ToolCallId>('demo-1'),
> ```
>
> **🕐 当时（2026-09-16，`dsh-brand@0.0.1-rc.1`）——官方写法不可用**：
> - `dsh-brand@0.0.1-rc.1` **运行时不导出任何东西**（纯类型包）
> - 直接 import `brandString` 报：`SyntaxError: ... does not provide an export named 'brandString'`
> - 当时的变通：用 `dsh-llm` 的 `CallId` 工厂 → `CallId('demo-1')`
>
> **✅ 现在（2026-09-16 复核，`dsh-brand@0.1.5-rc.2`）——官方写法已可用**：
> - `dsh-brand` 的 `lib/index.js` **已有 `function brandString(value)` 运行时实现**（`lib/types/index.d.ts` 也 `export declare function brandString`）
> - 实测 `import { brandString } from '@deepseek-ai/dsh-brand'` **成功**，`typeof === 'function'`
> - 且 `dsh-llm` 现在导出 **`ToolCallId`**（函数，不叫 `CallId` 了）——`brand.d.ts:25,31`
>
> **📌 结论**：dsh 是 Developer Preview，**包导出会跨版本变化**。**本文的命令/写法必须注明当时的 dsh 版本**；跨版本参考时**先实测再照抄**。
>
> **出处**：本人两次实测（2026-09-16，`0.0.1-rc.1` → `0.1.5-rc.2`）

---

## 第 3 步：写观察插件 `tool-logger.ts`

```ts
import type { Context } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-tools'

export const name = 'tool-logger'
export const inject = ['tools']

export function apply(ctx: Context) {
  ctx.on('tools/result', (exec, result) => {
    const text = result.content
      .map(block => (block.type === 'text' ? block.text : ''))
      .join('')
    console.log(`[tool-logger] ${exec.name} -> ${text}`)
  })
}
```

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`（代码逐字一致）

---

## 第 4 步：组合并运行

```yaml
- name: '@deepseek-ai/dsh-system-prompt'
- name: '@deepseek-ai/dsh-tools'
- name: './tool-logger.ts'
- name: './greet-tool.ts'
```

```sh
npm start
```

预期输出：

```
[tool-logger] greet -> Hello, Cordis!
tool replied: [{"type":"text","text":"Hello, Cordis!"}]
```

> **出处**：实测（2026-09-16）——与官方完全一致

### 为什么 logger 先触发？（官方解读）

> **出处**：`docs/cordis-tutorial/07-into-the-harness.zh.md`——*"logger 会先触发：`tools/result` 在结果物化过程中发出，发生在 `execute` 向调用方返回的 promise 兑现之前。两个插件都不知道另一个插件存在，它们由注册表服务和事件连接。"*

**逐行看**：

| 顺序 | 输出来源 | 机制 |
|---|---|---|
| 1 | `[tool-logger] ...` | `tools/result` 在结果**物化时**发出（execute 的 promise **兑现前**） |
| 2 | `tool replied: ...` | `execute` 的 promise 兑现，`greet-tool` 打印结果 |

---

## 第 5 步：回望七讲——你走完了一条完整的路径

| 讲 | 主题 | 核心模式 | 用在 07 讲 |
|---|---|---|---|
| 01 | 第一个插件 | 插件形态 / `apply` | ✅ 两个插件都靠它 |
| 02 | 生命周期与 effect | 注册可逆 | ✅ `tools.register` 卸载即撤销 |
| 03 | 服务与依赖注入 | `inject` / PENDING | ✅ `inject: ['tools']` |
| 04 | 事件 | `emit`/`on`/五种分发 | ✅ `tools/result` 监听 |
| 05 | 配置 | `Config` / schema | （07 未用，但工具 schema 同源） |
| 06 | 组合与 HMR | PENDING 诊断 / `id` | ✅ `tools` 缺 `systemPrompt` 会 PENDING |
| **07** | **进入 Harness** | **组合成真实能力** | **✅ 本章** |

**七讲闭环**：从"写一个 hello 插件"到"注册一个模型可调用的真实工具"。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| `inject: ['tools']` | 等工具注册表就绪 | 依赖注入 | 官方 07 讲 |
| `defineTool` | 参数转 JSON Schema + 类型推导 + 校验 | 带 schema 的 handler 定义 | 官方 07 讲 |
| `ctx.tools.register` | 注册即 effect，卸载即注销 | 可逆注册 | 官方 07 讲 |
| `tools/result` | 观察每次工具调用的结果事件 | 事件总线订阅 | 官方 07 讲 + 实测 |
| 组合需 `system-prompt` | tools 注入它，缺则 PENDING | 依赖缺失即挂起 | 官方 07 讲 |
| 两个插件互不知晓 | 由服务 + 事件连接 | 解耦的订阅者 | 官方 07 讲 |

## 踩坑记录

- **`dsh-*` 依赖要 `--legacy-peer-deps`**：`dsh-tools@0.0.1-rc.1` 的 peer 要 `dsh-agent@^0.0.1-rc.1`，而 npm 上只有 `0.1.0-rc.6`，直接装报 `ERESOLVE`。（出处：实测）
- **peer 依赖需手动逐个补齐**：`--legacy-peer-deps` 不自动装 peer，运行时报 `Cannot find package '@deepseek-ai/dsh-xxx'`——按报错逐个 `npm install --legacy-peer-deps` 补齐（实测缺 `dsh-scope`、`dsh-timeout` 等）。（出处：实测）
- **⚠️ `brandString` / `ToolCallId` 可用性随版本变化**（重要教训）：`dsh-brand@0.0.1-rc.1` 是纯类型包、不导出 `brandString`（当时官方写法不可用，变通用 `dsh-llm` 的 `CallId`）；但 `0.1.5-rc.2` **已导出运行时 `brandString`**，官方写法可用，且 `dsh-llm` 现在导出的是 **`ToolCallId`**（不再叫 `CallId`）。**dsh 跨版本包导出会变，照抄前先实测。**（出处：本人两次实测 2026-09-16，`0.0.1-rc.1` → `0.1.5-rc.2`）
- **缺 `system-prompt` 工具插件静默 PENDING**：`dsh-tools` 注入 `systemPrompt` 服务，组合中不列其提供方，工具插件会像 06 讲那样卡 PENDING。（出处：官方 07 讲）
