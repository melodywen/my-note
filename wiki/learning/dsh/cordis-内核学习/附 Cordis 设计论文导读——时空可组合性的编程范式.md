---
type: paper-notes
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 论文导读, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 附 Cordis 设计论文导读——《时空可组合性的编程范式》

> [!info] 版本锚点
> - 论文：**A Programming Paradigm for Spatiotemporal Composability**
> - 作者：Yifan Shi（PKU / DeepSeek-AI）、Wei Zhang（PKU）、Tianyi Cui（DeepSeek-AI）
> - arXiv：**2608.25512**，2026-08-26 提交，92 页
> - 链接：https://arxiv.org/abs/2608.25512 ｜ PDF：https://arxiv.org/pdf/2608.25512
> - **本文是"精简导读"**：只译摘要 + §1 Introduction + §2 Preliminaries 核心 + §5 实现要点；§3–§4 的形式化证明**只意译思想、跳过推导**。逐字原文以 arXiv 为准。
> - 出处标注：`[P.4]` 表示 PDF 第 4 页，`[§1.1]` 表示论文小节。

---

## 一句话：这篇论文在讲什么

> 论文为「**动态组合**」提供了形式化基础：把经典的 **effect（副作用）** 和 **coeffect（上下文依赖）** 概念"提升"为运行时机制，从而让**组件在运行时加载/卸载时不留痕迹，且依赖可声明、可响应式管理**。这套理论实现于 **Cordis**。

> **出处**：摘要 [P.1]。原文：*"We address the two dimensions by lifting classical effect and coeffect concepts to runtime mechanisms."*

---

## 1. 问题背景：为什么需要"动态组合"

> **出处**：§1 Introduction，[P.4]。

组合（composition）是软件工程的基础。传统组合是**静态**的——函数调用、模块导入、类继承在编译期就已确定，运行期固定不变。

但现代软件越来越需要**动态组合**：组件在**运行时**被加载、卸载、重配置。插件系统、自进化 agent harness 都属于这类。**问题在于**：当前实践只能靠"粗粒度机制"（重启整个进程）来重配置，代价是**丢弃运行时状态**。

> 原文：*"modern software increasingly demands dynamic composition, where components are loaded, unloaded, and reconfigured at runtime. Plugin architectures and self-evolving agent harnesses both require systems that can safely add and remove functionality on the fly, yet current practice defers to coarse-grained mechanisms that reconfigure only by restarting, discarding runtime state."* [P.4]

---

## 2. 核心概念：两个正交维度（本文的"总纲"）

> **出处**：§1.1 Dimensions of Composability，[P.4]。

论文指出动态组合有**两个正交维度**（即标题的"spatiotemporal / 时空"）：

### 2.1 时间可组合性（Temporal composability）

> 组件被移除时，它**对共享环境做的所有修改**都必须被**完整、安全地撤销**。这要求追踪组件的每一次资源分配、事件注册、状态变更，并保证移除时有**有序的回收**。

> 原文：*"upon removal of a component, the modifications the component made to the shared environment must be completely and safely reversed. This requires tracking every resource allocation, event registration, and state mutation the component performs, and guaranteeing their orderly reclamation upon removal."* [P.4]

### 2.2 空间可组合性（Spatial composability）

> 组件必须能**以结构化、可验证的方式声明、发现、解析**彼此的依赖。这要求管理**依赖拓扑**，并**响应依赖变化**来协调组件生命周期。

> 原文：*"components must be able to declare, discover, and resolve their dependencies on one another in a structured and verifiable manner. This requires managing dependency topology and coordinating component lifecycles in response to dependency changes."* [P.4]

### 2.3 静态 vs 动态

> 在**静态**场景下：时间可组合性退化为**词法作用域**（如 RAII、bracket 模式），空间可组合性退化为**模块导入解析**。
> 在**动态**场景下（组件运行期来去），两者都变得显著更难：时间维要处理**作用域不受词法约束的长生命周期、有状态副作用**；空间维要处理**运行期出现/消失/改变身份的依赖**。

> 原文：*"In the static setting, temporal composability reduces to lexical scoping (e.g., RAII, bracket patterns), and spatial composability reduces to module import resolution. In the dynamic setting ... both dimensions become significantly harder."* [P.4]

> [!tip] 用 Go 类比
> - **时间可组合性** ≈ Go 的 `defer`（但要处理"作用域超出函数"的长生命周期资源）
> - **空间可组合性** ≈ DI 容器（但要处理"依赖在运行期动态变化"）

---

## 3. 动机：现有系统的两个缺陷

> **出处**：§1.2 Motivating Examples，[P.4-P.5]。

论文以 **VSCode** 为插件系统的代表，指出两个缺陷：

| 缺陷       | 说明                                                                                                                                                                                                  |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **时间局限** | VSCode 所有扩展跑在同一个 *extension host* 进程；**无法在运行时卸载单个扩展的代码**。禁用/卸载必须重启整个 host。虽有 `deactivate` 钩子，但它只是进程终止时的优雅关闭回调，**不是实时卸载**；且该钩子把"副作用销毁"与"创建"（在 `activate`）**分离**，破坏 locality of concern，难以验证清理完整性。    |
| **空间局限** | VSCode 有 `extensionDependencies` 可声明扩展间依赖，但**几乎没人用**（top 100 扩展里只有 7 个声明）。原因是扩展 API 只暴露固定扩展点（commands/views/...），扩展通过**宿主扩展点**贡献而非**彼此依赖**。且 `getExtension().exports` 返回**无类型**（`any`），依赖方无法依赖受检接口。 |

> 原文（关键句）：*"Once an extension's activate function has executed, disabling or uninstalling it requires restarting the entire host"* [P.4]；*"the returned value is untyped (any by default), so the dependent cannot rely on a checked interface"* [P.5]

论文强调：**这两个局限不是 VSCode 独有，而是所有插件系统的通病，只是程度不同**。

> 原文：*"These two limitations are not unique to VSCode; they recur across plugin systems generally."* [P.5]

### 3.1 自进化 agent harness 更需要动态组合

> **出处**：§1.2.2，[P.5]。

未来 harness 可能**在持续服务的同时，生成并部署对自身组件的修改**（模型合成的可复用工具就是一个先兆）：

- **没有时间可组合性**：每次自修改都强制完整重启，丢弃所有进程内累积状态；这个频率下累计不可用时间巨大，进行中的任务被反复打断；更糟的是，**一次错误的自我修改可能让"用来恢复的进程"本身也挂掉**。
- **没有空间可组合性**：每个模块必须**自己**检测并适配其依赖的出现/消失/身份变化，只能用 ad-hoc 手段；更糟的是，**粗糙的代码替换策略可能静默破坏依赖方，或引入只在 reload 时才暴露的循环依赖**。

### 3.2 为什么以前没人做：粗粒度替代品

> **出处**：§1.2.3 The Coarse-Grained Workaround，[P.5-P.6]。

操作系统在**进程**粒度提供时间可组合性；容器编排器在**服务**粒度提供空间可组合性。多数软件就靠这些粗粒度机制"将就"。但代价巨大：每次重启丢弃所有进程内状态，重建需数秒到数分钟；容器级编排无法表达**共享地址空间**内的组件依赖，还为本可本地函数调用的交互引入网络开销。

> 原文：*"each restart discards all process-local accumulated state ... and rebuilding it takes seconds to minutes"*；*"container-level orchestration cannot express dependencies between components sharing an address space"* [P.6]

**结论**：需要一个**细粒度的组合抽象**，在与组件同级的层面管理 effects 和 dependencies。

---

## 4. 学术根基：从 effect/coeffect 到"运行时可操作"

> **出处**：§1.3 Contributions + §2 Preliminaries，[P.6-P.8]。

### 4.1 effect 与 coeffect 各管一维

论文借用两个已有理论：
- **effect 系统**：为"计算**如何修改**环境"提供形式化词汇；
- **coeffect 系统**：为"计算**如何依赖**环境"提供形式化词汇。

> 原文：*"effects provide the formal vocabulary for reasoning about environmental modifications, and coeffects for reasoning about environmental requirements."* [P.6]

**对应关系**（§2.3 [P.8]）：
- **时间可组合性** ← 有状态 effect（要对环境做持久变换，撤销需要它有逆）
- **空间可组合性** ← coeffect（正是它捕获的"依赖"，管理它 = 对照环境供给去解析）

### 4.2 但经典 effect/coeffect 是"静态工具"

> 经典的 effect 只在**词法固定作用域**内追踪、由**编译期 handler** 消解；coeffect 注解在**执行前确定**的上下文上验证。而动态组合要求这些保证对**运行期来去的组件**、**持续演化的上下文**成立——**没有固定词法作用域能界定一个部署后才加载的插件，没有编译期上下文能预见运行期配置涌现的依赖**。
>
> **出处**：§2.3，[P.8]。

### 4.3 论文的 5 项贡献

> **出处**：§1.3 Contributions，[P.6]。

| # | 贡献 | 位置 |
|---|---|---|
| 1 | **可撤销 Effect（revertible effects）**：每次上下文变换都携带一个运行时持有的**显式逆**，追踪与恢复都保持组合律 → **局部时间可组合性** | §3.1 |
| 2 | **响应式 Coeffect（reactive coeffects）**：组件把所需 coeffect 声明为 spec，每次上下文变化都被分类为**激活 / 停用 / 中性**，驱动组件开关 → **局部空间可组合性** | §3.2 |
| 3 | **Context 范式**：把 effect 上下文与 coeffect 上下文**统一为单一上下文类型**，一切 effect/coeffect 经由它中介，中介诱导出一种"观察等价"——不同组件的 effect 借此达到**互不干扰** | §3.3 |
| 4 | **动态组合演算**：把两机制组合为"组件"概念并给出操作语义，元理论把时空可组合性从单组件提升到整个系统 | §4 |
| 5 | **Cordis 实现**：核心库实现效果追踪 + coeffect 解析，外加声明式组件加载器（配置调和 + HMR） | §5 |

> [!important] 一句话抓住 §3 的核心
> §3 的中心思想是：把承载 effect/coeffect 的"类型上下文"**变成运行时的一等实体**——effect 建模为「上下文变换 + 运行时持有的逆」，coeffect 建模为「声明的依赖 + 对它的变化分类」。

---

## 5. 落地：Cordis 怎么实现（理论 → 代码）

> **出处**：§5 Implementation，[P.57-P.62]。

Cordis 是一个 **meta-framework**（元框架）：它**不预设任何具体场景**（不像 web 路由 / ORM / UI 框架），**唯一职责是提供通用的动态组合语义**。

> 原文：*"it prescribes no concrete scenario; its sole responsibility is to supply universal dynamic composition semantics."* [P.57]

分三层：① 核心库（直接实现 effect/coeffect 系统）；② 组件加载器（核心之上加配置调和 + HMR）；③ 应用框架如 Koishi。

### 5.1 理论与实现的对应表（Table 2，最有价值的一张表）

> **出处**：Table 2，[P.58]。这是把论文数学符号翻译成 Cordis API 的**官方对照表**：

| 论文（理论） | Cordis 实现（代码） |
|---|---|
| `Γ∞` 上下文 | `ctx`（一等上下文） |
| `𝔈Γ, ℑΓ` effect 回调 | **`ctx.effect(callback)`** |
| `get(k)`, `set(k,v)` | `ctx.get(key)`, `ctx.set(key, value)` |
| `isolate(k, r)` | `ctx.isolate(key, realm)` |
| `intercept(k, ν)` | `ctx.intercept(key, metadata)` |
| 组件实例化 `⟨d,p,e,...⟩` | **`fiber`** |
| `d` 依赖规范 | `fiber.inject` |
| `e` 效果函数 | `fiber.apply` |
| `θ` 生命周期状态 | `fiber.state`（`LOADING`/`ACTIVE`...） |
| `recover` 累积逆 | **`fiber.dispose`** |
| O-Insert / O-Retire | `ctx.use` 及其回调的逆 |

### 5.2 三个关键机制（对应你写插件会碰到的）

> **出处**：§5.1.1–§5.1.3，[P.59-P.61]。

1. **Effect 追踪（`ctx.effect`）**：Cordis 里**每一次上下文变更都流经 `ctx.effect` 这一个原语**——coeffect 提供、组件实例化、其它一切上下文变更，都归约到 `ctx.effect` 调用。所以**凡是通过上下文做的操作，都会被自动追踪并在卸载时撤销**。逆按 **LIFO（后进先出）**叠加。
   > 原文：*"Every context mutation in Cordis flows through a single primitive, ctx.effect ... so any operation performed through the context is automatically tracked and reverted upon component unloading."* [P.59]

   > ⚠️ 注意：`ctx.effect` **不检查逆是否真的能撤销**——"提供的逆确实能回滚"是**组件作者的责任**，不是运行时验证的性质。[P.59]

2. **Coeffect 操作（`ctx.get`/`set`/`isolate`/`intercept`）**：`set(k,v)` 本身也是 `ctx.effect`（因为类型是 `𝔈`），自动继承追踪与恢复。两个层：`@@store`（值存储）+ `@@isolate`（realm 表）。`set` 时 `notify` 通知依赖方，触发 `refresh` 重评估——这就是**响应式**。
   > 出处：§5.1.2，[P.60]。

3. **组件生命周期（`ctx.use` → `fiber`）**：组件 = `inject`（coeffect spec）+ `apply`（effect 函数）。实例化即**父组件的一次普通被追踪 effect**，所以**卸载父组件会级联卸载子组件**。`refresh` 根据 coeffect store 重算 `fiber.target`，触发 `reload`/`unload`（**惯性状态机**：一旦进入转换，跑完才响应新变化）。
   > 出处：§5.1.3，Algorithm 4/5，[P.61-P.62]。

---

## 6. 这篇论文对你学 dsh 的意义

| 论文概念 | 你会遇到的 dsh 现象 |
|---|---|
| `ctx.effect` = 唯一上下文变更原语 | 为什么"注册可逆"是 dsh 的基石；为什么卸载插件不留痕迹 |
| 逆按 LIFO 恢复 | 为什么 `ctx.effect` 的 disposer 顺序是后进先出 |
| 组件 = `inject` + `apply` | 为什么插件要写 `inject` 和 `apply(ctx)` |
| coeffect spec → 响应式激活 | 为什么 `inject: ['settings']` 能让插件"等待服务就绪才启动" |
| 父组件效应级联 | 为什么卸载父插件会带走子插件 |

> [!note] 不要被形式化符号劝退
> §3–§4 的 `𝔈Γ`、`track`/`recover`、定理证明是**理论根基**，工程使用时**不需要**掌握。你只需要记住：**Cordis 把"副作用"和"依赖"从编译期概念，变成了运行时可操作的两件事**——这正是它区别于普通 DI 框架的地方。

---

## 7. 出处汇总（可逐条复查）

| 编号 | 内容 | 出处 |
|---|---|---|
| [P.1] | 摘要、总述 | arXiv PDF 第 1 页 |
| [P.4] | §1 Introduction + §1.1 两维度 | PDF 第 4 页 |
| [P.5] | §1.2 动机（VSCode / harness / 粗粒度替代） | PDF 第 5 页 |
| [P.6] | §1.2.3 收尾 + §1.3 五项贡献 | PDF 第 6 页 |
| [P.7-8] | §2 Preliminaries（effect/coeffect 理论） | PDF 第 7-8 页 |
| [P.57] | §5 开头：Cordis 是 meta-framework | PDF 第 57 页 |
| [P.58] | Table 2：理论↔实现对应表 | PDF 第 58 页 |
| [P.59-62] | §5.1 Core Library（effect/coeffect/生命周期） | PDF 第 59-62 页 |

> 原始 PDF 本地缓存：`/tmp/cordis-paper.pdf`（如清理过，重新 `curl -sL https://arxiv.org/pdf/2608.25512 -o cordis-paper.pdf`）
