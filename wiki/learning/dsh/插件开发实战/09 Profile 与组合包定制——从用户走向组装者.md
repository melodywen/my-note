---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, profile, bundle, patch, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 09 Profile 与组合包定制——从"用户"走向"组装者"

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 官方参考：`docs/architecture.zh.md`「Profile 与组合包」节；`packages/boot/app-boot/src/profile.ts`
> - 前置：完成 04 篇（打包发布——你已做过一个 `hello-bundle`）；回顾 01 篇（`--patch` 挂载层）
> - **本篇是阶段二的收官篇**——把前 8 篇的"单插件"能力，提升到"**组装整棵插件树**"的能力
> - 写法说明：本系列采用**完整重讲式**。官方**没有**独立教程页，本篇由本人从 `architecture.zh.md` + `app-boot/src/profile.ts` + 真实 `bundle/` + 你本机 `~/.dsh/profiles/` 组织，**每段标出处**

## 这一篇在讲什么

前面 8 篇，你始终是**"写插件的人"**：写一个插件，用 `--patch` 挂进别人的组装。

这一篇，你升级为**"组装者"**：**决定整棵插件树长什么样**——哪些 bundle、按什么顺序、你自己的 patch 覆盖什么。

**而且你已经无意中做过一次**：04 篇的 `publish-demo/hello-bundle` 被你挂进了 `~/.dsh/profiles/demo/`。本篇把那次经验**系统化**。

> **一句话**：前面是"造积木"，本篇是"用积木搭出你自己的作品"。

---

## 一、三层概念：profile / bundle / patch

### 权威定义

> **出处**：`docs/architecture.zh.md`「Profile 与组合包」节（逐字）
>
> - *"运行中的 `dsh` 是一棵插件树，由启动时按序叠加的各层组合而成。"*
> - *"**profile** 是存放在 Harness home 中的具名组装。它列出自己叠放的组合包，存放自己安装的树外插件，并保存用户自己的 `cordis.patch.yml`。"*
> - *"**组合包（bundle）** 是 Cordis 配置项及其挂载代码的分发格式，因此它插入的内容始终可被其上各层 patch。"*
> - *"两者都在各自的 `package.json` 中通过 `dsh` 字段声明自己：`dsh.profile` 列出一个 profile 的组合包，`dsh.bundle` 指向一个组合包的 patch 文件。"*

### Go 类比（先映射到你的认知）

| dsh 概念 | Go 类比 | 说明 |
|---|---|---|
| **bundle** | 一个**预置的配置切片**（比如一套 `fx`/`wire` 的 Option 组合包） | 别人打包好的"一大块组装" |
| **profile** | 你的 **`main()`** ——决定 `main` 里 **import 哪些包、按什么顺序初始化** | 组装者视角 |
| **patch** | 对某个已注册组件的**配置覆盖**（按 key 覆盖） | 改已装好的东西 |

**核心心智**：`dsh` 启动 = 拿一个**空列表**，按 profile 声明的顺序，**一层层叠加 patch**，最后一棵完整的插件树。

### 你已经有一个自定义 profile！

> **出处**：你本机 `~/.dsh/profiles/demo/package.json`（实读）

```json
{
  "name": "dsh-profile-demo",
  "private": true,
  "dependencies": {
    "dsh-hello-bundle": "link:/Users/melodycchen/ai-work/dsh/dsh-learn/plugins/publish-demo/hello-bundle"
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

**这就是"Profile 定制"的最小实例**——`demo` 这个 profile 叠了 `base` + **你自己 04 篇做的 `hello-bundle`**（通过 `link:` 本地链接）。

---

## 二、核心机制：五层叠加顺序

这是**整篇最关键**的部分，必须记准。

### 权威出处

> **出处**：`packages/boot/app-boot/src/profile.ts:7-13`（头注释，逐字）
> *"the tree is composed by applying each bundle's patch list in `dsh.profile.bundles` order over an empty entry list, **then the profile's own patches, then any launcher layers**（`--patch` files and flag-derived patches）"*

### 五层顺序（从底到顶）

```
        ┌─────────────────────────────────┐
  最后叠 │ ⑤ --patch overlay              │ ← 命令行叠加（start.sh 用的就是这层）
        ├─────────────────────────────────┤
        │ ④ home 级 cordis.patch.yml      │ ← ~/.dsh/cordis.patch.yml（全局用户层）
        ├─────────────────────────────────┤
        │ ③ profile 的 cordis.patch.yml   │ ← ~/.dsh/profiles/<name>/cordis.patch.yml
        ├─────────────────────────────────┤
        │ ② profile.dsh.bundles[1]        │ ← 如 dsh-web-app / dsh-headless
        ├─────────────────────────────────┤
  最先叠 │ ① profile.dsh.bundles[0]        │ ← 通常是 dsh-base（核心层）
        └─────────────────────────────────┘
              叠加在"空条目列表"之上
```

**"后叠的覆盖先叠的"**——同 id 的行，**后面的 patch 赢**。

> **出处**：`packages/bundle/base/cordis.patch.yml` 头注释（逐字）——*"Later bundle patches and the user's profile `cordis.patch.yml` address these rows by id, **with the last write winning per row**."*

### 组装代码（权威实现）

> **出处**：`packages/boot/app-boot/src/profile.ts` 的 `composeEntries()`

```ts
export function composeEntries(layers, warn = () => {}) {
  return applyEntryPatches([], structuredClone(layers.flat()), ...)
  //                     ↑ 从空列表开始，把所有层拍平后按序应用
}
```

**关键**：从 `[]`（空）开始，`layers.flat()` 把所有层**按顺序摊平**，交给 `applyEntryPatches` 逐个应用。

---

## 三、patch 的精确语法

理解了"五层叠加"，还得知道**一条 patch 到底能干什么**。

### `PatchOptions` 的三种操作

> **出处**：`vendor/include/src/index.ts:130`（类型）+ `:57-124`（`applyEntryPatches` 实现）

```ts
export interface PatchOptions {
  id?: string                 // 定位目标行（非 insert patch 必填）
  insert?: EntryOptions[]     // 插入新条目
  disabled?: boolean | null   // 禁用/启用某行
  name?: string               // 可选：校验目标行的 name
  // ...其余 key（如 config）= 覆盖目标行的对应字段
}
```

**三种操作**（`applyEntryPatches` 的实现逐条）：

| 形态 | 语义 | 实现 |
|---|---|---|
| `{ insert: [...] }`（**无 id**） | 往**根列表**追加条目 | `data.push(...insert)` |
| `{ id, insert: [...] }`（**有 id**） | 往**指定 group** 的 config **追加** | `target.config.push(...insert)` |
| `{ id, config: {...} }`（**非 insert**） | **覆盖**目标 id 的字段 | `for (const [k,v] of Object.entries(overrides)) target[k] = v` |

> **出处**：`vendor/include/src/index.ts:77-124`（`applyEntryPatches` 主体）

### ⚠️ 关键语义：**patch 是"按 key 替换"，不是"深合并"**

base bundle 头注释说 *"A patch replaces the targeted row's whole `config` rather than merging into it"*。**源码印证**：覆盖逻辑就是 `target[key] = value` —— **整个 key 的值被替换**（不是把两个 config 对象递归合并）。

> **出处**：`vendor/include/src/index.ts:120-123`——`for (const [key, value] of Object.entries(overrides)) { if (key === 'id') continue; target[key] = value }`

**这意味着**：你若想改某行的某一个子字段，**必须重述整行 config**，不能只写差异部分。

> **Go 类比**：像 `map[string]Value` 的赋值——`m["config"] = newConfig` 是**整体换掉**，不是 `newConfig` 逐字段 merge 进旧的。想改一个字段，得把整个 `newConfig` 写全。

### ⚠️ 两个"未命中"行为

> **出处**：`vendor/include/src/index.ts:109-117`

1. **patch 匹配不到 id** → **warn 并跳过**（不报错）：`warn('patch: entry %C not found', id)`
2. **patch 带了 `name` 但与目标行不符** → **warn 并跳过**：`warn('patch: name mismatch for %C ...')`

**为何设计成 warn 而非 error**：多平台/多版本的 patch 层可共用，允许某些行在当前平台不存在（如 win32 没有 POSIX 行）。

### 后一层能 patch 前一层插入的行

> **出处**：`vendor/include/src/index.ts:93-100`（注释，逐字）——*"Index what this patch added so a LATER patch in the same list can target it. ... a layer must be able to configure or disable a row an earlier layer inserted."*

**实现**：每次 `insert` 后，立即 `buildMap(insert)` 把新行索引进 `entryMap`，供后续 patch 定位。**所以叠加是"逐层生效"的**——你的 profile patch 能改任何下层（base/bundle）插入的行。

### patch 不可变（为了热重载）

> **出处**：`vendor/include/src/index.ts:46-48`（头注释）——*"The input is never mutated: patching shared entry objects would bake earlier patch values into the cached parse, so repeated application (config hot-reloads) could never revert a removed or changed patch."*

**意思**：patch 前 `structuredClone` 一份，**不改原始数据**——这样你**改/删一条 patch**，热重载能**真正回滚**（否则旧值会被"烤"进缓存，回不去）。

---

## 四、看不见的骨架：`base` bundle（505 行）

你天天启动的 web profile，**90% 的能力来自 `base` bundle 的一张大 patch**。

> **出处**：`packages/bundle/base/cordis.patch.yml`（**505 行**）头注释——*"The dsh-base bundle patch: the shared core of each base-backed profile, applied as ONE insert over the empty profile root."*

它一口气 `insert` 了 ~80 个核心插件行（部分节选）：

```yaml
- insert:
    - id: timer
      name: '@deepseek-ai/cordis-plugin-timer'
    - id: llm
      name: '@deepseek-ai/dsh-llm'
    - id: session
      name: '@deepseek-ai/dsh-session'
    - id: session-log-deepseek
      name: '@deepseek-ai/dsh-session-log-deepseek'
    - id: tools
      name: '@deepseek-ai/dsh-tools'
    # ...约 80 行
```

> **出处**：`packages/bundle/base/cordis.patch.yml:15-60`（节选）

**这解释了一个之前没答的问题**：为什么你 `./start.sh` 什么都没配，dsh 就有 bash 工具、有 LLM、有会话管理？——**全是 `base` 这 505 行 patch 组装出来的。**

### `headless` bundle 演示"增量覆盖"

> **出处**：`packages/bundle/headless/cordis.patch.yml:8-40`（节选）

```yaml
# 1) 定位 base 里的 system-prompt 行，覆盖它的 config
- id: system-prompt
  config:
    personaSuffix: Your working directory is {{cwd}}.
    personaPrefix: >-
      You are a coding agent powered by the {{model}} model.

# 2) 再插入 headless 独有的行
- insert:
    - id: headless-startup
      name: '@deepseek-ai/dsh-headless/startup'
    - id: headless-runner
      name: '@deepseek-ai/dsh-headless'
      inject: [headlessStartup]
      config:
        task: !!js ctx.headlessStartup.task
        sessionId: !!js ctx.headlessStartup.sessionId
```

**两个看点**：
1. **覆盖**：`id: system-prompt` 重述整个 config（**注意是重述，不是合并**——见第三节）
2. **`!!js` 表达式**：config 里能写 `!!js` 开头的 JS 表达式，运行时求值（如 `ctx.headlessStartup.task`）

> **出处**：`!!js` 用法见官方 `docs/architecture.zh.md` profile/cordis.patch.yml 注释——*"`!!js` expressions allowed"*

### 五个已交付模板

> **出处**：`packages/boot/app-boot/src/profile.ts:139`（`PROFILE_TEMPLATES`，逐字）

| 模板 | bundles | patchReload |
|---|---|---|
| `web` | `[dsh-base, dsh-web-app]` | `live` |
| `headless` | `[dsh-base, dsh-headless]` | `startup` |
| `sdk` | `[dsh-base, dsh-sdk-app]` | `startup` |
| `acp` | `[dsh-base, dsh-acp-app]` | `startup` |
| `sdk-minimal` | `[dsh-sdk-minimal]`（**不叠 base**，例外） | `startup` |

**`patchReload` 的含义**（`architecture.zh.md`）：*"自定义 profile 默认实时重载 patch。随附的 `web` profile 使用实时重载；`headless`、`sdk`、`sdk-minimal` 和 `acp` 则只在启动时应用一次所有配置层"*——因为一次性/stdio 应用**启动后替换其依赖会破坏生命周期**。

---

## 五、动手案例：从零建一个自定义 profile（已实测）

> **规则（AGENTS.md）**：动手环节"你动手"。本节代码**已实测通过**（2026-09-16）。

**目标**：建一个自定义 profile `my-agent`，**亲手验证五层叠加**。

### 第 1 步：从 web 模板新建

```sh
dsh --profile my-agent --from-default-profile web
```

> `--from-default-profile` 的语义（官方 `dsh --help`）：*"create rescue from the shipped web template, **then boot it**"*——**建 + 启动**。

**实测结果**：生成了 `~/.dsh/profiles/my-agent/`，`package.json` 里 bundles **正是 web 模板的**（确认"复制模板 bundles"）：

```json
// ~/.dsh/profiles/my-agent/package.json（实测）
{
  "name": "dsh-profile-my-agent",
  "private": true,
  "dependencies": {},
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"],
      "patchReload": "live"
    }
  }
}
```

### 第 2 步：观察未定制前的树

```sh
dsh --profile my-agent --dump-config
```

**实测**：树共 **152 个 id**。其中 `system-prompt` 行**已被 base+web-app 组装好**：

```yaml
- id: system-prompt
  name: '@deepseek-ai/dsh-system-prompt'
  config:
    personaSuffix: Your working directory is {{cwd}}.          # ← web-app 设的
    personaPrefix: You are a coding agent powered by the {{model}} model.
```

### 第 3 步：写自己的 patch（覆盖 + 插入）

编辑 `~/.dsh/profiles/my-agent/cordis.patch.yml`：

```yaml
# ① 覆盖：定位 base/web-app 里的 system-prompt 行
- id: system-prompt
  config:
    personaPrefix: >-
      你是 Melody 的专属助手（由 my-agent profile 定制）。

# ② 插入：往根列表追加一个新行（用 01 篇的 hello-plugin，只打日志、不注册服务）
- insert:
    - id: my-agent-marker
      name: '/Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/hello-plugin/hello-plugin.ts'
```

> [!warning] ⚠️ 插入的插件**不能与 base 已挂的插件冲突**
> 我最初用 `cordis-plugin-timer` 做插入示例，结果**真启动时崩溃**：
> ```
> service "timer" has been registered at <TimerService>
> at my-agent-marker (@deepseek-ai/cordis-plugin-timer)
> ```
> 因为 `base` bundle **已经挂过 `timer`**（`base/cordis.patch.yml:16`），我又插一个 → **同名服务重复注册**。
> **这是 08 篇讲过的机制本身**（一个 context 只能挂一个同名服务，`reflect.ts:290`）。
> **注意**：这个错误 **`--dump-config` 看不出来**（dump 只组装、不启动），**只在真启动 boot 时暴露**。**所以"dump 通过"≠"能启动"，必须真启动验证。**
> **出处**：本人实测踩坑（2026-09-16，`dsh 0.1.5-rc.1`）
>
> **改用 `hello-plugin` 后正常**（它只 `console.log`，零服务注册）。

### 第 4 步：dump 验证

```sh
dsh --profile my-agent --dump-config
```

**实测结果**：

```yaml
- id: system-prompt
  name: '@deepseek-ai/dsh-system-prompt'
  config:
    personaPrefix: 你是 Melody 的专属助手（由 my-agent profile 定制）。   # ← 我的 patch 生效
    # ⚠️ personaSuffix 不见了！

# ...（尾部）
- id: my-agent-marker                              # ← 插入生效
  name: '/Users/.../example/plugins/hello-plugin/hello-plugin.ts'
```

- 条目数 **152 → 153**（插入了一行）✅
- `system-prompt` 的 `personaPrefix` 被**覆盖** ✅

> [!warning] ⚠️ **实测坐实了「patch 替换非合并」**
> 我只写了 `personaPrefix`，但 **`personaSuffix` 消失了**——因为**整个 config 被替换**，不是 merge。
> 这正是第三节讲的关键语义：**想保留旧字段，必须重述整行 config**。
> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

### 第 5 步：验证五层顺序的"后叠赢"

再用 `--patch`（第⑤层）叠一层，看能否盖过 profile 自己的 patch（第③层）：

```sh
# /tmp/override-top.yml
# - id: system-prompt
#   config:
#     personaPrefix: 我是最上层 --patch，理应覆盖 profile patch。

dsh --profile my-agent --patch /tmp/override-top.yml --dump-config
```

**实测结果**——同一行的 `personaPrefix`，随层级**依次被覆盖**：

| 层级 | `personaPrefix` 的值（实测） |
|---|---|
| base + web-app | `You are a coding agent powered by the {{model}} model.` |
| + profile patch（③） | `你是 Melody 的专属助手（由 my-agent profile 定制）。` |
| + `--patch`（⑤） | `我是最上层 --patch，理应覆盖 profile patch。` |

**"后叠的赢"实测成立** ✅

### 第 6 步：真启动验证（树能 boot）

```sh
dsh --profile my-agent --no-open
```

**实测**：成功监听 `127.0.0.1:3080`，无报错——**组装出的树真能启动**（不只是 dump 能打印）✅

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

### 小结：本篇所有断言均实测通过

| 断言 | 实测 |
|---|---|
| `--from-default-profile` 复制模板 bundles | ✅ |
| profile patch 覆盖下层 bundle 的行 | ✅ |
| profile patch 能 insert 新行 | ✅ |
| **patch 替换非合并**（子字段消失） | ✅ 关键 |
| 五层顺序"后叠赢" | ✅ |
| 组装出的树能真实 boot | ✅ |

### 案例文件位置（仓库可复现）

本案例的 profile **定义文件已入库**，可一键复现：

```
dsh-learn/example/profile-demo/
├── README.md              # 案例说明
├── setup.sh               # install / verify / clean
└── my-agent/              # profile 定义文件（package.json + cordis.patch.yml + cordis.yml + pnpm-workspace.yaml）
```

```sh
cd example/profile-demo
./setup.sh          # 安装到 ~/.dsh/profiles/my-agent/ + dump 验证
./setup.sh clean    # 卸载
```

> **为什么要入库**：profile 是**用户环境产物**（`~/.dsh/profiles/`），天然不在版本控制里。本案例把它**明文入库 + 一键复现**，与 08 篇 `example/plugins/seam-demo/` 体例对齐。
> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

### 新建 profile 的三种方式

> **出处**：`packages/boot/app-boot/src/profile.ts:199`（`initProfile`）+ `:915-917`（报错信息）

| 方式 | 命令 | 底层 |
|---|---|---|
| **从模板** | `dsh --profile <name> --from-default-profile web` | 复制模板 bundles |
| **加插件**（新建） | `dsh plugin --profile <name> add <package>` | — |
| **底层函数** | `initProfile(dir, bundles, patchReload)` | 写 `package.json` + `cordis.patch.yml` + `pnpm-workspace.yaml` |

**无模板时的默认值**（`profile.ts:168,171`）：
- bundles 默认 `['@deepseek-ai/dsh-base']`（`DEFAULT_PROFILE_BUNDLES`）
- patchReload 默认 `'live'`（`DEFAULT_PROFILE_PATCH_RELOAD`）

> **出处**：`packages/boot/app-boot/src/profile.ts:168,171`

### 一个 profile 目录里的文件，各是干嘛的

新建的 profile 目录长这样（以 `my-agent` 为例）：

```
~/.dsh/profiles/my-agent/
├── package.json          # 声明 dsh.profile.bundles（叠哪些 bundle）+ patchReload
├── cordis.patch.yml      # ★ 你的 patch 层（改这个！）
├── cordis.yml            # 根条目列表（起点，保持空）
├── pnpm-workspace.yaml   # workspace 配置
└── node_modules/         # 运行时生成（依赖解析）
```

**重点分清 `cordis.yml` 和 `cordis.patch.yml`——它们不是"两个配置"，是"根 + patch 层"的关系**：

| 文件 | 角色 | 内容 | 你该动吗 |
|---|---|---|---|
| **`cordis.yml`** | **根条目列表**（组装起点 / boot 的叶子配置） | `[]`（空） | ❌ **别动**（保持空） |
| **`cordis.patch.yml`** | **你的 patch 层**（往根上叠） | 你的 patch 数组 | ✅ **改这个** |

> **出处**：`cordis.yml` 头注释（逐字）——*"dsh profile root — an empty entry list. The tree is composed as patches: each bundle in package.json's `dsh.profile.bundles`, then `cordis.patch.yml`, then any `--patch` overlays. **Edit `cordis.patch.yml`, not this file.**"*

**Go 类比**：`cordis.yml` ≈ 初始的空切片 `entries := []Entry{}`；`cordis.patch.yml` ≈ 你在这切片上追加/覆盖的那一层。boot 时，`include` 会加载 `cordis.yml` 作为根，再把各层 patch 应用上去。

> **出处**：源码 `packages/boot/app-boot/src/index.ts:530`（`mountRootInclude`）——把 `cordis.yml` 作为 `include` 的 `path`、把 `patches` 一并传入（`:559-561`）。

> [!warning] ⚠️ 一个易混淆点（实测发现）
> **`cordis.yml` 里的条目，boot 时会生效，但 `--dump-config` 不体现它**。
> **原因**（源码推断）：`boot` 走的是 `include`（根 = `cordis.yml` 内容 + patches），而 `--dump-config` 走 `composeEntries`（根 = **空列表** + 各 layer）——**两条路径的起点不同**。
> **实测**：往 `cordis.yml` 塞一个会打日志的插件 → 真启动打印了 `[hello-plugin] plugin loaded!`（**boot 读了**）；但 `--dump-config` 的条目数不变（**dump 不体现**）。
> ⚠️ 此条"dump 与 boot 起点不同"为**源码推断 + 单点实测**，未做完整对照实验。
> **出处**：本人实测 + 源码 `index.ts:530`（`mountRootInclude`）vs `profile.ts:933`（`composeEntries`），2026-09-16

---

## 六、`--dump-config`：观察组装结果

`architecture.zh.md` 明确给了这个工具：

> **出处**：`docs/architecture.zh.md`——*"要查看你的机器启动的配置树：`dsh --profile web --dump-config`。**它打印出的任何条目，都可以由你自己的 patch 替换。**"*

**它的价值**：把"五层叠加后的最终结果"**打印出来**——你就能看到"base 插了什么、你的 patch 改了什么、最终这一行长什么样"。

> **出处**：`vendor/include/src/index.ts:45`（头注释）——*"shared by mounting (`applyPatches`) and offline config tooling (`dsh --dump-config`) **so a dump can never drift from what boots**"*
>
> **关键保证**：`--dump-config` 和真实启动**走同一套 patch 逻辑**（`applyEntryPatches`）——**dump 出来的就是真正会挂载的**，不会漂移。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **profile** | 具名组装（bundles + 树外插件 + 用户 patch） | `main()` | `architecture.zh.md` |
| **bundle** | 配置项 + 挂载代码的分发格式 | 预置配置切片 | `architecture.zh.md` |
| **patch** | 按 id 定位行、按 key 覆盖 / 插入 | 配置覆盖 | `vendor/include/src/index.ts` |
| **五层顺序** | bundle[0]→bundle[1]→profile patch→home patch→`--patch` | init 顺序叠加 | `profile.ts:7-13` |
| **后叠赢** | 同 id 的行，后面的 patch 覆盖前面 | last-write-wins | `base/cordis.patch.yml` 头注 |
| patch 三操作 | 无 id insert / 有 id insert / 有 id 覆盖 | map 增/改 | `vendor/include/src/index.ts:77-124` |
| **patch 替换非合并** | 整个 key 的值被换掉，要重述整行 | `m["k"]=v` | `vendor/include/src/index.ts:120` |
| **未命中 warn 跳过** | id 不存在 / name 不符 → warn 不报错 | 宽容匹配 | `vendor/include/src/index.ts:109-117` |
| 后层可 patch 前层 | insert 后立即索引，供后续定位 | 逐层生效 | `vendor/include/src/index.ts:93-100` |
| **base bundle** | 505 行大 patch，插 ~80 个核心行 | 预置库 | `packages/bundle/base/cordis.patch.yml` |
| `--dump-config` | 打印组装结果，与真实启动同逻辑 | `print(config)` | `architecture.zh.md` |
| `patchReload` | live=热重载 / startup=启动一次 | 热更新开关 | `PROFILE_TEMPLATES:139` |

## 踩坑预防（写作阶段已知）

- **⚠️ patch 是"按 key 替换"不是"深合并"**：想改一个子字段，**必须重述整行 config**。（出处：`vendor/include/src/index.ts:120` + `base/cordis.patch.yml` 头注）
- **⚠️ 未命中的 patch 只 warn 不报错**：以为 patch "没生效"时，先查 `--dump-config` 是否有 warn（id 拼错 / name 不符）。（出处：`vendor/include/src/index.ts:109-117`）
- **⚠️ `sdk-minimal` 不叠 `base`**：它是唯一例外，别假设所有 profile 都以 base 打底。（出处：`PROFILE_TEMPLATES:139`）
- **⚠️ 自定义 profile 默认 `patchReload: live`**，但随附的 headless/sdk/acp 是 `startup`——热重载行为不同。（出处：`profile.ts:171`）

## 下一步

- **阶段二收官**：完成本篇后，阶段二的两条出口判据基本满足（会写插件 + 会组装）
- **后续**：Profile 已通 → 可进 **Agent Preset 编排**（人设/工具集/提示词），或进入**阶段三**（模型接入层 / 上下文与记忆）
