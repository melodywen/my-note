---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, 动手实战, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 03 插件配置——让插件接受用户在 yml 里传参

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/basic/config.zh.md`（插件配置）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 前置：完成 [01 第一个真插件](01%20第一个真插件——从最小工程走进真实%20dsh.md)、[02 开发一个工具](02%20开发一个工具——把能力暴露给模型.md)；回顾**实验05**《配置》
> - 与官方差异：在 `dsh-learn/example/plugins/` 走 `start.sh`（同 01/02 篇）

## 这个实验要验证什么

一句话：**验证"插件的参数不写死在代码里，而是从 `cordis.yml` 传入"——且配置错了插件拒绝启动。**

02 篇的 `greet` 工具**问候语写死**是 `'Hello'`。03 篇让它**可配置**——在 `cordis.patch.yml` 里改一个值，问候语就变，**不用改代码**。

官方原话：

> **出处**：`docs/user/develop/basic/config.zh.md`——*"让你的插件接受用户在 `cordis.yml` 中传入的配置。"*

用你的 Go 经验类比：**服务启动时从配置文件读参数**——但比 `yaml.Unmarshal` 更进一步：**非法配置直接加载失败（fail-fast）**。

> [!tip] 你其实已经学过这块
> **实验05《配置》** 讲的 `Config` 三合一（接口 + schema + 校验器）就是同一个东西。03 篇只是**把它用到真实 dsh 插件上**——模式完全一致。

---

## 先讲理论（动手前必读）

### 概念① `Config` 三合一：接口 + schema + 默认值

```ts
export interface Config {                 // ① TS 接口（编译期类型）
  greeting: string
}

export const Config: Schema<Config> = Schema.object({   // ② 运行时 schema
  greeting: Schema.string().default('Hello'),           // ③ 默认值直接写在这
})

export function apply(ctx: Context, config: Config) {   // ④ apply 第 2 参 = 已验证配置
  console.log(config.greeting)   // 用户值 或 schema 默认值
}
```

> **出处**：`docs/user/develop/basic/config.zh.md`——*"在插件中导出一个 `Config` 类型和同名的 Schemastery schema；默认值直接写在 schema 中。"*

**与实验05 逐点对应**：
- `interface Config` + `const Config` **同名共存**（TS 类型空间 + 值空间）——实验05 讲过的"数字魔法"
- `apply` 第二个参数 `config` 是**完整且已验证**的
- `Schema.string().default('Hello')` 提供默认值

### 概念② 配置从哪来：`insert` 里的 `config:` 块

```yaml
- insert:
    - id: greet-config
      name: '/绝对路径/greet-config.ts'
      config:                      # ← 配置块
        greeting: '你好'
```

> **出处**：`docs/user/develop/basic/config.zh.md`——*"插件加载时，Cordis 会通过导出的 schema 校验配置，并填充未提供字段的默认值。"*

### 概念③ ⚠️ `Config` 不能是普通对象

> **出处**：`docs/user/develop/basic/config.zh.md`——*"不要导出普通对象作为 `Config`，因为它不满足 Cordis 要求的 Standard Schema 接口。"*

必须用 **Schemastery**（或任意 Standard Schema 校验器）——这与实验05 的坑完全一致。

### 概念④ Schema 校验：配置错 → 加载失败

```ts
export const Config = Schema.object({
  apiKey: Schema.string().required(),     // ← 必填
  timeout: Schema.number().default(30000),
  mode: Schema.union(['fast', 'accurate']).default('fast'),
})
```

> **出处**：`docs/user/develop/basic/config.zh.md`——*"Schema 在插件加载时执行校验。如果配置不合法，插件会加载失败并给出明确错误信息。"*

### 概念⑤ 设计原则：**无硬编码可调参数**

> **出处**：`docs/user/develop/basic/config.zh.md`「无硬编码可调参数」节——*"Harness 的约定：**凡是不同部署可能需要采用不同值的参数，都必须定义为配置字段**。"*

检验标准（官方给的）：

> **出处**：同上——*"能否在 `cordis.yml` 中改变这个值，而不需要修改代码？"*

**Go 类比**：像**十二要素应用（12-factor）的"配置外置"原则**——凡随环境不同的值，都进配置。

### 概念⑥ 配置变更配合 HMR（回环实验06）

> **出处**：`docs/user/develop/basic/config.zh.md`——*"配置变更会触发插件热替换：修改 `cordis.yml` 中某个插件的 `config` 后，框架会卸载旧实例并加载新实例。由于注册都属于 effect 并会自动清理，替换后不会保留旧实例的注册。"*

**这就是实验06 的 HMR + 实验02 的 effect 组合**——改 config → 卸载旧 + 加载新。

---

## 动手：给 `greet` 加配置

> **规则（AGENTS.md）**：动手环节"你动手"。本文代码已写出并**已实测**。

### 第 1 步：建插件目录

```sh
cd ~/ai-work/dsh/dsh-learn
mkdir -p example/plugins/greet-config
```

### 第 2 步：写插件本体 `greet-config.ts`

创建 `example/plugins/greet-config/greet-config.ts`（在 02 篇基础上加 `Config` + 用 `config.greeting`）：

```ts
import type { Context } from '@deepseek-ai/cordis'
import Schema from '@deepseek-ai/schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'greet-config'
export const inject = ['tools']

export interface Config {
  greeting: string
}

export const Config: Schema<Config> = Schema.object({
  greeting: Schema.string().default('Hello'),
})

export function apply(ctx: Context, config: Config) {
  console.log(`[greet-config] loaded, greeting = "${config.greeting}"`)

  ctx.tools.register(defineTool({
    name: 'greet2',
    description: 'Greet someone using the configured greeting.',
    parameters: {
      name: { type: 'string', required: true, description: 'The name to greet' },
    },
    output: {
      schema: { type: 'string' },
      render: (_args, value) => [{ type: 'text', text: value }],
    },
    async execute(args) {
      return `${config.greeting}, ${args.name}!`
    },
  }))
}
```

> **出处**：结构综合官方 `develop/basic/config.zh.md`（`Config`/schema）+ `tool.zh.md`（`defineTool`）；`console.log` 一行是本实验**为验证配置生效**加的（官方示例无）

**注意**：这里 `execute` 里用了 `config.greeting`——**配置贯穿到工具执行**，不只是加载时打印。

### 第 3 步：写挂载层（**带 `config:` 块**）

创建 `example/plugins/greet-config/cordis.patch.yml`：

```yaml
- insert:
    - id: greet-config
      name: '/Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/greet-config/greet-config.ts'
      config:
        greeting: '你好'
```

> **出处**：`docs/user/develop/basic/config.zh.md`（`config:` 块结构）

### 第 4 步：解依赖（同 02 篇——符号链接）

```sh
GLOBAL_DSH=~/.nvm/versions/node/v24.14.0/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
cd ~/ai-work/dsh/dsh-learn/example/plugins/greet-config
mkdir -p node_modules/@deepseek-ai
for p in dsh-tools dsh-llm dsh-brand cordis schemastery cosmokit dsh-agent \
         dsh-scope dsh-session dsh-invariants dsh-code-runtime \
         dsh-system-prompt dsh-user-approval dsh-timeout; do
  [ -e "$GLOBAL_DSH/$p" ] && ln -sfn "$GLOBAL_DSH/$p" "node_modules/@deepseek-ai/$p"
done
```

> **出处**：同 02 篇（实测）——本插件 `import` 了 `dsh-tools` 与 `schemastery`，两者在全局 dsh 里都有

### 第 5 步：启动并验证配置生效

```sh
cd ~/ai-work/dsh/dsh-learn
./start.sh --patch /Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/greet-config/cordis.patch.yml
```

**实测输出**（2026-09-16）：

```
[greet-config] loaded, greeting = "你好"
dsh web: http://127.0.0.1:3080/?token=...
```

**`greeting = "你好"`** —— 配置生效了！插件读到了 yml 里的 `'你好'`（而非默认 `Hello`）。

> **出处**：本人实测（2026-09-16）——启动日志打印 `greeting = "你好"`

### 第 6 步：验证 schema 默认值（不配 config）

把 `cordis.patch.yml` 里的 `config:` 块**临时删掉**，重新启动：

```yaml
- insert:
    - id: greet-config
      name: '/Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/greet-config/greet-config.ts'
```

**实测输出**（2026-09-16）：

```
[greet-config] loaded, greeting = "Hello"
```

**`greeting = "Hello"`** —— schema 的 `.default('Hello')` 补上了缺失字段。

> **出处**：本人实测（2026-09-16）——删 config 后回退默认值 `Hello`

**两个场景对照**：

| `cordis.patch.yml` 里 | 实测输出 |
|---|---|
| `config: { greeting: '你好' }` | `greeting = "你好"` |
| 无 `config` | `greeting = "Hello"`（默认值） |

**这就完整验证了**：用户值优先；缺则用 schema 默认值——与实验05 的结论一致。

### 第 7 步：Web UI 里调用 `greet2` ✅ 已实测

启动后在 Web UI 输入：

```
Use the greet2 tool to greet Ada.
```

**实测结果**（2026-09-16）：

| 界面显示 | 内容 |
|---|---|
| 用户输入 | `Use the greet2 tool to greet Ada.` |
| 工具调用 | **1 次工具调用** → `工具调用 · greet2 · Ada` |
| 工具输入 | `{ "name": "Ada" }` |
| **工具输出** | **`你好, Ada!`** |
| 模型回复 | `搞定！👋 greet2 结果："你好, Ada!"` |

> **出处**：本人实测（2026-09-16，Web UI）——工具输出 `你好, Ada!`，**证明配置 `greeting: '你好'` 贯穿到了 `execute`**（不是默认的 `Hello`）

**这一步比 02 篇更进一步**：不只是加载时打印配置，**工具的运行时行为也由配置驱动**——同一个工具代码，改 yml 就能换问候语。

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| `Config` 三合一 | 接口 + schema + 默认值 | struct 类型 + 校验 | 官方 config.zh.md |
| `apply(ctx, config)` | 第 2 参是已验证配置 | 启动读配置 | 官方 config.zh.md |
| `config:` 块 | 在 yml 的插件条目里传参 | 配置文件段落 | 官方 config.zh.md |
| 默认值 | schema `.default()` 补缺 | 配置默认值 | 官方 config.zh.md + 实测 |
| 非普通对象 | 必须 Standard Schema | 要有校验器 | 官方 config.zh.md |
| 无硬编码 | 环境相关的值都进 config | 12-factor | 官方 config.zh.md |
| 配 HMR | 改 config → 卸载旧 + 加载新 | 热更新 | 官方 config.zh.md + 实验06 |

## 踩坑记录

- **`Config` 不能是普通对象**：必须 Schemastery / Standard Schema 校验器。（出处：官方 config.zh.md）
- **插件需额外链接 `schemastery`**：与 02 篇一样，`import` 的包要从全局 dsh 符号链接过来，`schemastery` 也在全局 dsh 里。（出处：实测）
- **端口 `EADDRINUSE: 3080`**：上次 dsh 未完全退出——`pkill -9 -f "@deepseek-ai/dsh"` 后再启动。（出处：实测）

## 下一步

- **04 打包与安装插件**：把插件以可安装包形式交付（对应官方 `basic/publish.zh.md`）
- **framework 教程**：`service.zh.md`（对外提供服务）、`events.zh.md`（事件）
