---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, 动手实战, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 01 第一个真插件——从"最小工程"走进"真实 dsh"

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/basic/index.zh.md`（第一个插件）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 前置：已完成**阶段一**（cordis-tutorial 七讲，实验02–07）
> - **本文是阶段二的起点**：从"临时最小工程跑 Cordis"升级到"把插件装进真实 dsh"
> - 与官方的差异：官方用 `deepseek-harness/scratch-plugin/` + `pnpm dsh web`；**本文改在 `dsh-learn/example/plugins/` + `dsh-learn/start.sh`**（遵守 AGENTS.md，不污染官方仓库）

## 阶段二在学什么

阶段一（七讲）你学的是 **Cordis 内核**——用**最小独立工程**理解"插件/服务/事件/配置/组合"这些**模式**。

阶段二换战场：**把同样的模式用到真实 dsh 上**。两者的关系：

| | 阶段一（七讲） | 阶段二（develop 教程） |
|---|---|---|
| 工程 | `test_workspace/cordis-tutorial/lesson-*`（自包含最小工程） | `dsh-learn/example/plugins/*`（真实 dsh 插件） |
| 启动 | `npm start`（自己的 `bin.js`） | `./start.sh`（启动真实 dsh） |
| 挂载 | `cordis.yml` 顶层列表 | `cordis.patch.yml` 的 `insert:` 覆盖层 |
| 目标 | 理解**模式** | 写出**能用的插件** |

**关键认知**：**写插件的能力你在七讲已经练过了**——本阶段只是换环境、换挂载方式。官方原话：

> **出处**：`docs/user/develop/basic/index.zh.md`——*"在 Harness 中，插件是一个导出 `apply` 函数的 TypeScript 模块。框架在加载时调用 `apply`，传入一个 `ctx`（上下文对象），你通过 `ctx` 注册能力。"*

---

## 先讲理论（动手前必读）

### 概念① 插件三要素：`name` + `apply` + （可选）`inject`

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'hello-plugin'          // 插件名（给框架，见实验03"两个 name"）
export function apply(ctx: Context) {        // 框架加载时调用
  console.log('[hello-plugin] plugin loaded!')
}
```

> **出处**：`docs/user/develop/basic/index.zh.md`——*"这就是完整配置。"*

回想**实验03 的"两个 name"**：`export const name` 是**插件名**（给框架做标识），不是服务名。这里再次印证——**你 export 出去的东西是给框架读的**。

### 概念② 挂载方式变了：从"顶层列表"到"`insert:` 覆盖层"

七讲里你在 `cordis.yml` 写：

```yaml
- name: './hello.ts'          # ← 顶层列表：从零定义
```

dsh 插件用 **patch 覆盖层**：

```yaml
- insert:                      # ← 往已有 profile 配置里"插入"
    - id: hello-plugin
      name: '/绝对路径/plugins/hello-plugin/hello-plugin.ts'
```

> **出处**：`example/plugins/codebuddy-llm/cordis.patch.yml`（本仓库现有插件）+ 官方 `develop/basic/index.zh.md`——*"插件路径必须是绝对路径。patch 文件只贡献配置，不会改变 loader 解析模块路径时使用的 profile 目录。"*

**为什么是 `insert` 而不是顶层列表**：dsh 的 profile 已有大量内置插件（base 层），你的 patch 是**在它之上再叠一层**（AGENTS.md 说的"配置五层叠加"里的**用户层**）。`insert` = 插入，不改动已有配置。

**为什么必须绝对路径**：loader 解析模块用的目录是 **profile 目录**，不是你 patch 文件所在的目录。所以写相对路径会解析失败——**只能用绝对路径**。

### 概念③ `start.sh` 是你的启动器（比官方 `pnpm dsh web` 更适合本仓库）

官方教程让你 `pnpm dsh web --patch ./scratch-plugin/cordis.yml`；本仓库封装成 `start.sh`：

> **出处**：`dsh-learn/start.sh`——*"启动 dsh 时，一律优先使用本仓库根目录的 `./start.sh`……已自动把本仓库的 `example/plugins/codebuddy-llm/cordis.patch.yml` 作为 `--patch` 层挂上。"*

它默认挂 `codebuddy-llm` 那一层，并支持**再叠一层**：

```sh
./start.sh --patch example/plugins/hello-plugin/cordis.patch.yml
```

> **出处**：`start.sh` 头部注释——*"`./start.sh --patch extra.yml` —— 额外再叠一层 patch"*

### 概念④ 自动清理（= 实验02 的时间可组合性）

> **出处**：`docs/user/develop/basic/index.zh.md`——*"通过 `ctx` 注册的任何东西——事件监听、工具、定时器——在插件卸载时都会被自动清理。你不需要手动 removeListener 或 clearInterval。"*

需要手动清理的资源（如网络连接）用 `ctx.effect()` 返回清理函数——**这就是实验02 学的**。

### 概念⑤ 插件的三种形态

> **出处**：`docs/user/develop/basic/index.zh.md`「插件的三种形态」节

| 形态 | 写法 | 何时用 |
|---|---|---|
| **函数** | `export function apply(ctx)` + `export const name` | 大多数情况 |
| **对象** | `export default { name, inject, apply }` | 想纯对象声明 |
| **类** | `export default class extends Service` | 需要**提供服务**给别的插件（实验03） |

> **出处**：官方——*"大多数情况下，函数形式足够了。当插件需要向其他插件提供服务时，可使用类形式。"*

---

## 动手：写第一个真插件 `hello-plugin`

> **规则（AGENTS.md）**：动手环节"你动手"——**插件代码你自己敲**，AI 只搭骨架、讲原理。

### 第 1 步：建插件目录

```sh
cd ~/ai-work/dsh/dsh-learn
mkdir -p example/plugins/hello-plugin
```

### 第 2 步：写插件本体 `hello-plugin.ts`（**你敲**）

创建 `example/plugins/hello-plugin/hello-plugin.ts`：

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'hello-plugin'

export function apply(ctx: Context) {
  console.log('[hello-plugin] plugin loaded!')
}
```

> **出处**：`docs/user/develop/basic/index.zh.md`（代码逐字一致）

### 第 3 步：写挂载层 `cordis.patch.yml`（**你敲**）

创建 `example/plugins/hello-plugin/cordis.patch.yml`：

```yaml
# hello-plugin 挂载层
# 用法：./start.sh --patch <本文件绝对路径>
# （`name` 必须是插件文件的绝对路径——patch 只贡献配置，不改 loader 的解析目录）
- insert:
    - id: hello-plugin
      name: '/Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/hello-plugin/hello-plugin.ts'
```

> **出处**：结构照搬 `example/plugins/codebuddy-llm/cordis.patch.yml`（本仓库现有插件）；`name` 需绝对路径见官方 `develop/basic/index.zh.md`
> ⚠️ **路径按你自己的实际路径改**（用 `pwd` 确认）

### 第 4 步：（建议）写 `package.json`

创建 `example/plugins/hello-plugin/package.json`：

```json
{
  "name": "hello-plugin",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "dsh 插件：第一个真插件（加载时打印一行日志）"
}
```

> **出处**：结构照搬 `example/plugins/codebuddy-llm/package.json`

### 第 5 步：干跑验证命令（不真正启动）

```sh
DRY_RUN=1 ./start.sh --patch example/plugins/hello-plugin/cordis.patch.yml
```

会打印完整命令，确认 `--patch` 挂了两层（codebuddy + hello-plugin）。

> **出处**：实测（2026-09-16）——`DRY_RUN=1` 只打印不执行

### 第 6 步：启动 dsh

```sh
./start.sh --patch example/plugins/hello-plugin/cordis.patch.yml
```

启动过程中，终端应打印：

```
[hello-plugin] plugin loaded!
```

> **出处**：官方 `develop/basic/index.zh.md`——*"启动期间，终端会打印 `[hello-plugin] plugin loaded!`。"*

**看到这行 = 你的第一个真插件装进 dsh 成功了。**

### ✅ 实测记录（2026-09-16，本人跑通）

**干跑验证**（`DRY_RUN=1`）确认挂了两层 patch：

```
→ 完整命令  : dsh web --patch .../codebuddy-llm/cordis.patch.yml --patch .../hello-plugin/cordis.patch.yml
（DRY_RUN=1，仅打印不执行）
```

**真实启动**后，终端输出（节选）：

```
→ 完整命令  : dsh web --patch /Users/.../codebuddy-llm/cordis.patch.yml --patch /Users/.../hello-plugin/cordis.patch.yml
[hello-plugin] plugin loaded!
```

> **出处**：本人实测（`dsh-learn/example/plugins/hello-plugin/`，`./start.sh --patch <绝对路径>`，2026-09-16）——`[hello-plugin] plugin loaded!` 成功打印

> [!note] 启动命令用绝对路径更稳
> 实测用**绝对路径**传 `--patch`（`./start.sh --patch /Users/.../hello-plugin/cordis.patch.yml`）；`start.sh` 也支持相对路径，但绝对路径可避免"当前工作目录"影响，更稳。

> [!tip] 这一步你可能踩的坑
> - **`name` 用相对路径** → loader 解析不到（因它按 profile 目录解析）。必须**绝对路径**。
> - **忘了 `--patch`** → `start.sh` 只挂 codebuddy 层，你的插件不会被加载。
> - **`id` 冲突** → `id` 是配置项标识，别和已有的（如 `codebuddy-llm`）重名。

---

## 阶段二 vs 阶段一：一张对照表

| 概念   | 阶段一（七讲）                           | 阶段二（本篇）                        |
| ---- | --------------------------------- | ------------------------------ |
| 插件形态 | `export function apply`           | **一样**                         |
| 声明依赖 | `export const inject`             | **一样**                         |
| 自动清理 | `ctx.effect`                      | **一样**                         |
| 挂载配置 | `cordis.yml` 顶层列表                 | `cordis.patch.yml` 的 `insert:` |
| 启动器  | `npm start`                       | `./start.sh`                   |
| 工程位置 | `test_workspace/cordis-tutorial/` | `dsh-learn/example/plugins/`           |

**结论**：**核心模式没变，变的是环境与挂载方式。** 七讲打的地基直接复用。

---

## 一页纸总结

| 概念 | 一句话 | 出处 |
|---|---|---|
| dsh 插件 | 导出 `apply(ctx)` 的 TS 模块 | 官方 basic/index |
| 三要素 | `name` + `apply`（+ 可选 `inject`） | 官方 basic/index |
| `insert:` 覆盖层 | 往已有 profile 配置插入一条 | 官方 basic/index + codebuddy 样板 |
| 绝对路径 | patch 只贡献配置，loader 按 profile 目录解析 | 官方 basic/index |
| `start.sh` | 封装 `pnpm dsh web --patch`，默认挂 codebuddy 层 | 本仓库 start.sh |
| 自动清理 | `ctx` 注册的资源随卸载撤销 | 官方 basic/index + 实验02 |
| 三种形态 | 函数 / 对象 / 类 | 官方 basic/index |

## 下一步

- **02 开发一个工具**：用 `defineTool` 注册一个 `greet` 工具，在 Web UI 里让模型调用（对应官方 `basic/tool.zh.md`）
- **03 插件配置**：让插件接受 `cordis.yml` 里的 `config`（对应官方 `basic/config.zh.md`）
