---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 动手实验, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 实验02 亲手跑通《生命周期与 effect》——看见"撤销自动发生"

> [!info] 版本锚点
> - 对应官方：`docs/cordis-tutorial/02-lifecycle-and-effects.zh.md`
> - 环境：`~/ai-work/dsh/deepseek-harness/`（已 `pnpm install`）
> - 前置：读完本系列《01》《附》《附2》
> - **本文是动手文档**：你照着**贴代码、跑命令**，我负责讲清楚每个现象为什么发生

## 这个实验要验证什么

一句话：**验证"组件卸载时，它开的资源会自动清理"——即论文说的"时间可组合性"。**

> **出处**：[P.4]（arXiv:2608.25512）时间可组合性 = *"upon removal of a component, the modifications the component made to the shared environment must be completely and safely reversed"*

你会亲眼看到：一个插件开了定时器，**没人手动调 `clearInterval`，卸载时却自动停了**。

---

## 第 1 步：准备目录

在**官方源码仓库**里操作（教程就是这么设计的，`tmp/` 被 git 忽略，不会污染仓库）：

```sh
cd ~/ai-work/dsh/deepseek-harness
mkdir -p tmp/cordis-tutorial
cd tmp/cordis-tutorial
```

> **出处**：教程 index.zh.md 的[准备工作]一节：*"`tmp/` 已被 git 忽略，因此你在其中写入的任何内容都不会进入版本控制"*

---

## 第 2 步：写代码（两个文件）

### 文件一：`lifecycle.ts`

**请把这个文件创建出来**（代码逻辑与官方 02 讲完全一致；**注释**我做成了中英对照，方便阅读——英文注释是官方原版，中文是我加的翻译，不影响运行）：

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'lifecycle-demo'

function heartbeat(ctx: Context) {
  console.log('heartbeat plugin loading')
  ctx.effect(() => {
    const timer = setInterval(() => console.log('tick'), 200)
    return () => {
      clearInterval(timer)
      console.log('heartbeat cleaned up')
    }
  })
}

export function apply(ctx: Context) {
  // Mount a child plugin and keep its fiber to dispose it later.
  // 挂载一个子插件，并保留它的 fiber 句柄，以便稍后手动卸载它。
  const fiber = ctx.plugin(heartbeat)
  // The demo timer is itself an effect: if THIS plugin is unloaded first,
  // the pending callback is cancelled instead of firing on a dead app.
  // 这个演示用的定时器本身也是一个 effect：如果"本插件"先被卸载，
  // 这个待触发的回调就会被取消，而不是在一个已死的应用上继续执行。
  ctx.effect(() => {
    const timer = setTimeout(async () => {
      await fiber.dispose()
      console.log('disposed')
      process.exit(0)
    }, 700)
    return () => clearTimeout(timer)
  })
}
```

> **出处**：`docs/cordis-tutorial/02-lifecycle-and-effects.zh.md`

### 文件二：`cordis.yml`

```yaml
- name: './lifecycle.ts'
```

---

## 第 3 步：跑它

```sh
node --import tsx ../../vendor/cordis/bin.js
```

### 预期输出（官方原文）

```
heartbeat plugin loading
tick
tick
tick
heartbeat cleaned up
disposed
```

> **出处**：`02-lifecycle-and-effects.zh.md` 的"运行后会得到"

---

## 第 4 步：看懂每一行是怎么来的（关键！）

这段代码的执行时序，我帮你推演一遍。**对着你终端的真实输出，逐行找**：

| 时刻 | 发生了什么 | 终端出现 |
|---|---|---|
| t=0 | 启动器加载 `lifecycle.ts`，调用它的 `apply` | |
| t=0 | `apply` 里 `ctx.plugin(heartbeat)` → **挂载子插件** → 触发 `heartbeat` 函数 | `heartbeat plugin loading` |
| t=0 | `heartbeat` 里 `ctx.effect(...)` 起了个 **setInterval(200ms)** 定时器 | |
| t=0 | 回到 `apply`，又 `ctx.effect(...)` 起了个 **setTimeout(700ms)**（用来"稍后自杀"） | |
| t=200 | 第一个定时器触发 | `tick` |
| t=400 | | `tick` |
| t=600 | | `tick` |
| **t=700** | setTimeout 触发 → `await fiber.dispose()` → **卸载 heartbeat 插件** | |
| t=700 | **卸载 → heartbeat 的 effect 逆函数自动执行** → `clearInterval` + 打印 | `heartbeat cleaned up` ← **这就是"撤销自动发生"！** |
| t=700 | 继续执行 timeout 回调剩余部分 | `disposed` |
| t=700 | `process.exit(0)` 退出 | （进程结束） |

### 🎯 划重点：`heartbeat cleaned up` 这行是本次实验的"证据"

**注意：代码里没有任何一处手动调用了 `clearInterval` 之外的 `heartbeat` 卸载。** 是 `fiber.dispose()` 触发了卸载，卸载**自动**执行了 effect 里 return 的那个销毁函数。

> **出处**：[P.59] Algorithm 1：`ctx.effect` 的 disposer 被"**前插**"进累积器（`inverse ← value ∘ inverse`），卸载时按 **LIFO** 执行。

---

## 加厚小节：`await fiber.dispose()` 到底是什么？（图纸 + 注释）

这行代码是实验里**唯一手动触发卸载**的地方，也是最难懂的一行。下面把它彻底拆开。

### 1. 先看它在这段代码里的位置

```ts
const fiber = ctx.plugin(heartbeat)        // ① 挂载子插件，拿到它的句柄
...
ctx.effect(() => {
  const timer = setTimeout(async () => {
    await fiber.dispose()                  // ② 700ms 后，卸载那个子插件
    console.log('disposed')
    process.exit(0)
  }, 700)
  return () => clearTimeout(timer)
})
```

**一句话**：`fiber` 是 `heartbeat` 这个子插件的"**遥控器**"，`fiber.dispose()` = **按遥控器上的"卸载"键**。

### 2. 图纸（一图看懂 dispose 干了什么）

```
   ctx.plugin(heartbeat)
          │
          ▼  产生了 fiber（句柄）
   ┌───────────────────────────────┐
   │  fiber                        │  ← heartbeat 这个子插件实例
   │  ├─ state: ACTIVE             │
   │  └─ _disposables: [           │  ← 它收集的所有"逆函数"
   │       () => clearInterval(...) │     （heartbeat 里 ctx.effect 注册的）
   │     ]                          │
   └───────────────────────────────┘
          │  fiber.dispose()  ← 你调这一下
          ▼
   ① 把 state 改成 UNLOADING
   ② 把所有 _disposables **倒序（LIFO）** 逐个执行
        └─→ 执行 () => clearInterval(timer)
             └─→ 打印 "heartbeat cleaned up"   ← 定时器停了！
   ③ 等全部清理完（可能有异步的），状态 → DISPOSED
```

### 3. 逐行注释（这行代码 + 它触发的链条）

```ts
await fiber.dispose()
//      ↑            ↑
//      │            └─ dispose() 返回一个 Promise（因为清理可能含异步），
//      │               所以用 await 等它"清理完"再往下走。
//      └─ fiber 是 ctx.plugin(heartbeat) 的返回值 —— 子插件的运行时句柄。
//
// dispose() 内部做的事（对应下图链条）：
//   1. 把 fiber 状态置为 UNLOADING（"正在拆"）
//   2. 把它名下所有 effect 的"逆函数"，按【注册的倒序】依次执行  ← LIFO
//   3. 等所有逆执行完（含异步），状态置为 DISPOSED（"拆完了"）
```

### 4. 源码级证据（为什么它"自动"清了定时器）

翻本地 cordis 源码 `vendor/cordis/src/fiber.ts`，`dispose` 的构造是这样的：

```ts
// fiber.ts 约 L265
this.dispose = parent.fiber.effect(() => {     // ← ① dispose 本身是"父 fiber 的一个 effect"！
  const remove = runtime.fibers.push(this)
  return async () => {                          // ← ② 这个 effect 的"逆" = 卸载逻辑
    this.uid = null
    ...
    this.inertia = this._unload()               // ← ③ 真正执行逆的地方
    ...
    while (this.inertia) { await this.inertia }
  }
}, 'ctx.plugin()')
```

而 `_unload()`（同文件）就是"把收集的逆倒序执行"：

```ts
// fiber.ts 约 _unload()
private async _unload() {
  await Promise.all(this._disposables.clear().map(async (dispose) => {
    try { await runDisposable(dispose) }        // ← 执行每一个逆函数
    catch (reason) { this.ctx.logger.error(reason) }
  }))
  ...
}
```

而 `ctx.effect` 内部收集逆、并按 **LIFO** 执行（`fiber.ts` 的 `effect()` 方法）：

```ts
for (const disposable of disposables.splice(0).reverse()) {   // ← .reverse() 就是 LIFO！
  ...
}
```

> **出处**：三条均来自本地源码 `~/ai-work/dsh/deepseek-harness/vendor/cordis/src/fiber.ts`（`dispose` 构造约 L265、`_unload`、`effect()`）。

### 5. 一个"惊人"的设计：dispose 本身就是 effect

看上面第 4 节 ① —— **`fiber.dispose` 不是普通函数，它是"父 fiber 注册的一个 effect"。**

这意味着什么？

```
"挂载子插件" = 父 fiber 的一个 effect
     ↓
这个 effect 的"逆" = 卸载子插件（即子插件的 dispose）
     ↓
所以：父 fiber 卸载时 → 自动执行这个逆 → 子插件被自动 dispose
     ↓
这就是"为什么卸载父插件会级联卸载子插件"的源码级答案！
```

> **出处**：`vendor/cordis/src/fiber.ts` L265（`this.dispose = parent.fiber.effect(...)`）；论文 [P.61] Algorithm 4 注释：*"an instantiation is an ordinary tracked effect of the parent, so unloading a parent cascades to its children."*

### 6. 三个数字/细节的注释

| 代码 | 含义 |
|---|---|
| `await` | 清理可能有**异步**步骤，要**等它完**才继续（论文的"惯性 Unloading 状态跑完才响应下一步"） |
| `dispose()` 无参数 | 卸载的是**整个 fiber**（它名下所有 effect），不是某一个 |
| 返回值是 Promise | [P.62] Algorithm 5：`unload` 会 "reverts all tracked effects in LIFO order" |

---

## 第 5 步：改一改，加深理解（重要！）

**光跑一遍不够，改参数观察差异，才叫真懂。** 试试这几个：

| 改什么                                          | 预期变化                                    | 你在验证什么              |
| -------------------------------------------- | --------------------------------------- | ------------------- |
| 把 `setInterval` 的 `200` 改成 `100`             | `tick` 变多（700ms 内从 3 次变 6 次）            | 定时器真的在跑             |
| 把 `setTimeout` 的 `700` 改成 `1500`             | `tick` 变多（1.5s 内）                       | "自杀"时机可控            |
| **把 `800` 改成 `100`（小于 tick 间隔 200）**         | 可能 **`tick` 都没打就 disposed**             | 卸载时机早于第一次 tick      |
| **注释掉 `await fiber.dispose()`**              | **`heartbeat cleaned up` 不再出现，进程也退不出去** | 验证"是 dispose 触发了清理" |
| **把 `return () => clearInterval(timer)` 删掉** | 定时器**永远停不下来**（进程卡住）                     | 验证"逆函数是清理的关键"       |

> [!tip] 最有价值的一个改动
> **注释掉 `fiber.dispose()` 那一行**。你会发现：
> - `heartbeat cleaned up` 消失了（因为卸载没发生）
> - 进程**退不出去**（定时器还在跑）
> 这直接证明了：**清理不是"自动魔法"，而是 `dispose` → 卸载 → 执行逆函数这条链**。

---

## 第 6 步：把现象连回理论

跑完、改完，你应该能回答这几个问题（**能答上来 = 这个实验过关**）：

1. **`ctx.effect(cb)` 里，`cb` 和 `cb` 返回的函数，分别什么时候执行？**
   → cb 在**加载**时执行；返回的函数（逆）在**卸载**时执行。
2. **为什么没人手动调 `clearInterval`，定时器却停了？**
   → 因为它在 `ctx.effect` 里，卸载时 Cordis **自动**执行了逆函数。
3. **`fiber.dispose()` 做了什么？**
   → 卸载那个插件实例 → 跑它的所有 effect 逆（按 LIFO）。

> 对应论文：这就是 **revertible effect** 的运行时行为。
> **出处**：[P.59] §5.1.1 *"any operation performed through the context is automatically tracked and reverted upon component unloading"*

---

## 踩坑（待你跑完后补充）

> 记录你实际跑的时候遇到的报错、意外现象。**空着，等你跑。**

---

## 出处汇总

| 内容 | 出处 |
|---|---|
| 全部代码 + 预期输出 | `docs/cordis-tutorial/02-lifecycle-and-effects.zh.md` |
| 启动命令 | `docs/cordis-tutorial/index.zh.md` |
| 时间可组合性定义 | [P.4]（arXiv:2608.25512） |
| effect 自动追踪与撤销 | [P.59] §5.1.1 Algorithm 1 |
| LIFO 恢复 | [P.59] Algorithm 1；02 讲"顺序注意事项" |
