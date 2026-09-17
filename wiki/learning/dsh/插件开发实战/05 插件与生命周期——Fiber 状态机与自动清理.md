---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, framework, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 05 插件与生命周期——Fiber 状态机与自动清理

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/framework/index.zh.md`（插件与生命周期）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 前置：完成阶段二 basic（01–04 篇）；回顾阶段一**实验02/03/06**
> - **本篇起进入 `develop/framework` 教程**（阶段二主路径续篇）
> - 写法说明：本系列采用**完整重讲式**——每个概念都讲全，并标注**哪些在阶段一学过、哪些是真实 dsh 的新知**

## 这一篇在讲什么

stage 一（七讲 + 实验）你已经在**最小工程**里理解了 Cordis 的生命周期；framework 教程从**真实 dsh 视角**把同一套机制**系统重述**一遍，并补上完整细节。

官方定位：

> **出处**：`docs/user/develop/framework/index.zh.md`——*"本页介绍 Cordis 插件模型和生命周期状态机。"*

**本篇的核心**：理解 **Fiber（插件的运行时实例）** 及其 **6 态状态机**，以及"注册自动清理"的精确规则。

---

## 先讲理论（完整版）

### 概念① 什么是 Fiber —— 插件的"运行时实例"

> **出处**：官方 index.zh.md——*"每个被加载的插件都拥有一个 **Fiber** 作用域。"*

**这是本篇的地基概念**。你实验02 用过 `ctx.plugin()` 的返回值（那个 `fiber`），但当时没系统理解它是什么。

**用 Go 类比**：插件代码（`export function apply`）是**类定义**；Fiber 是这个类在运行时**被实例化出的对象**。

关键区别：
- **一个插件**（一份代码）可以被**挂载多次** → 每次产生**独立的一个 Fiber**
- 每个 Fiber 有**自己的**：状态（state）、配置（config）、effect 集合、子插件

> **出处**：官方 `vendor/cordis/src/fiber.ts:194`——`public state = FiberState.PENDING`（每个 Fiber 有自己的状态字段）

> [!tip] 关联：实验02 的 `fiber.dispose()`
> 实验02 里 `ctx.plugin(heartbeat)` 返回的那个 `fiber`，就是一个 Fiber 实例；`await fiber.dispose()` 就是**手动终结这个实例**。本篇概念⑥会给出它的三条保证。

### 概念② Fiber 状态机（完整 6 态）

> **出处**：官方 index.zh.md——状态机图：

```
PENDING → LOADING → ACTIVE
                 ↘ FAILED
ACTIVE → UNLOADING → DISPOSED
```

| 状态            | 含义                | 阶段一在哪儿见过        |
| ------------- | ----------------- | --------------- |
| **PENDING**   | 已声明，但所需依赖未就绪      | 实验06（`state=0`） |
| **LOADING**   | 依赖就绪，正在执行 `apply` | 新知              |
| **ACTIVE**    | 插件运行中             | 实验06            |
| **FAILED**    | `apply` 抛出异常      | 实验06 提过         |
| **UNLOADING** | 插件正在卸载并释放资源       | 新知              |
| **DISPOSED**  | 已完全卸载             | 实验02            |

> **出处**：官方 index.zh.md 的状态含义表（逐字）

**三条路径**：
1. **正常加载**：`PENDING → LOADING → ACTIVE`（依赖就绪才进 LOADING）
2. **失败路径**：`LOADING ↘ FAILED`（`apply` 抛异常）
3. **卸载路径**：`ACTIVE → UNLOADING → DISPOSED`

**回看实验06**：`needs-timer` 声明 `inject=['timer']` 但无人提供 → 卡在 **PENDING** → **永远进不了 LOADING** → `apply` 不执行。这就是状态机的直接体现。

> **出处**：生命周期状态机的源码实现在 `vendor/cordis/src/fiber.ts`（`_getState` / `_setEpoch` / `_updateState`，实验06 场景③c 已深挖）

### 概念③ 依赖驱动的加载（阶段一学过，完整讲）

> **出处**：官方 index.zh.md——*"声明了 `inject` 的插件会等待所有必需服务就绪……如果依赖的服务消失（例如提供方被替换时），插件会被自动卸载（ACTIVE → DISPOSED），待服务恢复后重新加载。"*

**双向流转**（关键）：
- 依赖**就绪** → `PENDING →（LOADING）→ ACTIVE`
- 依赖**消失** → `ACTIVE → DISPOSED`
- 依赖**恢复** → 重新 `PENDING → ACTIVE`

```ts
export const inject = ['tools', 'llm']
export function apply(ctx: Context) {
  // ctx.tools 和 ctx.llm 在此就绪
}
```

> **出处**：官方 index.zh.md（代码逐字）

**关联**：这正是实验03（服务依赖持续跟踪）+ 实验06（PENDING 诊断）的**状态机视角**。

### 概念④ 自动清理机制（阶段一学过，完整讲）

> **出处**：官方 index.zh.md——*"通过 `ctx` 做的任何注册，在插件卸载时都会自动撤销。"*

**会被自动追踪清理的操作**（官方清单）：

| 操作 | 说明 |
|---|---|
| `ctx.on(event, handler)` | 事件监听 |
| `ctx.tools.register(tool)` | 工具注册 |
| `ctx.llm.registerAdapter(names, adapter)` | LLM 适配器注册 |
| `ctx.effect(() => cleanup)` | 自定义资源 |

> **出处**：官方 index.zh.md（清单逐字）

```ts
export function apply(ctx: Context) {
  // 事件监听：卸载时自动移除
  ctx.on('some-event', handler)

  // 自定义资源：返回的 disposer 在卸载时运行
  ctx.effect(() => {
    const connection = createConnection()
    return () => connection.close()
  })
}
```

> **出处**：官方 index.zh.md（代码逐字）

> [!warning] ⚠️ 卸载顺序的坑（新知，重要）
> > **出处**：官方 index.zh.md——*"插件卸载时，处置器按**注册顺序的逆序**开始调用，但**多个异步处置器会并发执行，不保证逐个完成**。存在顺序依赖的清理步骤必须放进**同一个 `ctx.effect()`** 返回的处置器中，由该处置器负责串行等待。"*
>
> **解读**：
> - 逆序（LIFO）——后注册的先清理（像 Go 的多个 `defer` 逆序执行）
> - **但**异步 disposer **并发**执行 → 有先后依赖的两步清理**不能**靠逆序保证
> - **解法**：把有依赖的清理**塞进同一个 `ctx.effect`**，在那个 disposer 内部自己 `await` 串行

**Go 类比**：像多个 `defer` 逆序执行——但 Go 的 defer 是**串行**的；Cordis 这里**异步 disposer 会并发**，所以顺序敏感的资源要合并到一个 `effect` 里。

> [!question] 那么，**什么情况下会触发清理**？（你可能有的疑问）
> 你启动 dsh 时**并没说要移除任何插件**，但日志里却出现了"清理"——为什么？因为**清理 ≠ 你主动移除插件**。触发清理的完整场景：
>
> | # | 触发场景 | 源码 |
> |---|---|---|
> | 1 | **父插件卸载 → 子插件级联卸载** | `dispose()` 递归 |
> | 2 | **依赖的服务消失**（provider 被卸载/替换） | `fiber.ts` 的 `_refresh` → `_unload` |
> | 3 | **⭐ 加载失败 → 回滚已加载的插件** | **`fiber.ts:306`** |
> | 4 | 手动 `fiber.dispose()` | 你显式调用 |
> | 5 | 进程退出（`Ctrl-C` / 崩溃） | 运行时整体拆除 |
>
> **场景 3 是关键**（容易误解）：dsh 的插件树是**原子**的——一次启动里**任一插件加载失败**（如 `webserver` 端口被占 `EADDRINUSE`），**整棵树都会回滚**，连带清理那些**已加载成功、本身没问题**的插件。
>
> > **出处**：`vendor/cordis/src/fiber.ts:303-307`——发布失败时 `void Promise.resolve(this.dispose()).catch(...)`（抛错即回滚清理）
>
> **Go 类比**：像**事务回滚 / 构造失败时的 `defer` 清理**——初始化流程任一步失败，已建立资源全部释放，不留半加载状态。
>
> **本文动手案例的实测**就撞上了场景 3：`lifecycle-demo` 加载成功后，同一次启动的 `webserver` 因端口占用失败 → 整树回滚 → 触发了 `effect-1/A/B` 的清理（详见下文动手案例的说明）。

### 概念⑤ 嵌套上下文（实验01 的 `ctx.plugin` 深化）

> **出处**：官方 index.zh.md——*"`ctx.plugin()` 创建子 Fiber，它继承父上下文但有独立的生命周期……子插件随父插件卸载。"*

```ts
export function apply(ctx: Context) {
  // 注册一个子插件
  ctx.plugin(childPlugin)
  // 子插件有自己的 Fiber，并随父插件一起卸载
}
```

> **出处**：官方 index.zh.md（代码逐字）

**Go 类比**：像**父子 goroutine / 嵌套组件**——父的 context 传给子，但子有独立生命周期，父终结时子一起终结（级联）。

**关联**：实验01 你见过 `ctx.plugin()`；这里是它的"子 Fiber + 继承 + 级联卸载"完整语义。

### 概念⑤·补 什么决定"父子"关系？（源码级）

一个必问的问题：**说 `lifecycle-child` 是 `lifecycle-demo` 的子插件，凭据是什么？** 是名字吗？——**不是**。父子关系由 **Fiber** 决定，与 `name` 无关。

#### 第 1 步：每个 Fiber 的 ctx 从「父 ctx」派生

> **出处**：`vendor/cordis/src/fiber.ts:236`——
> ```ts
> this.ctx = this.context = parent.extend({ fiber: this })
> ```
> 每个 Fiber 的 `ctx` 是从 **`parent`**（父）`extend()` 出来的——这就是官方说的"**继承父上下文**"的实现。

#### 第 2 步：`ctx.plugin()` 用「调用者的 ctx」当新 Fiber 的 parent

> **出处**：`vendor/cordis/src/registry.ts:330`——
> ```ts
> const fiber = new Fiber(this.ctx, config, ...)
> ```
> 这里 `this.ctx` = **调用 `ctx.plugin()` 时用的那个 ctx**。

#### 串起来：你的代码为什么构成父子

```ts
export function apply(ctx: Context) {     // ← 这个 ctx = lifecycle-demo 的 Fiber 的 ctx
  const child = ctx.plugin({ name: 'lifecycle-child', apply: ... })
  //             ↑ 用「lifecycle-demo 的 ctx」调 ctx.plugin
  //               → 新 Fiber 的 parent = lifecycle-demo 的 ctx
  //               → lifecycle-child 成为 lifecycle-demo 的子 Fiber
}
```

**"父子"成立的唯一依据**：`ctx.plugin()` 被**谁的 ctx** 调用。

| 事实                                      | 依据                                                               |
| --------------------------------------- | ---------------------------------------------------------------- |
| `lifecycle-child` 的父 = `lifecycle-demo` | `ctx.plugin()` 用的是 **`lifecycle-demo` 的 ctx**（`registry.ts:330`） |
| `lifecycle-demo` 的父 = 根 ctx             | 它是 `start.sh` 从**根 ctx** 挂载的                                     |

#### 关键洞察：名字与父子无关

把子插件的 `name` 改成 `'xyz'`，它**依然是** `lifecycle-demo` 的子插件——**父子由"哪个 ctx 调了 `ctx.plugin()`"决定，与 `name` 无关**。这再次印证**实验03 的"两个 name"**：`name` 只是给框架读的可读标签，**身份与层级靠对象引用（ctx / fiber），不靠名字**。

#### 为什么"父卸载 → 子级联卸载"

因为父 Fiber 持有子 Fiber 的引用（子登记在父的 `ctx` 空间）。父 `dispose()` 时按此引用**递归卸载子 Fiber**——这就是概念⑥ dispose 第 2 条保证（"子插件也被递归卸载"）的机制来源。

> **出处**：机制综合 `vendor/cordis/src/fiber.ts:236`（ctx 从 parent 派生）+ `registry.ts:330`（parent = 调用者 ctx）+ 实验05 实测（子插件 effect 在父上下文中被清理）

### 概念⑥ `dispose()` 语义（实验02 用过，完整讲）

> **出处**：官方 index.zh.md——*"当你需要提前终止一个插件实例："*

```ts
const fiber = ctx.plugin(myPlugin)
await fiber.dispose()   // 稍后手动销毁
```

**`dispose` 的三条保证**（官方逐条）：

> **出处**：官方 index.zh.md——
> 1. 该插件拥有的**所有注册均被移除**
> 2. 它的**子插件也被递归卸载**
> 3. 返回的 Promise 会**在所有异步清理完成后**兑现

**关联**：实验02 的 `await fiber.dispose()` —— 这里补全了它的**契约**。特别是第 3 条：`await dispose()` 保证**异步清理也完成**了才返回。

### 概念⑦ HMR（实验06 学过）

> **出处**：官方 index.zh.md——*"通过 `cordis.yml` 加载 `@deepseek-ai/cordis-plugin-hmr` 后，修改插件源文件会触发：1. 卸载旧插件（清理所有注册）；2. 重新加载新代码；3. 执行新的 `apply`。"*

**为什么 HMR 能干净工作**：

> **出处**：官方——*"因为插件注册会被自动清理，所以热替换**不会保留旧实例的注册**。"*

**串起来**：HMR = ②状态机的卸载路径 + ④自动清理 + ③依赖加载的**组合**。这正是实验06 的核心洞察。

### 概念⑧ 生命周期示例（官方给的完整例子）

```ts
export function apply(ctx: Context) {
  console.log('plugin loading')

  ctx.effect(() => {
    console.log('effect registered')
    return () => console.log('effect cleaned up')
  })
}
```

**加载时输出**：
```
plugin loading
effect registered
```

**卸载时输出**：
```
effect cleaned up
```

> **出处**：官方 index.zh.md（代码 + 输出逐字）

**解读**：`apply` 执行时先打印 `plugin loading`，然后注册 effect；卸载时 effect 的清理函数执行，打印 `effect cleaned up`。

---

## 动手案例：把生命周期"跑出来"看

> **规则（AGENTS.md）**：动手环节"你动手"。本文代码已写出并**已实测**。

**目标**：把 05 篇的抽象概念（6 态状态机、自动清理、dispose）变成**终端里看得见的输出**。

案例插件在 `dsh-learn/plugins/lifecycle-demo/`，做三件事：
1. **① 打印完整生命周期**：`apply` 执行（LOADING→ACTIVE）+ effect 注册/清理
2. **② 验证"逆序开始 + 异步并发"**：两个异步清理 effect（A 耗时 300ms、B 耗时 100ms）
3. **③ 观察 Fiber 状态 + dispose 演示**：挂子插件、读 `fiber.state`、手动 `dispose`

### `lifecycle-demo.ts`（核心部分）

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'lifecycle-demo'

export function apply(ctx: Context) {
  console.log('[lifecycle] apply 执行（LOADING → ACTIVE）')

  ctx.effect(() => {
    console.log('[lifecycle] effect-1 注册')
    return () => console.log('[lifecycle] effect-1 清理')
  })

  // 两个带异步清理的 effect：观察「逆序开始 + 异步并发」
  ctx.effect(() => {
    console.log('[lifecycle] effect-A 注册（清理耗时 300ms）')
    return async () => {
      console.log('[lifecycle] effect-A 清理开始')
      await new Promise(r => setTimeout(r, 300))
      console.log('[lifecycle] effect-A 清理完成')
    }
  })

  ctx.effect(() => {
    console.log('[lifecycle] effect-B 注册（清理耗时 100ms）')
    return async () => {
      console.log('[lifecycle] effect-B 清理开始')
      await new Promise(r => setTimeout(r, 100))
      console.log('[lifecycle] effect-B 清理完成')
    }
  })

  // 子插件 + 状态观察 + 手动 dispose
  const child = ctx.plugin({
    name: 'lifecycle-child',
    apply(childCtx: Context) {
      console.log('[lifecycle] 子插件 apply 执行')
      childCtx.effect(() => {
        console.log('[lifecycle] 子插件 effect 注册')
        return () => console.log('[lifecycle] 子插件 effect 清理')
      })
    },
  })

  ctx.effect(() => {
    const timer = setTimeout(async () => {
      console.log(`[lifecycle] 观察子插件 fiber.state = ${(child as any).state}`)
      console.log('[lifecycle] 手动 dispose 子插件…')
      await child.dispose()
      console.log('[lifecycle] 子插件 dispose 完成（含其异步清理）')
    }, 1200)
    return () => clearTimeout(timer)
  })
}
```

### 跑法

```sh
cd ~/ai-work/dsh/dsh-learn
./start.sh --patch /Users/melodycchen/ai-work/dsh/dsh-learn/plugins/lifecycle-demo/cordis.patch.yml
```

### ✅ 实测输出（2026-09-16）

```
[lifecycle] apply 执行（LOADING → ACTIVE）
[lifecycle] effect-1 注册
[lifecycle] effect-A 注册（清理耗时 300ms）
[lifecycle] effect-B 注册（清理耗时 100ms）
[lifecycle] 子插件 apply 执行
[lifecycle] 子插件 effect 注册
[lifecycle] 观察子插件 fiber.state = 2
[lifecycle] 手动 dispose 子插件…
[lifecycle] 子插件 effect 清理
[lifecycle] 子插件 dispose 完成（含其异步清理）
[lifecycle] effect-B 清理开始
[lifecycle] effect-A 清理开始
[lifecycle] effect-1 清理
[lifecycle] effect-B 清理完成
[lifecycle] effect-A 清理完成
```

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）
>
> ⚠️ **实测背景说明**：这次实测**恰好撞上了"启动失败回滚"**——同一次启动里 `webserver` 插件因端口 3080 被占（`EADDRINUSE`）失败，导致**整棵插件树回滚**。所以日志里 `effect-1/A/B` 的清理**不是本插件主动移除的**，而是**回滚触发**的（详见概念④的"清理触发场景"表）。**子插件**的清理则是代码里 `await child.dispose()` **主动触发的**。两类清理要分清。

### 逐点解读（每个现象对应一个概念）

| 现象 | 证实的概念 |
|---|---|
| `apply 执行（LOADING → ACTIVE）` | 概念② 状态机的加载路径 |
| `fiber.state = 2`（= ACTIVE） | 概念② 6 态（数字 2 = ACTIVE） |
| B 先 A 后 `清理开始` | 概念④ **处置器逆序开始** |
| **A 先开始却后完成**（300ms > 100ms） | 概念④ ⚠️ **异步 disposer 并发、不保证逐个完成** |
| 子插件 effect 清理 → dispose 完成 | 概念⑥ dispose **递归卸载子 + await 异步完成** |

**最关键的是这两行**：
```
[lifecycle] effect-A 清理开始     ← A 注册更早，却"开始"更晚（逆序）
...
[lifecycle] effect-A 清理完成     ← A 耗时 300ms，反而"完成"最晚
```
A 注册**早**、清理**开始晚**（逆序生效），但因耗时更长，**完成反而最晚**——这就是"逆序开始 ≠ 顺序完成"。**如果有顺序依赖，必须合并到一个 `ctx.effect`。**

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| Fiber | 插件的**运行时实例**（一插件可多次挂载） | 类的实例化对象 | 官方 index.zh.md |
| 6 态状态机 | PENDING→LOADING→ACTIVE（↘FAILED）；ACTIVE→UNLOADING→DISPOSED | goroutine 生命周期 | 官方 index.zh.md |
| 依赖驱动加载 | 依赖就绪→加载；消失→卸载；恢复→重载 | 依赖注入 + 级联 | 官方 index.zh.md + 实验03/06 |
| 自动清理 | `ctx.on`/`tools.register`/`llm.registerAdapter`/`ctx.effect` | `defer` | 官方 index.zh.md + 实验02 |
| ⚠️ 清理逆序但异步并发 | 有依赖的清理须合并到一个 `effect` | 多个 `defer`（但 Go 串行） | 官方 index.zh.md |
| 嵌套上下文 | `ctx.plugin` 子 Fiber，独立生命周期、级联卸载 | 父子 goroutine | 官方 index.zh.md + 实验01 |
| `dispose()` 三保证 | 移除注册 + 递归卸载子 + await 异步清理完成 | 显式销毁 | 官方 index.zh.md + 实验02 |
| HMR | 卸载旧 + 加载新，不保留旧注册 | 热替换 | 官方 index.zh.md + 实验06 |

## 踩坑记录

- **⚠️ 异步清理会并发、不保证顺序**：卸载时 disposer 逆序**开始**调用，但多个**异步** disposer 并发执行——有顺序依赖的清理必须放进**同一个 `ctx.effect()`** 内部串行等待。（出处：官方 index.zh.md）
- **`apply` 抛异常 → FAILED 态**：插件不会"半运行"，而是进入 FAILED（对应实验06 的失败路径）。（出处：官方 index.zh.md 状态表）
- **`await dispose()` 才等得到异步清理完成**：不 await，异步清理可能还在跑。（出处：官方 index.zh.md dispose 第 3 条）

## 下一步

- **06 服务与依赖**：让插件**对外提供服务**（`Service` 基类）+ 服务隔离
- **07 事件系统**：插件间松耦合通信 + **Cordis 事件 vs 持久化会话事件**
