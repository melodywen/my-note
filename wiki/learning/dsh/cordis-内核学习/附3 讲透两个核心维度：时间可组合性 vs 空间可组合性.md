---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 核心概念, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 附3 讲透两个核心维度：时间可组合性 vs 空间可组合性

> [!info] 版本锚点
> - 论文：arXiv:2608.25512，`[P.x]` 指 PDF 页码
> - 这是理解 Cordis 的**总纲**：后面所有概念（effect / inject / 可撤销 / 响应式）都服务于这两个维度
> - 本文分两部分：**上半篇"讲清楚"**（大白话 + 例子）、**下半篇"扩展"**（学术谱系、为什么这么分、边界在哪）

---

# 上半篇：先把这两个词讲清楚

## 0. 先破题：这俩词到底在说什么？

论文说，**动态组合**（组件能在运行时装卸）有**两个"难处"**，它们彼此正交（互不依赖）：

> **出处**：[P.4] §1.1 *"we identify two orthogonal dimensions beyond the well-studied algebraic aspects of composition"*

| 维度 | 论文原话 | 一句话人话 |
|---|---|---|
| **时间可组合性** | 组件移除时，它对环境做的修改必须被**完整、安全地撤销** | **"我走了，痕迹擦干净"** |
| **空间可组合性** | 组件能**结构化地声明、发现、解析**彼此的依赖 | **"我依赖谁，说清楚，自动接上"** |

**为什么叫"时间/空间"？**
- **temporal（时间）**：管的是"**时间轴上的来去**"——组件在时间中加载又卸载，卸载时要**回溯**到加载前。
- **spatial（空间）**：管的是"**组件之间的空间关系**"——谁依赖谁，是一张"依赖拓扑图"。

> 出处同上 [P.4]。

---

## 1. 时间可组合性（Temporal Composability）

### 1.1 定义 + 人话

> **论文定义（[P.4] §1.1）**：
> *"upon removal of a component, the modifications the component made to the shared environment must be completely and safely reversed. This requires tracking every resource allocation, event registration, and state mutation the component performs, and guaranteeing their orderly reclamation upon removal."*
>
> **翻译**：组件被移除时，它**对共享环境做的修改**必须被**完整、安全地撤销**。这要求：追踪它做的**每一次资源分配、事件注册、状态变更**，并保证移除时**有序回收**。

**人话拆解**——一个组件"动过环境的手脚"通常有这几类：

| 组件干了什么 | 卸载时必须做什么 |
|---|---|
| 开了一个定时器 / 起了个 goroutine | 停掉它（不然泄漏） |
| 注册了一个事件监听 / HTTP 路由 | 摘掉它（不然残留） |
| 申请了一个连接 / 文件句柄 | 归还它 |
| 改了某个全局状态 | 改回去 |

**如果做不到"完整撤销"会怎样？** —— 这正是论文拿 **VSCode** 举的反例：

> **出处**：[P.4] §1.2.1
> VSCode 所有扩展跑在同一个 *extension host* 进程里。**一旦某个扩展的 `activate` 跑过，就没办法在运行时卸载它的代码**——禁用/卸载必须**重启整个 host**，牵连所有已加载扩展。
> 更糟的是：它的 `deactivate` 钩子把"副作用销毁"和"副作用创建（在 `activate` 里）"**分开写**，违反 locality of concern（关注点局部性），使清理**难以验证是否完整**。

> **原文（[P.4]）**：*"Once an extension's activate function has executed, disabling or uninstalling it requires restarting the entire host"*；*"the hook separates effect disposal from effect creation (in activate), violating locality of concern and making complete cleanup difficult to verify."*

**这就是"时间不可组合"的代价**：想移除一个组件，只能"掀桌子"（重启进程）。

### 1.2 一句话抓住

> **时间可组合性 = 让"组件卸载"能像"函数返回"一样干净**——函数返回时局部变量自动销毁（栈帧弹出），那么组件卸载时它开的一切也应该自动销毁。

---

## 2. 空间可组合性（Spatial Composability）

### 2.1 定义 + 人话

> **论文定义（[P.4] §1.1）**：
> *"components must be able to declare, discover, and resolve their dependencies on one another in a structured and verifiable manner. This requires managing dependency topology and coordinating component lifecycles in response to dependency changes."*
>
> **翻译**：组件必须能**以结构化、可验证的方式声明、发现、解析**彼此的依赖。这要求**管理依赖拓扑**，并**响应依赖变化**来协调组件生命周期。

**人话拆解**——三个动作：

| 动作                        | 含义                                |
| ------------------------- | --------------------------------- |
| **declare（声明）**           | "我需要一个缓存服务"——明确说出来                |
| **resolve（解析）**           | 框架自动去找到那个服务，接上                    |
| **react to change（响应变化）** | 依赖**没了** → 我自动停；依赖**换了** → 我自动用新的 |

**VSCode 在空间维的缺陷**（论文 [P.5] §1.2.1）：
> VSCode 有 `extensionDependencies` 能声明扩展间依赖，但**几乎没人用**（top 100 扩展里只有 7 个声明）。原因是它只提供**固定的扩展点**（commands/views/...），扩展是"挂到宿主上"，而不是"彼此依赖"。
> 更要命：扩展间通信走 `getExtension().exports`，返回**无类型**（默认 `any`），依赖方**无法依赖一个受检的接口**。

> **原文（[P.5]）**：*"the returned value is untyped (any by default), so the dependent cannot rely on a checked interface."*

**这就是"空间不可组合"**：组件之间无法**安全地、有类型地**声明依赖。

### 2.2 一句话抓住

> **空间可组合性 = 把"组件依赖"变成声明式的、活的**——像 Go 的接口：你声明你依赖"一个能 `Get(key)` 的东西"，框架负责找到并接上；而不是硬编码 `import 具体实现`。

---

## 3. 为什么偏偏是"这两个"？（正交性的意义）

论文强调这两个维度是**正交的（orthogonal）**——它们**各自独立、互不替代**：

> **出处**：[P.4] §1.1；[P.6] §1.3 *"These two directions are what effect systems and coeffect systems formalize"*

- **时间维**回答："计算**怎么修改**环境"——对应 **effect（副作用）**
- **空间维**回答："计算**怎么依赖**环境"——对应 **coeffect（上下文依赖）**

**"修改"和"依赖"是两件不同的事**——你可以：
- 一个组件"只读环境"（有依赖、无副作用）→ 只有空间维问题
- 一个组件"只改环境"（有副作用、无依赖）→ 只有时间维问题
- 大多数组件两者都有 → 两个维都要解决

**这就是为什么论文要分两维**：一个框架若只解决其中之一，就不完整。**Cordis 两个都解决。**

---

## 4. 静态 vs 动态：为什么以前不难，现在变难

> **论文（[P.4] §1.1）**：这两个维度在**静态**场景下其实是"老问题、已有解"，但**动态**场景下变难：

| 维度 | **静态**场景（旧） | **动态**场景（dsh 要解决的） |
|---|---|---|
| **时间** | 退化为**词法作用域**（RAII、bracket 模式）——资源生命周期和代码块绑定 | 要处理**作用域不受词法约束的、长生命周期的、有状态的**副作用 |
| **空间** | 退化为**模块导入解析**——启动时一次性确定 | 要处理**运行期出现/消失/改变身份**的依赖 |

> **原文（[P.4]）**：*"In the static setting, temporal composability reduces to lexical scoping (e.g., RAII, bracket patterns), and spatial composability reduces to module import resolution."*
> *"In the dynamic setting ... temporal composability must handle long-lived, stateful effects whose scope is not lexically bounded; and spatial composability must handle dependencies that appear, disappear, or change identity during execution."*

**大白话**：
- **静态**：Go 里 `defer f.Close()` 就够了——因为"资源"和"函数"生命周期一致。**但插件不一样**：插件存活几分钟到几小时，它开的资源不能被某个函数"包住"。
- **静态**：Go 里 `import` 在编译期就定了。**但插件不一样**：B 插件可能比 A 插件后加载，甚至 A 运行时 B 才出现。

---

# 下半篇：扩展——放进学术谱系看

> 这部分来自论文 §7.2 / §7.3 / §7.4（Related Work），帮你建立"**Cordis 相对已有方案，到底新在哪**"的认识。

## 5. 时间可组合性：已有方案分四派（§7.3）

> **出处**：[P.79-P.81] §7.3。论文把"替换组件时如何恢复它装的 effect"分成四类：

| 派别 | 做法 | 局限 | 代表 |
|---|---|---|---|
| **① 状态前向迁移** | 把旧组件的**状态带到新版本**（滚动升级） | 只在"无交互点"才能换（quiescence/tranquility） | Kramer-Magee、Vandewoude |
| **② 开发者手写 cleanup** | 组件自己写清理代码 | 靠自觉，**忘了就静默泄漏** | OSGi、iPOJO |
| **③ 预先固定作用域内自动逆转** | 作用域封闭时自动撤销 | 作用域**必须提前静态固定** | 线性类型、RAII、Rust ownership、RCCS |
| **④ 运行时代理记录回收** | 运行时在**接口层拦截**，记录分配、自动回收 | 组件只能用**平台已知如何释放**的资源 | Nooks、shadow drivers、Akeso |

### ✅ Cordis 到底用哪一派？—— 答案是"哪一派都不是，而是跨派别的组合"

**先给结论，再给证据**：论文**没有把 Cordis 归入四派中的任何一派**。它说 Cordis 与**第④派"最接近"**，但**在关键处不同**；同时又**吸收了第②派"把 effect 和逆配对"的思想**，却**去掉了它的两处短板**。**Cordis = ②的"配对思想" + ④的"运行时自动回收" + 自己的"可组合 + 不限平台"**。

#### 与第④派（代理记录回收）的关系：**最近，但不同**

> **出处**：[P.81] §7.3 "Interposed reclamation" 段末
> *"Reclamation thus follows from a record the runtime maintains rather than from cleanup the developer remembers to write, which makes this family the **closest systems-level precedent for revertible effects.** It differs from Cordis in vocabulary and in reach. The platform fixes what can be recorded ... so a component may hold only resources the platform already knows how to release; a Cordis component instead **introduces effects of its own and supplies an inverse for each atomic one**."*
>
> **翻译**：这派的回收，靠的是"**运行时维护的记录**"而非"开发者记得写的清理"——这就是它成为**最接近的先例**的原因。但它与 Cordis 在**词汇**和**触达范围**上不同：平台**固定了"什么能被记录"**，所以组件**只能持有平台已经知道如何释放的资源**；而 Cordis 的组件**自己引入 effect，并为每个原子 effect 提供逆**。

| | 第④派（Nooks/Akeso） | Cordis |
|---|---|---|
| 谁提供回收能力 | **平台**（预定义好每种资源的释放方式） | **组件自己**（自供逆） |
| 能管理的资源 | 只有平台**已认识**的 | **任意**组件自定义的 effect |
| 回收范围 | 被"一次请求/一次重启"界定 | **整个组件生命周期**，且**传播到依赖方** |

> **出处**：[P.81] *"...whereas Cordis reverts over a component's whole lifetime and propagates removal to its dependents."*

#### 与第②派的关系：**共享"配对"，补上"可组合"与"自动"**

第②派的问题是"逆由开发者手写、易漏"。论文特别拿 **React 的 `useEffect`** 作对照——它是②里**结构上最接近**的（effect 和 cleanup 成对）：

> **出处**：[P.80] §7.3 "Developer-authored recovery" 段
> *"React's useEffect hook comes closest to pairing an effect with its inverse structurally, returning a cleanup the runtime invokes before each re-execution and on unmount. Its shortfall is **composability**: a hook may be called only at the top level ... its effect body accepts neither an async function nor an iterator. Effects thus cannot be assembled from other effects ... Cordis effects carry no such restriction: they are ordinary operations that **compose freely and may run asynchronously** ... so that assembling existing effects requires writing no inverses at all. This **structural pairing of every effect with its inverse makes complete recovery an invariant of the system rather than a matter of developer discipline.**"*
>
> **翻译**：`useEffect` 最接近"effect 与逆配对"，但短板在**可组合性**——hook 只能在顶层调用、不能异步。Cordis 的 effect **没有这些限制**：普通操作、可自由组合、可异步，**组合已有 effect 时完全不用写逆**。这种"每个 effect 都与其逆**结构配对**"使**完整恢复成为系统的固有性质（invariant），而非开发者的自觉**。

**②派 vs Cordis**：
| | 第②派（OSGi/React useEffect） | Cordis |
|---|---|---|
| 逆谁写 | 开发者（易漏）；React 由运行时调但仅顶层 | 每个**原子** effect 写逆；**复合 effect 的逆自动推出** |
| 可组合性 | React：不能组合/不能异步 | **可自由组合、可异步** |
| 可靠性 | 靠自觉（"matter of developer discipline"） | **系统 invariant**（不靠自觉） |

#### 与第①③派的区别（一句话）

- **vs ①（状态迁移）**：① 是**把状态搬到新版本**（不是撤销）；Cordis 是**撤销旧 effect + 从干净状态重应用新组件**——**不需要手写迁移函数**，且**支持彻底卸载**（不只是原地更新）。
  > [P.80] *"Cordis's approach is nonetheless more general in two respects: it needs no hand-written migration functions ... and it supports unloading a component entirely."*
- **vs ③（静态作用域逆转）**：③ 要求"**作用域提前静态固定**"（RAII/线性类型/RCCS 的语义边界）；Cordis **不预设任何作用域**，可撤销**整个组件生命周期内**的任意上下文操作。
  > [P.81] *"Each fixes the scope and reach of reversal statically; Cordis, by contrast, fixes no such scope in advance: it reverts arbitrary context operations over a component's lifecycle."*

### 一句话总结这张"归属"问题

> **Cordis 不属于四派中任何一派，而是"站在②和④的交叉点上再往前走"**：
> - 从 ② 学到"**每个 effect 配一个逆**"，但**去掉"手写"**（复合逆自动推导）+ **补上"可组合、可异步"**；
> - 从 ④ 学到"**运行时自动回收、不靠开发者记忆**"，但**去掉"平台限制"**（组件自引入 effect，能力不受限于平台）；
> - 结果：**完整恢复从"开发者的责任"变成"系统的固有性质"**。

## 6. 空间可组合性：已有方案分三派（§7.4）

> **出处**：[P.81-P.82] §7.4。按"绑定如何响应变化"分三类：

| 派别 | 做法 | 局限 | 代表 |
|---|---|---|---|
| **① 初始化时一次性装配** | 启动时注入依赖 | **不响应式**：provider 被替换/移除时，依赖方**既不停止也不重初始化** | Spring、Guice、Angular、Vue provide/inject |
| **② 响应服务可用性** | 服务出现/消失时自动激活/停用 | 有 deactivation 回调，但 **①手写（易漏）②同步（不能异步等待拆除）** | OSGi Declarative Services、iPOJO |
| **③ 值级响应式** | signal 变化 → 派生计算重算 | 是**值级**粒度，不建模**组件级**生命周期 | FRP、SolidJS signals、Vue reactivity |

**Cordis 的位置（直接回答"用哪一派"）**：与时间维一样，**Cordis 不归属任何单一派别，而是把②的"响应式"与③的"细粒度"结合、并补上②的两处短板**：

- **vs ①（初始化时一次性装配，如 Spring/Guice/Angular/Vue）**：这派**根本不响应式**——provider 在运行时被替换/移除时，依赖方**既不停止也不重新初始化**。Cordis **是响应式的**。
  > **出处**：[P.82] *"neither re-resolves reactively: when a provider is replaced or removed at runtime, existing dependents are neither deactivated nor re-initialized, and none offers lifecycle management of the kind our component state machine provides."*
- **vs ②（响应服务可用性，如 OSGi Declarative Services / iPOJO）**：这派**最接近**，但它的 deactivation 回调有**两个短板**，Cordis 都补上了：
  > **出处**：[P.82] *"All these systems recover through a deactivation callback, which is limited in two ways. First, the callback is **hand-written**, so resource safety rests on developer discipline and a forgotten one leaks silently. Second, the callback is **synchronous**: should teardown require an asynchronous exchange ... the frameworks offer no protocol to await it."*
  >
  > **翻译**：这派靠 deactivation 回调恢复，但①回调是**手写的**（靠自觉，忘一个就静默泄漏）；②回调是**同步的**（若拆除需要异步交互，框架没有协议去 await）。
  >
  > Cordis 的补救：*"deactivation reverts the dependents' accumulated effects（自动撤销累积 effect）, and its inertial Unloading state runs asynchronous teardown to completion before acting on further change（惯性 Unloading 状态跑完异步拆除才响应下一次变化）."*
- **vs ③（值级响应式，如 FRP/SolidJS/Vue reactivity）**：这派是**值级**粒度（signal 变了 → 派生计算重算），**不建模组件级生命周期**。Cordis 是**组件级**粒度 + **异步生命周期**。
  > **出处**：[P.82] *"Cordis's reactive coeffects act at a component-level granularity, adding asynchronous lifecycle semantics that value-level propagation does not model."* 并指出两者**互补**（Cordis 的 coeffect 本身也可以携带 reactive 值）。

> [!note] 一个精辟的对比：Cordis vs COP/AOP
> **出处**：[P.79] §7.2。
> - **COP（Context-Oriented Programming）**：Cordis 与它都"把 context 当一等、运行时可变"。但 **COP 的"context"指环境情景（位置/用户/模式），激活只改变方法派发**；**Cordis 的 context 是中介 effect/coeffect 的实体，激活会运行并完全逆转组件的 effect**。
> - **AOP**：Cordis 的 aspect 类比物是 **coeffect**（多个组件声明依赖的共享中介点）。差异：AOP 的 join point 是"**无感知**"的（代码不知道自己被织入），Cordis 则**限定在组件自己声明的 coeffect 上**——因此**可确定、可追溯**（编排器不用读源码就能知道谁横切了谁）。

## 7. 扩展小结：Cordis 两维的"新"在哪

> **核心结论（回答你的问题）**：Cordis **不归属于任何单一派别**——它是**跨派别重组**：从某一派借"思想"，去掉它的短板，两个维度各取所长。

| 维度     | 已有方案分派                        | Cordis 吸收了谁                       | 去掉了什么短板               | 结果                                   |
| ------ | ----------------------------- | --------------------------------- | --------------------- | ------------------------------------ |
| **时间** | ①状态迁移 ②手写cleanup ③静态作用域 ④代理记录 | **②**（effect↔逆配对）+ **④**（运行时自动回收） | ②的"手写、不可组合"、④的"受平台限制" | **自供逆 + 可组合 + 不限平台 + 撤销整个生命周期**      |
| **空间** | ①一次性装配 ②响应可用性 ③值级响应           | **②**（响应服务可用性）+ **③**（细粒度）        | ②的"手写回调、同步"、③的"只到值级"  | **自动撤销累积 effect + 异步惯性拆除 + 组件级生命周期** |

> 一句话：**时间维 = "②的配对 + ④的自动"，空间维 = "②的响应 + ③的粒度"**，各自补齐短板后统一到 "context 范式" 之下。

> 论文结论（[P.82] §8）：*"Revertible effects address local temporal composability ... Reactive coeffects address local spatial composability ..."*，两者经"context 范式"统一后，把可组合性从**单个组件**提升到**整个交错组件系统**。

---

## 8. 落到 dsh：这两个维度分别对应什么

| 维度 | dsh 里的机制 | 你写插件时的体现 |
|---|---|---|
| **时间可组合性** | `ctx.effect(cb)` 返回 disposer；`ctx.on(...)` 自动移除；`ctx.plugin(child)` 级联卸载 | 你开的定时器/连接，卸载时自动清理（**详见《附2 用官方代码实例讲透》**） |
| **空间可组合性** | `export const inject = ['xxx']` + 响应式激活 | 声明依赖，框架负责等它就绪、它消失我就卸（**详见《附2》**） |

> 这两条的**代码级展开**见本系列《附2 用官方代码实例讲透 effect-coeffect-可组合性》。

---

## 出处汇总

| 内容 | 出处 |
|---|---|
| 两维度定义 | [P.4] §1.1 |
| VSCode 时间/空间局限 | [P.4-P.5] §1.2.1 |
| 静态退化（词法作用域 / 模块导入） | [P.4] §1.1 |
| effect↔时间、coeffect↔空间 | [P.6] §1.3、[P.8] §2.3 |
| 时间可组合性四派对比 | [P.79-P.81] §7.3 |
| 空间可组合性三派对比 | [P.81-P.82] §7.4 |
| Cordis vs COP/AOP | [P.79] §7.2 |
| 结论 | [P.82-P.83] §8 |

> 论文地址：https://arxiv.org/abs/2608.25512 ｜ PDF：https://arxiv.org/pdf/2608.25512
