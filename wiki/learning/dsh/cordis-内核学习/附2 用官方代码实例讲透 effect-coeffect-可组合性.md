---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 实例讲解, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 附2 用官方代码实例讲透 effect / coeffect / 可组合性

> [!info] 版本锚点
> - 代码来源：官方 cordis-tutorial 第 2、3、4 讲（`~/ai-work/dsh/deepseek-harness/docs/cordis-tutorial/`），**真实可运行**
> - 理论来源：论文 arXiv:2608.25512（`[P.59]` 等指 PDF 页码）
> - 本文目的：**抛开学术术语，用一段段真代码，把论文的概念一个个"翻译"成大白话**
> - 前置：读本系列《附 Cordis 设计论文导读》建立整体印象，再读本文做具象化

## 为什么写这篇

前一篇《论文导读》讲了"论文说了什么"，但术语（effect / coeffect / 时空可组合性）太抽象。**这篇换个方式：拿官方教程里真实能跑的代码，逐行对应论文概念。** 不讲数学，只讲"这行代码在干嘛、论文管它叫什么"。

---

## 第 0 步：先把"效果（effect）"这个怪词翻译成人话

论文管"**组件对共享环境做的修改**"叫 **effect（效果/副作用）**。

> **出处**：[P.4] *"the modifications the component made to the shared environment"*

**大白话**：effect 就是"**一个组件动过环境的手脚**"。比如：
- 开了一个定时器 → 动了环境
- 注册了一个路由 → 动了环境
- 往 ctx 上挂了一个服务 → 动了环境

论文的核心 insight 是：**每次"动手脚"都应该同时记录"怎么把手脚收回来"**。它管这个叫 **revertible effect（可撤销效果）**。

> **出处**：[P.6] *"every context transformation carries an explicit inverse that the runtime holds"*（每次上下文变换都携带一个运行时持有的显式逆）

---

## 第 1 段代码：`ctx.effect` —— "借了东西要还"

看教程第 2 讲的 `heartbeat` 插件（`docs/cordis-tutorial/02-lifecycle-and-effects.zh.md`）：

```ts
function heartbeat(ctx: Context) {
  console.log('heartbeat plugin loading')
  ctx.effect(() => {
    const timer = setInterval(() => console.log('tick'), 200)   // 借了：一个定时器
    return () => {
      clearInterval(timer)                                       // 还：清掉它
      console.log('heartbeat cleaned up')
    }
  })
}
```

**逐行对论文**：

| 代码                                  | 在做什么         | 论文概念                 |
| ----------------------------------- | ------------ | -------------------- |
| `ctx.effect(callback)`              | 声明"我要动环境"    | `effectΓ(𝑒)` [P.58] |
| `const timer = setInterval(...)`    | 动了手脚（开定时器）   | 一次 context 变换        |
| `return () => clearInterval(timer)` | **返回"撤销函数"** | 显式逆（inverse）[P.6]    |
| `heartbeat cleaned up`              | 卸载时逆被自动执行    | `recover` [P.59]     |

> [!tip] 一句话理解
> **`ctx.effect(回调)` 里的回调，"做"是什么，返回的"函数"就是怎么"撤销"。** 就像 Go 里 `defer cleanup()` —— 只不过 Cordis 帮你**在卸载插件时自动**跑这个 cleanup，你不用手写 defer。

**运行结果**（教程原文）：

```
heartbeat plugin loading
tick
tick
tick
heartbeat cleaned up      ← 撤销自动发生了
disposed
```

**注意最后两行**：没人手动调用 `clearInterval`，是 **Cordis 在卸载时自动执行了那个"逆"**。这就是"**时间可组合性**"——组件走了，它留下的痕迹自动擦干净。

> **出处**：教程原文 *"effect 主体在加载期间运行；它返回的 disposer 在卸载期间运行。"*（`02-lifecycle-and-effects.zh.md`）

### 关键细节：逆是**后进先出（LIFO）**执行的

论文 Algorithm 1 里，逆是**前插**到累积器里的（`inverse ← value ∘ inverse`），所以恢复时是 **LIFO**。

> **出处**：[P.59] Algorithm 1 第 6 行；教程亦印证：*"disposer 会按注册顺序的逆序启动"*（02 讲）

**大白话**：跟 Go 的 `defer` 一模一样——最后 `defer` 的最先执行。

---

## 第 2 段代码：`ctx.plugin` 与 `fiber` —— "装了才有实例"

教程第 2 讲里接着：

```ts
export function apply(ctx: Context) {
  const fiber = ctx.plugin(heartbeat)        // 把 heartbeat 挂成一个子插件
  ...
  await fiber.dispose()                       // 之后手动拆除它
}
```

**概念对应**：

| 代码 | 论文概念 | 大白话 |
|---|---|---|
| `ctx.plugin(heartbeat)` | 组件实例化 `⟨d,p,e,...⟩` [P.58] | 装一个插件，产生一个"实例" |
| `fiber` | **fiber**（组件实例，运行时句柄）[P.58] | 这个实例的"遥控器" |
| `fiber.dispose()` | `recover`（累积逆）[P.58] | **拆除这个实例**：把它的逆都跑一遍 |

> [!note] "fiber" 这个词
> 论文 [P.58] Table 2 明确：`⟨d, p, e, ...⟩`（理论里的组件）对应实现里的 **`fiber`**。它是"**一个组件被加载后的运行时实例**"。
> 注意：这里的 fiber **不是 Go 的 goroutine**，是同名不同物——它更像"一个插件的实例句柄"。

**大白话串起来**：`ctx.plugin(heartbeat)` = 装插件（像 `go run` 起一个模块），`fiber` = 拿到它的句柄，`fiber.dispose()` = 关掉它（触发所有逆执行）。

### 为什么卸载父插件会带走子插件？

论文 Algorithm 4 有一句关键：实例化**本身就是父组件的一次被追踪 effect**。

> **出处**：[P.61] Algorithm 4 注释；[P.61] *"an instantiation is an ordinary tracked effect of the parent, so unloading a parent cascades to its children."*

**大白话**：`ctx.plugin(子)` 是父组件"借的一个东西"，所以父组件卸载 → 自动还 → 子组件跟着被拆。**层层嵌套，自动级联。**

---

## 第 3 段代码：`inject` —— "依赖没就绪，我就不启动"

教程第 3 讲的 `consumer`（`03-services.zh.md`）：

```ts
export const name = 'consumer'
export const inject = ['greeter']          // ← 声明：我依赖 greeter 服务

export function apply(ctx: Context) {
  console.log(ctx.greeter.greet('world'))  // 到这里时，greeter 一定已就绪
}
```

**这是什么？** 论文管"**组件对环境的要求**"叫 **coeffect（上下文依赖）**：

> **出处**：[P.7-8] *"a coeffect system enriches the context rather than the type ... describing what the computation requires from its environment"*（coeffect 描述计算**从环境要求什么**）

**大白话对照**：
- **effect** = 我对环境**做了什么**（借了定时器）
- **coeffect** = 我**要求**环境有什么（我需要 greeter 服务）

`inject = ['greeter']` 就是一份 **coeffect 规格（spec）**。

> **出处**：论文叫它 `d`（依赖规范），对应实现 `fiber.inject`。[P.58] Table 2

### 最关键的点：依赖是"响应式"的，不是一次性检查

教程原文强调：

> *"`inject` 并非一次性的启动检查。如果应用运行期间所需服务消失……每个依赖插件也会随之卸载，并在服务恢复后再次加载。"*
>
> **出处**：`03-services.zh.md` "加载后仍会跟踪依赖关系"一节

这就是论文的 **reactive coeffect（响应式 coeffect）**：每次上下文变化都被**分类**为"激活 / 停用 / 中性"，据此驱动组件开关。

> **出处**：[P.6] *"every context change is classified against that specification as activating, deactivating, or neutral, driving the component's activation and deactivation"*

**大白话**：
```
greeter 服务上线   → 依赖满足了 → consumer 被"激活"（启动）
greeter 服务下线   → 依赖没了   → consumer 被"停用"（自动卸载）
greeter 换个实现   → 重新激活   → consumer 用新实现重启
```

**这就是"空间可组合性"**：组件对依赖的声明和管理是**活的、响应式的**，不是启动时写死的。

### 一个反直觉的验证

教程让你**交换 `cordis.yml` 里两行的顺序**，输出不变：

```yaml
- name: './consumer.ts'   # 就算 consumer 写在前面
- name: './greeter.ts'    # greeter 写在后面
```

**为什么？** 因为启动顺序**不由文件顺序决定，而由依赖决定**——`consumer` 会保持 `PENDING`，直到 `greeter` 就绪。

> **出处**：教程原文 *"决定插件何时启动的是依赖关系，而不是文件顺序"*（03 讲）；Fiber 状态机 `PENDING` 定义见 02 讲

**这就是"空间可组合性"的价值**：你**不用手动编排启动顺序**，声明依赖即可。

---

## 第 4 段代码：`ctx.on` —— "监听器也是借的"

教程第 2 讲说，很多 API **本身就是 effect**，不用你手写 `ctx.effect`：

```ts
ctx.on(event, listener)      // 监听器会在卸载时自动移除
ctx.plugin(child)            // 子插件随父插件 dispose
ctx.tools.register(...)      // 工具注册也自动撤销
```

> **出处**：`02-lifecycle-and-effects.zh.md` "已经属于 effect 的操作"一节

**大白话**：`ctx.on(...)` 注册的监听器，**卸载插件时 Cordis 自动帮你摘掉**——你不用手写撤销。这又是"时间可组合性"的体现：**凡是注册，皆可撤销**。

---

## 把两个维度用一句话钉死

| 维度 | 大白话 | 代码里对应 |
|---|---|---|
| **时间可组合性** | **我走了，痕迹擦干净** | `ctx.effect(...)` 的逆、`ctx.on` 自动移除 |
| **空间可组合性** | **依赖谁，声明即可，自动响应** | `export const inject = [...]` |

这两个词，就是论文标题里的 "**spatiotemporal（时空）**"：
- **temporal（时间）** = 时间维：走了要能回滚
- **spatial（空间）**：组件之间的依赖关系

> **出处**：[P.4] §1.1 两维度的定义

---

## 用 Go 类比收尾（帮你锚定）

| Cordis | Go 里的相近物 | 关键差异 |
|---|---|---|
| `ctx.effect(cb)` | `defer cb's cleanup` | defer 作用域是**函数**；effect 作用域是**插件生命周期**（更长、动态） |
| 逆按 LIFO | defer 的 LIFO | 一样 |
| `inject = ['x']` | DI 容器声明的依赖 | 更**响应式**：依赖消失会自动卸载 |
| `fiber.dispose()` | 关闭一个服务/module | 会**递归级联**到子组件 |
| `ctx.on(...)` 自动撤销 | 手动摘 listener | Cordis **自动**帮你摘 |

> [!important] 一句话记住
> **Cordis 把 Go 里需要你手动 `defer` / 手动摘 listener / 手动编排依赖顺序的事，变成了"声明 + 自动撤销 + 响应式"。** 这就是它比普通 DI 框架强的地方。

---

## 出处汇总

| 内容 | 出处 |
|---|---|
| `heartbeat` / `ctx.effect` 代码 | `docs/cordis-tutorial/02-lifecycle-and-effects.zh.md` |
| `GreeterService` / `inject` / 响应式依赖 | `docs/cordis-tutorial/03-services.zh.md` |
| `ctx.on` 自动撤销 | `docs/cordis-tutorial/02-lifecycle-and-effects.zh.md` |
| 两维度定义 | [P.4]（arXiv:2608.25512） |
| revertible effect / inverse | [P.6]、[P.59] Algorithm 1 |
| fiber / inject / dispose 对应 | [P.58] Table 2 |
| 实例化=父的被追踪 effect（级联卸载） | [P.61] Algorithm 4 |
| reactive coeffect（激活/停用/中性） | [P.6] |

> 教程本地根：`~/ai-work/dsh/deepseek-harness/docs/cordis-tutorial/`
