---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 01 Cordis 是什么——dsh 的插件框架

> [!info] 版本锚点
> - dsh：**0.1.5-rc.1**（全局 npm 安装）
> - 官方源码：master `0d1f50007f`（`~/ai-work/dsh/deepseek-harness/`，2026-09-16 fetch）
> - 本篇所有论断附**出处锚点**（本地路径 / 官方文档 / 论文），可自行复查
> - 教学法：先讲清"是什么、为什么"，再动手（见仓库 `AGENTS.md`「协作姿态」）

## 0. 本篇要回答什么

1. Cordis 是什么？
2. dsh 和 Cordis 什么关系？
3. 为什么 dsh 要搞个插件框架（设计意图）？

---

## 1. Cordis 是什么

**官方定义**：Cordis 是一个 **TypeScript 插件框架**，为需要「显式依赖注入、作用域服务、生命周期管理的清理、可选的配置驱动加载」的应用而生。

> **出处**：`vendor/cordis/README.md` 首段原文 —— *"Cordis is a TypeScript plugin framework for applications that need explicit dependency injection, scoped services, lifecycle-managed cleanup, and optional configuration-driven loading."*
> 本地路径：`~/ai-work/dsh/deepseek-harness/vendor/cordis/README.md`

**在 dsh 语境下**，官方中文文档的原话是：

> Cordis 是 DeepSeek Harness **底层以 vendor 方式引入的插件框架**。
>
> **出处**：`docs/cordis-primer.zh.md` 首段。本地路径：`~/ai-work/dsh/deepseek-harness/docs/cordis-primer.zh.md`

**它自己不做业务**——只负责"管插件"。这一点由它的能力清单佐证：核心包 `cordis` 只提供 *context、插件注册表、fiber 生命周期、事件、服务、logger*；其余能力（loader、HMR、timer 等）都是**可选的独立包**。

> **出处**：`vendor/cordis/README.md` 的 Packages 表格。

### 用 Go 经验类比

| Cordis | 你 Go 里的对应 |
|---|---|
| Cordis 框架 | `uber/fx`（DI + 生命周期容器） |
| 插件 | 一个可注册的模块 |
| `ctx` | DI 容器（服务挂在其上） |
| 加载 / 卸载 | 服务启动 / graceful shutdown |

> [!note] 类比是脚手架，不是等号
> 见本文第 3 节的"论文"——Cordis 有 Go DI 框架没有的**形式化基础**（可撤销 effect / 响应式依赖）。类比只为快速定位，差异后续章节展开。

---

## 2. dsh 与 Cordis 的关系

官方一句话讲清了：

> **dsh** 是 DeepSeek AI 开发的开源 agent harness，**构建于「一切皆插件」的架构之上，由 Cordis 驱动**。
>
> **出处**：`README.zh.md` 第 5 行。原文（英）：*"It is built on an architecture where everything is a plugin, driven by Cordis."* 本地路径：`~/ai-work/dsh/deepseek-harness/README.zh.md`

即：`dsh = Cordis（框架）+ 一大堆插件（功能）`。

### 「一切皆插件」到底指什么？—— 原文证据

> *"产品的每一部分都是插件，包括**模型适配器、工具注册表、会话日志，以及 agent loop（智能体循环）本身**，因此每个都可以从配置替换。"*
>
> **出处**：`docs/architecture.zh.md`「Cordis」一节。本地路径：`~/ai-work/dsh/deepseek-harness/docs/architecture.zh.md`

**"没有特权内核"**——同一份文档紧接着写：

> *"不存在需要打补丁的特权内核：扩展 dsh 的方式是把插件挂载到其他插件旁边，而各项注册都是副作用，会在其插件卸载时撤销。"*
>
> **出处**：同上，`docs/architecture.zh.md`。

> [!note] 英文原文（供交叉核对）
> *"There is no privileged core to patch: you extend dsh by mounting a plugin beside the others, and registrations are effects that unwind when their plugin unloads."*

---

## 3. 为什么 dsh 要搞插件框架？—— 设计意图

这一节回答"**为什么**"，来源是 dsh 背后的**学术论文**（一手）。

> 论文：**《A Programming Paradigm for Spatiotemporal Composability》**（时空可组合性的编程范式）
> 作者：Yifan Shi, Wei Zhang, Tianyi Cui（**Peking University / DeepSeek-AI**）
> arXiv:2608.25512，2026-08-26 提交
> 链接：https://arxiv.org/abs/2608.25512

论文摘要的核心论点（直接引用并翻译）：

> 现代软件（从插件系统到自进化 agent harness）越来越需要**动态组合**，但其形式化基础尚不完善。作者指出问题的**两个正交维度**：
> - **时间可组合性（temporal composability）**：组件被移除时，**完全回滚其副作用**的能力；
> - **空间可组合性（spatial composability）**：**声明并响应式管理**组件间依赖的能力。
>
> 论文把这套机制实现于 **Cordis** —— 一个"时空可组合性的元框架（meta-framework）"。
>
> **出处**：arXiv:2608.25512 摘要（https://arxiv.org/abs/2608.25512）。

**这说明**：Cordis 不是"随手写的插件系统"，而是**有形式化基础的框架设计**。它要解决的核心问题正是你 Go 里也会遇到的：

| 维度         | 大白话                     | Cordis 的机制       | Go 里的相近物              |
| ---------- | ----------------------- | ---------------- | --------------------- |
| **时间可组合性** | 组件卸载时，它留下的痕迹要**能完全擦干净** | 可撤销的 effect      | `defer` + 关闭钩子（但更结构化） |
| **空间可组合性** | 组件要**声明依赖谁、谁就绪才启动**     | `inject` + 响应式激活 | DI 框架的依赖注入            |

> [!important] 这两个词是理解 dsh 的"总纲"
> 后面学的 `ctx.effect`（可撤销）、`inject`（依赖声明）、`ctx.on`（事件监听自动撤销）——**全部服务于这两个可组合性**。记住这两个词，后面每学一个概念都可以问自己："它是在解决时间维、还是空间维？"

---

## 4. 一个必要的澄清：dsh 里的 Cordis 是「vendored 改名版」

未来你读 cordis 文档/源码时**一定会困惑**：为什么 dsh 里写的是 `@deepseek-ai/cordis`，而上游 GitHub 是 `cordiverse/cordis`？答案是 **vendored + rescope（源码内嵌 + 改名）**：

> Cordis 框架及其基础库以**源码形式 vendored** 在 `vendor/` 下，并以 `@deepseek-ai` scope 发布……*"用上游名发布等于在 registry 上占用别人的名字"*。
>
> **出处**：`docs/rescope.zh.md` 首段。

**改名映射**（部分）：

| dsh 里的名字 | 上游名字 |
|---|---|
| `@deepseek-ai/cordis` | `cordis` |
| `@deepseek-ai/cordis-plugin-loader` | `@cordisjs/plugin-loader` |
| `@deepseek-ai/cordis-plugin-include` | `@cordisjs/plugin-include` |

> **出处**：`vendor/README.md` 的 Manifest 表格（含上游版本与 commit）。

**为什么这么做**（官方理由）：*"so that the harness fully owns its framework layer (auditable, patchable, pinned)"* —— 让 harness **完全拥有**自己的框架层（可审计、可打补丁、可钉版本）。

> **出处**：`vendor/README.md` 首段。

> [!tip] 读源码时的换算规则
> 写 dsh 插件 → import 用 `@deepseek-ai/*`；查上游 cordis 文档 → 名字要换回 `cordis` / `@cordisjs/*`。完整映射见 `docs/rescope.zh.md`。

---

## 5. 本篇核心结论

1. **Cordis 是 dsh 底层的插件框架**，官方定位是"需要显式依赖注入 + 生命周期清理的 TypeScript 插件框架"（出处：`vendor/cordis/README.md`）。
2. **dsh = Cordis + 一堆插件**，连 agent-loop、模型适配器都是插件，**没有特权内核**（出处：`docs/architecture.zh.md`）。
3. **搞插件框架是为了"时空可组合性"**：时间维=副作用可回滚，空间维=依赖可声明（出处：arXiv:2608.25512）。
4. **dsh 里的 Cordis 是 vendored 改名版**，读源码要按 `docs/rescope.zh.md` 做名字换算。

---

## 6. 出处汇总（可逐条复查）

| 编号 | 来源 | 本地路径 / 链接 |
|---|---|---|
| [P1] | Cordis 官方定义 | `vendor/cordis/README.md` |
| [P2] | Cordis 是 dsh 底层框架 | `docs/cordis-primer.zh.md` 首段 |
| [P3] | dsh 自述（一切皆插件 + Cordis 驱动） | `README.zh.md` |
| [P4] | dsh 架构（无特权内核 / 一切皆插件） | `docs/architecture.zh.md` |
| [P5] | 设计论文（时空可组合性） | https://arxiv.org/abs/2608.25512 |
| [P6] | vendored + rescope 机制 | `docs/rescope.zh.md`、`vendor/README.md` |

> 本地根目录：`~/ai-work/dsh/deepseek-harness/`

## 下一篇

- `02 插件是什么形态——函数、对象与类`（规划中）
