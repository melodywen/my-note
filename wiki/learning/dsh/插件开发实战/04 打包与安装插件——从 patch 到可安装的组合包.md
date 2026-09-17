---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, 动手实战, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 04 打包与安装插件——从 `--patch` 到可安装的组合包

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/basic/publish.zh.md`（打包与安装插件）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 前置：完成 [01](01%20第一个真插件——从最小工程走进真实%20dsh.md) / [02](02%20开发一个工具——把能力暴露给模型.md) / [03 插件配置](03%20插件配置——让插件接受用户在%20yml%20里传参.md)
> - **本篇是 `develop/basic` 收官**：把插件从"本地 patch"升级为"可安装包"
> - 实测环境：`dsh 0.1.5-rc.1`，pnpm `10.11.0`

## 这个实验要验证什么

一句话：**验证"把插件打包成可安装的组合包（bundle），用 `dsh plugin add` 装进 profile"——这是插件从"本地开发"走向"可分发"的关键一步。**

前几篇你用 `--patch` 挂**本地插件文件**（绝对路径）。04 篇把它变成**npm 包**，用 `dsh plugin add` 安装。

官方原话：

> **出处**：`docs/user/develop/basic/publish.zh.md`——*"前几篇教程通过 `--patch` overlay 加载本地插件。本教程把它打包成可安装的**组合包**（bundle），用 `dsh plugin add` 安装进一个 **profile**，并解释决定组合后配置的层顺序。"*

用你的 Go 经验类比：前面像**本地写个 main.go 直接跑**；04 篇像**打成 module 包并 `go get` 安装**——从"本地代码"到"可分发的依赖"。

---

## 先讲理论（动手前必读）

### 概念① 两个概念、两种 manifest：bundle vs profile

**这是 04 篇的理论核心**。官方把"安装机制"拆成两个概念：

> **出处**：`docs/user/develop/basic/publish.zh.md`——*"**组合包**是附带一个配置层的 npm 包。它的 manifest 声明 `dsh.bundle`，回答的是'这个包贡献什么？'：一个插入或覆盖插件行的 patch 文件。**profile** 是位于 `$DSH_HOME/profiles/<name>` 下、描述一份可启动组合的目录。它的 manifest 声明 `dsh.profile`，回答的是'这套配置由哪些组合包按什么顺序组成？'。"*

|          | **bundle（组合包）**            | **profile**                  |
| -------- | -------------------------- | ---------------------------- |
| 是什么      | **你编写并分发**的 npm 包          | **用户用来启动**的组合目录              |
| manifest | `dsh.bundle`               | `dsh.profile`                |
| 回答       | "这个包**贡献什么**？"（一个 patch 层） | "这套配置**由哪些 bundle 组成**？"     |
| 位置       | 任意（npm / 本地 / git）         | `$DSH_HOME/profiles/<name>/` |

> **出处**：官方——*"组合包是你编写并分发的东西；profile 是用户用 `dsh --profile <name>` 启动的东西。**没有东西同时是两者**。"*

Go 类比：**bundle ≈ 一个 library 包**（贡献能力）；**profile ≈ 一个 `main` 的依赖清单**（决定了用哪些库、什么顺序）。

### 概念② bundle 的 manifest：`dsh.bundle`

```json
{
  "name": "dsh-hello-bundle",
  "version": "0.1.0",
  "type": "module",
  "main": "index.js",
  "files": ["index.js", "cordis.patch.yml"],
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
```

> **出处**：`docs/user/develop/basic/publish.zh.md`（bundle manifest 示例，逐字一致）

**关键**：`dsh.bundle.patch` 指向一个 patch 文件——就是**你前几篇写的 `cordis.patch.yml` 同款**。

**bundle 的 patch 与 `--patch` overlay 的区别**：

> **出处**：官方——*"这个 patch 与你写过的 `--patch` overlay 一样，是一个 patch 条目的 YAML 数组；区别是**插件行按包名而不是相对源码路径引用这个包**，这样 Node 的模块解析才能找到已安装的代码。"*

```yaml
- insert:
    - id: hello-bundle
      name: dsh-hello-bundle     # ← 包名（不是绝对路径！）
```

**这解决了 01–03 篇的"绝对路径 + 符号链接"痛点**——包名由 Node 正常解析，**不需要符号链接了**。

### 概念③ 安装：`dsh plugin --profile <name> add ...`

```sh
dsh plugin --profile demo add ./hello-bundle
```

> **出处**：官方——*"`dsh plugin --profile <name> <args...>` 在 profile 目录内**转发给 pnpm**，因此所有 pnpm 子命令都可用。"*

首次使用会：
1. **初始化 profile**（`@deepseek-ai/dsh-base` 作为第一个 bundle）
2. **pnpm link** 该 checkout
3. 因为包声明了 `dsh.bundle`，**追加进 `dsh.profile.bundles`**

### 概念④ 加载顺序（4 层）

> **出处**：`docs/user/develop/basic/publish.zh.md`「加载顺序」节——官方列出**从空根之上逐层组合**：

| 顺序 | 层 | 说明 |
|---|---|---|
| 1 | profile 的 `dsh.profile.bundles` 里的各 bundle patch | 按列表顺序（先是 `dsh-base`，再各已装 bundle） |
| 2 | profile 自己的 `cordis.patch.yml` | 用户 patch |
| 3 | home 级 `$DSH_HOME/cordis.patch.yml` | 各 profile 共享 |
| 4 | 每个 `--patch <path>` overlay | 按 argv 顺序 |

**规则**：*"后应用的层按行胜出，且 patch 会**替换**目标行的整个 `config` 值，而不是深度合并各键。"*

> **出处**：官方——*"你的 patch 可以按 `id` 覆盖前面各层的行……但必须重述该行需要的每一个键，而不是只写改动的那个。"*

Go 类比：像**配置的分层覆盖**（如 Kustomize overlay）——后层覆盖前层，且是**整块替换 config**（不是深合并）。

### 概念⑤ GitHub 安装的"构建脚本坎"（重要坑）

> **出处**：`docs/user/develop/basic/publish.zh.md`「从 GitHub 安装：构建脚本这道坎」节——*"git 安装拉取的是**源码，不是构建产物**：没有任何环节运行你的 `build` 脚本，因此 TypeScript 包到手时没有 `lib/` 输出，加载会失败。"*

**两种规避方式**：
- **发布到 npm**：`pnpm publish` 时构建好 `lib/`，用户装的是预构建代码
- **交付 tarball**：`pnpm pack` 打包，用户 `dsh plugin add ./xxx.tgz`

**安全提醒**：git 安装需用户授权 `allowBuilds`——*"请把这项授权视为**允许该包的代码在安装时于你的机器上执行**"*。只对可信包授权，并锁 commit。

---

## 动手：做第一个可安装 bundle

> **规则（AGENTS.md）**：动手环节"你动手"。本文操作已全部**实测跑通**。

### 第 1 步：建 bundle 目录与文件

```sh
cd ~/ai-work/dsh/dsh-learn/plugins
mkdir -p publish-demo/hello-bundle
```

**三个文件**（逻辑与官方一致）：

`hello-bundle/package.json`：

```json
{
  "name": "dsh-hello-bundle",
  "version": "0.1.0",
  "type": "module",
  "main": "index.js",
  "files": ["index.js", "cordis.patch.yml"],
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
```

`hello-bundle/index.js`：

```js
export const name = 'hello-bundle'

export function apply() {
  console.log('[hello-bundle] bundle plugin loaded!')
}
```

`hello-bundle/cordis.patch.yml`（**注意按包名引用**）：

```yaml
- insert:
    - id: hello-bundle
      name: dsh-hello-bundle
```

> **出处**：`docs/user/develop/basic/publish.zh.md`（三文件结构逐字一致）

> [!note] 为什么用 `.js` 而不是 `.ts`
> 官方 bundle 示例用 `.js`（预编译）——这避免了"git/npm 安装时没有构建步骤"的坑（概念⑤）。本地 `--patch` 你能用 `.ts`（tsx 转译），但**要分发的包应在发布前构建**。本 demo 用最简 `.js` 跑通流程。

### 第 2 步：安装进 demo profile

```sh
cd ~/ai-work/dsh/dsh-learn/plugins/publish-demo
dsh plugin --profile demo add ./hello-bundle
```

**实测输出**（2026-09-16）：

```
dsh: initialized profile demo at /Users/melodycchen/.dsh/profiles/demo
dependencies:
+ dsh-hello-bundle link:/Users/.../publish-demo/hello-bundle
Done in 206ms using pnpm v10.11.0
```

> **出处**：本人实测（2026-09-16，dsh `0.1.5-rc.1`）——profile 初始化 + bundle 链接成功

### 第 3 步：验证 profile manifest

```sh
cat ~/.dsh/profiles/demo/package.json
```

**实测结果**（2026-09-16）：

```json
{
  "name": "dsh-profile-demo",
  "private": true,
  "dependencies": {
    "dsh-hello-bundle": "link:/Users/.../publish-demo/hello-bundle"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "dsh-hello-bundle"
      ],
      "patchReload": "live"
    }
  }
}
```

**关键**：`bundles` 列表里 `dsh-hello-bundle` 被**自动追加**在 `dsh-base` 之后——印证概念③。

> **出处**：与官方给出的 profile manifest 结构一致（`docs/user/develop/basic/publish.zh.md`）

### 第 4 步：不启动，先验证层

```sh
dsh --profile demo --dump-config
```

**实测输出**（2026-09-16，节选）：

```
# == @deepseek-ai/dsh-base
...
# == dsh-hello-bundle
- id: hello-bundle
  name: dsh-hello-bundle
```

**`# == dsh-hello-bundle`** 这一层出现了——证明 bundle 的 patch 被正确应用。

> **出处**：官方——*"`dsh --profile demo --dump-config` # shows a `"# == dsh-hello-plugin"` layer"*；本人实测一致

### 第 5 步：启动 demo profile

```sh
dsh --profile demo --no-open --port 3099
```

**实测输出**（2026-09-16）：

```
[hello-bundle] bundle plugin loaded!
```

**看到这行 = 你的 bundle 通过 profile 加载成功了。**

> **出处**：本人实测（2026-09-16）——bundle 加载并打印日志

### 第 6 步：卸载（可选）

```sh
dsh plugin --profile demo remove dsh-hello-bundle
```

> **出处**：官方——*"`dsh plugin --profile demo remove dsh-hello-plugin` 会同时移除依赖和对应的层。"*

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **bundle** | 贡献一个 patch 层的 npm 包（`dsh.bundle`） | 一个 library 包 | 官方 publish.zh.md |
| **profile** | 描述可启动组合的目录（`dsh.profile`） | `main` 的依赖清单 | 官方 publish.zh.md |
| `dsh plugin add` | 转发给 pnpm，自动追加 bundle | `go get` | 官方 publish.zh.md |
| 包名引用 | bundle patch 用包名，非绝对路径 | 模块导入 | 官方 publish.zh.md |
| 加载顺序 4 层 | bundles → profile patch → home patch → `--patch` | Kustomize overlay | 官方 publish.zh.md |
| 整块替换 config | 后层替换目标行整个 config | 非深合并 | 官方 publish.zh.md |
| git 安装坎 | 拉源码非产物，需 `prepare` + 授权 | 需构建 | 官方 publish.zh.md |

## 踩坑记录

- **bundle 的 patch 用「包名」而非绝对路径**：这样 Node 正常解析，**不像 02/03 篇用 `--patch` 时需符号链接**。（出处：官方 publish.zh.md + 实测）
- **git 安装需构建授权**：pnpm ≥10 拒绝运行 git 依赖的 `prepare`，需在 `pnpm-workspace.yaml` 加 `allowBuilds`——**等于允许该包安装时在你机器上执行代码**，只对可信包授权。（出处：官方 publish.zh.md）
- **分发未构建的 TS 包会加载失败**：git 安装拉源码不跑 build → 无 `lib/`。要发布就 `pnpm publish`（预构建）或 `pnpm pack`（tarball）。（出处：官方 publish.zh.md）
- **patch 覆盖是整块替换**：后层覆盖时**必须重述该行所有键**，只写改动项会丢配置。（出处：官方 publish.zh.md）

## 下一步

- **framework 教程**：`service.zh.md`（对外提供服务）、`events.zh.md`（事件系统）
- **practice 教程**：`dynamic-cordis`（运行时挂载/卸载插件）、`llm-adapter`（LLM 适配器）
- **能力分层**：Service Definition / Provider / Consumer 三角色
