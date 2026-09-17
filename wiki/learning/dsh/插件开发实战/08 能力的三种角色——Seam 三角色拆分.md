---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段二, 插件开发, practice, seam, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 08 能力的三种角色——Seam 三角色拆分

> [!info] 版本锚点
> - 对应官方：`docs/user/develop/practice/index.zh.md`（能力的三种角色设计）
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）
> - 前置：完成阶段二 framework（05–07 篇）；**重点回顾 06 篇「服务与依赖」**（本篇是它的进阶）
> - **本篇起进入 `develop/practice` 教程**（阶段二主路径收尾）
> - 写法说明：本系列采用**完整重讲式**——每个概念都讲全，并标注**哪些在阶段一学过、哪些是真实 dsh 的新知**

## 这一篇在讲什么

06 篇你学会了写一个 **Service**（`ctx.xxx` 摊位上放一个能力）。但**真实的 dsh** 里，一个大能力（比如"执行 bash 命令"）**不是一个包扛下来的，而是拆成三个包**。

官方定位：

> **出处**：`docs/user/develop/practice/index.zh.md`——*"当一项能力足够通用，需要支持可替换的提供方时（例如 Bash 执行），harness 会区分三种角色：**Service Definition**、**Service Provider** 和 **Consumer**。角色需要独立演进或替换时，将它们放入不同包；否则一个包可以承担多个角色。完整能力构成其 seam。**任何单一角色都不是 seam。**"*

**本篇的核心**：理解 **Seam（能力接缝）** 的三角色设计，以及"为什么要拆、什么时候不该拆"。

> ⚠️ **前置提醒**：本篇是**架构设计**篇，不是新 API 篇。三角色用的 API（`Service` / `declare module` / `inject` / `ctx.plugin`）你全在 05/06 篇学过了。**新的东西是"怎么组织"**——把已有的积木按什么逻辑分装到三个盒子里。

---

## 一、先建立直觉：Seam 就是 Go 的「面向接口编程」

你是 Go 出身，这个概念**你早就用过**，只是没给它起名。

### Go 里的「面向接口编程」

```go
// ① 定义接口（只有方法签名，无实现）
type Reader interface {
    Read(p []byte) (n int, err error)
}

// ② 实现（可以有多个）
type FileReader struct { /* ... */ }
func (f *FileReader) Read(p []byte) (int, error) { /* 从文件读 */ }

type BufferReader struct { /* ... */ }
func (b *BufferReader) Read(p []byte) (int, error) { /* 从内存读 */ }

// ③ 调用方（只依赖接口，不依赖任何具体实现）
func Copy(dst Writer, src Reader) (int64, error) { /* 读 src 写 dst */ }
```

**关键性质**：`Copy` 的签名里**只出现 `Reader`**，它**不认识 `FileReader` 也不认识 `BufferReader`**。所以你**换实现不用改调用方**——这就是「可替换」。

### dsh 把这套认知落成「三个角色 + 三个包」

| Go 概念 | dsh 角色 | dsh 里的物理形态 |
|---|---|---|
| `interface Reader` | **Service Definition** | 一个包（如 `dsh-shell`） |
| `FileReader` / `BufferReader` | **Service Provider** | 一个/多个包（如 `dsh-bash-local`、`dsh-bash-sandbox`） |
| `func Copy(...Reader...)` | **Consumer** | 一个包（如 `dsh-tool-bash`） |

**"Seam"（接缝）这个词**，指的是**这三个角色合起来构成的那条可替换的接缝**——拔掉一个 Provider、换上一个新 Provider，接缝两边的 Definition 和 Consumer 纹丝不动。

> **出处**：`docs/user/develop/practice/index.zh.md`——*"完整能力构成其 seam。任何单一角色都不是 seam。"*

---

## 二、三角色各自的职责（以 bash 能力为例）

官方给的对照图：

> **出处**：`docs/user/develop/practice/index.zh.md`——"以 Bash 为例"节
> - **Service Definition** (`dsh-shell`)：定义 Cordis 服务以及 Bash 请求和结果类型
> - **Service Provider** (`dsh-bash-local`)：在本地计算机上执行命令
> - **Consumer** (`dsh-tool-bash`)：将该能力公开为模型可调用的工具

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────┐
│  dsh-shell   │────▶│  dsh-bash-local  │     │ dsh-tool-bash│
│(definition) │     │    (provider)     │     │(consumer/tool)│
└─────────────┘     └──────────────────┘     └──────────────┘
       ▲                                            │
       └────────────────────────────────────────────┘
                    inject: ['shell']
```

⚠️ **注意这张图的一个细节**：`dsh-shell` 有三条箭头指向它（Provider 依赖它、Consumer 依赖它），**但 Provider 和 Consumer 之间没有箭头**——**它们互不认识**。这是整篇最重要的一条线。

### 三方在源码里长什么样

#### ① Service Definition —— `dsh-shell`

> **出处**：源码 `packages/shell/shell/src/index.ts`

核心就是一个**抽象类**（+ 全部类型）：

```ts
// packages/shell/shell/src/index.ts

declare module '@deepseek-ai/cordis' {
  interface Context {
    shell: ShellExecutor          // ← 把 ctx.shell 挂进 Context 类型（同 06 篇）
  }
}

export abstract class ShellExecutor extends Service {   // index.ts:65
  constructor(ctx: Context) {
    super(ctx, 'shell')                                  // index.ts:67，注册服务名 'shell'
  }

  get sandboxMode(): SandboxMode | undefined {           // index.ts:75，默认实现（子类可覆写）
    return undefined
  }

  abstract resolve(request: ShellExecRequest): ShellExecSpec          // index.ts:85
  abstract run(spec: ShellExecSpec): Promise<ShellRunResult>          // index.ts:94
  abstract start(spec: ShellExecSpec): Promise<ShellProcess>          // index.ts:101
}
```

**三个 `abstract` 方法**——这就是"接口"部分：只有签名，没有实现。

> ⚠️ **一个重要修正**（此处纠正了一个常见误解）：
> **Definition 不等于"纯接口"**。dsh 的 Definition 除了抽象方法，还**拥有具体代码**：
> - `get sandboxMode()` 是**有实现体的默认方法**（`index.ts:75`，返回 `undefined`），子类可覆写
> - `packages/shell/shell/src/render.ts` 里的 `parseExitStatus()`（`render.ts:37`）是**实打实的逻辑代码**，且被 Consumer 复用（见下方 Consumer 的 `render.ts`）
>
> 所以更准的类比是：**Definition ≈ Go 的 `interface` + 一个可复用的公共基类/工具库**。dsh 的 Definition **比 Go interface 更重**——它还共享代码。
> **出处**：源码 `packages/shell/shell/src/index.ts:75` + `render.ts:37`（本人实读）

**Definition 拥有的类型**（`packages/shell/shell/src/types.ts`）：

| 类型 | 面向谁 | 含义 |
|---|---|---|
| `ShellExecRequest` | **调用方**（Consumer） | 调用方给的「原始请求」，字段多为可选（`workdir?`、`timeoutMs?`） |
| `ShellExecSpec` | **Provider** | `resolve()` 填完默认值/封顶后的「已解析规格」，字段必填 |
| `ShellRunResult` | **调用方** | 执行结果（`exitCode`、`stdout`、`stderr` 等） |

> **出处**：源码 `packages/shell/shell/src/types.ts`

**Request → resolve → Spec 的两步设计**，是官方明确要求的：

> **出处**：`docs/user/develop/practice/index.zh.md`「设计要点」——*"**显式优于隐式**：实现应通过显式的 `resolve(request): Spec` 步骤处理默认值，而不是在 `run()` 中隐藏 `?? default`。"*

> [!tip] 为什么这个两步设计重要
> `Request` 是「调用方视角」（我不填的字段请你填默认），`Spec` 是「执行方视角」（所有字段都已确定，可直接跑）。
> **默认值填充这一步被显式暴露成 `resolve()`，而不是藏在 `run()` 里**——这样调用方能提前知道"最终到底用什么参数跑"，测试/审计/覆写都有抓手。
> **Go 类比**：就像把 `func New(opts ...Option)` 的"选项应用"过程单独拆成 `Apply()` 方法暴露出来，而不是在构造函数里悄悄默认。

#### ② Service Provider —— `dsh-bash-local`

> **出处**：源码 `packages/shell/bash-local/src/index.ts`

```ts
// packages/shell/bash-local/src/index.ts

import { SHELL_SETTINGS_NAMESPACE, ShellExecutor } from '@deepseek-ai/dsh-shell'  // ← 只 import Definition
import type { ShellExecRequest, ShellExecSpec /* ... */ } from '@deepseek-ai/dsh-shell'

export class LocalBashExecutor extends ShellExecutor {       // index.ts:102，继承抽象类
  static inject = ['subprocess']                             // index.ts:103，自己还依赖下游 seam
  static Config: z<Config> = z.object({                      // index.ts:105，schemastery 配置
    cwd: z.string(),
    timeoutMs: z.number().default(120_000),
    maxTimeoutMs: z.number().default(600_000),
    // ...
  })

  resolve(req) { /* 填默认值 + 封顶，返回 Spec */ }          // 实现抽象方法
  run(spec)    { /* 真的去跑前台命令 */ }
  start(spec)  { /* 真的去起后台进程 */ }
}

export default LocalBashExecutor
```

**两个关键点**：

1. **Provider 只依赖 Definition**：`import { ShellExecutor } from '@deepseek-ai/dsh-shell'`——它**不认识 Consumer**。
2. **Provider 自己也可能依赖别的 seam**：`static inject = ['subprocess']`——它借 `ctx.subprocess` 去真正起进程。**Seam 是可以层层叠的**。

> **出处**：源码 `packages/shell/bash-local/src/index.ts:102-103`

**同域还有第二个 Provider**：`packages/shell/bash-sandbox/`（`@deepseek-ai/dsh-bash-sandbox`）——**沙箱版执行器**，跟 `bash-local` 提供**同一个 `ctx.shell` 服务**，只是执行方式不同（受沙箱限制）。

> **出处**：`packages/shell/README.zh.md`「包」表——`bash-local`「在 POSIX 上以全新 `bash -c` 进程运行 Bash 命令」；`bash-sandbox`「通过沙箱能力限制 Bash 命令运行」

**这就是「可替换」的物理体现**：同一个 seam，两个 Provider 包，任选一个挂载。

> ⚠️ **一个组合约束**（源码级证据）：
> **一个 context 里只能挂一个 Provider**。挂两个会**在加载时报错**：
> ```
> service "shell" has been registered at <...>
> ```
> **出处**：源码 `vendor/cordis/src/reflect.ts:290`——`throw new Error(\`service "${name}" has been registered at <${this.store[key].fiber.name}>\`)`（这是 Cordis **注册表**的机制，不是 `Service` 基类自己做的；本人实读）
>
> **Go 类比**：`init()` 里往同一个全局 map 注册两次同名 handler，第二次 panic。dsh 把它变成**加载期（而非运行期）**的显式报错——早失败，符合插件树的"加载失败回滚"（见 05 篇）。

#### ③ Consumer —— `dsh-tool-bash`

> **出处**：源码 `packages/shell/tool-bash/src/index.ts`

```ts
// packages/shell/tool-bash/src/index.ts

import { DSH_ENV_PREFIX } from '@deepseek-ai/dsh-shell'       // index.ts:24，只依赖 Definition
import type { ShellRunResult } from '@deepseek-ai/dsh-shell'  // index.ts:25

export const name = 'tool-bash'
export const inject = ['tools', 'shell', 'systemPrompt', 'shellEnv']  // index.ts:30 ← 声明依赖 shell 服务

export function apply(ctx: Context, config: Config = {}): void {
  const defaultMode = ctx.shell.sandboxMode                    // index.ts:191 ← 读 Provider 提供的能力

  ctx.tools.register(defineTool({                              // index.ts:241，注册模型工具
    name: 'bash',                                              // index.ts:242
    // ...
    execute: async (args) => {
      const result = await ctx.shell.run(ctx.shell.resolve({   // index.ts:375 ← resolve 再 run
        command: args.command,
        // ...
      }))
      // ...
    },
  }))
}
```

**三个关键点**：

1. **`inject = ['tools', 'shell', ...]`**——`shell` 出现在 inject 里。 **这就是 Consumer 依赖 Definition 的机制**：声明"我需要 `ctx.shell` 这个服务"，Cordis 保证它在 Consumer 加载前就绪（否则 Consumer 挂起等待，见 06 篇）。
2. **调用链是 `ctx.shell.resolve(...)` 再 `ctx.shell.run(...)`**（`index.ts:375`）——严格遵循「两步模式」。
3. **`ctx.tools.register(defineTool({ name: 'bash', ... }))`**——把能力**包装成模型可调用的工具**。这是 Consumer 的典型形态：**面向模型暴露能力**。

> **出处**：源码 `packages/shell/tool-bash/src/index.ts:24-30, 241-242, 375`

**⭐ 最关键的证据**：在整个 `tool-bash/src/` 目录（不只 `index.ts`，还有 `background.ts`、`render.ts`）里，**搜索不到任何 Provider 名**：

> **实测**（本人执行）：`grep -rn "bash-local\|bash-sandbox\|LocalBash\|BashSandbox" packages/shell/tool-bash/src/` → **无任何匹配**

Consumer **全文只认 `ctx.shell`**（一个抽象服务名），**从不知道自己背后挂的是 `bash-local` 还是 `bash-sandbox`**。这就是**「换 Provider 不用改 Consumer」的源码级证据**。

---

## 三、三角色的依赖关系（解耦铁律）

> **出处**：`docs/user/develop/practice/index.zh.md`——*"Provider 依赖 Service Definition。Consumer 依赖 Service Definition。**Provider 和 Consumer 互不依赖**。"*

```
        Definition
        ▲        ▲
   import│        │import + inject:['shell']
        │        │
   Provider      Consumer
        ╲        ╱
         ╳  互不依赖
        ╱        ╲
   (各自独立演进)
```

**严格的三条规则**：

1. **Provider → Definition**（单向依赖）
2. **Consumer → Definition**（单向依赖）
3. **Provider ⊥ Consumer**（互不依赖）

**为什么这条铁律如此重要**：它意味着**三方可以独立演进**——

> **出处**：`docs/user/develop/practice/index.zh.md`「拆分的好处」——*"调用方开始依赖 Service Definition 的约定后，Service Definition 很少改动。Service Provider 可以独立优化性能和安全性。Consumer 可以调整能力向模型呈现的方式。"*

**Go 类比**：这就是 **依赖倒置原则（DIP）** 的标准落地——高层模块（Consumer）和低层模块（Provider）**都依赖抽象**（Definition），**抽象不依赖细节，细节依赖抽象**。

---

## 四、设计纪律：什么时候**不该**拆

官方对这一条说得非常重（罕见地用了"不要"开头的警告）：

> **出处**：`docs/user/develop/practice/index.zh.md`「设计要点」——*"**不要预防性拆分**：只有角色需要独立演进时，才使用不同包。**简单的工具插件无需拆分**。"*

**翻译成人话**：

- 如果你写的工具**只有一个实现、不打算换**，**别拆三个包**——直接在**一个包里**承担多个角色即可。
- 官方原话：*"角色需要独立演进或替换时，将它们放入不同包；**否则一个包可以承担多个角色**。"*（`practice/index.zh.md` 开头）

> [!warning] 这是最容易犯的架构错误
> Go 里有个类似的坑：**为了"解耦"而无脑抽 interface，结果每个 struct 都配一个只有一个实现的 interface**——过度设计。
> dsh 这里同理。**Seam 是为"可替换性"付的税**：三个包 = 三份 `package.json` + 三套构建 + 三条依赖边。**只有当你真的需要换 Provider（或让三方独立发布）时，这笔税才值得交。**

**判据**（我据官方要点归纳，⚠️ 供参考）：
- ✅ 该拆：能力**通用** + 需要**可替换提供方**（如 bash 有 local/sandbox 两版）
- ❌ 别拆：一次性工具、实现唯一、不会独立演进

---

## 五、动手案例：搭一个三包 Seam + 双 Provider 验证「可替换」

> **规则（AGENTS.md）**：动手环节"你动手"。案例落在 `dsh-learn/example/plugins/seam-demo/`，**已实测通过**（2026-09-16）。

**目标**：亲手搭一个 mini-cap 三角色工程，并**用两个 Provider 验证「可替换」**。

> ⚠️ **命名说明**：官方教程的示例用 `my-cap`（Definition）/ `my-cap-local`（Provider）/ `tool-my-cap`（Consumer），包作用域名 `@deepseek-ai/dsh-my-cap`（出处：官方 `practice/index.zh.md`「教程：开发三种角色的能力」节的路径注释）。**我们的案例沿用 `myCap` 这个名字，但自定以下目录命名**（因为我们要做**两个** Provider 演示替换，官方只做了一个）。

案例落在 `dsh-learn/example/plugins/seam-demo/`：

```
seam-demo/
├── my-cap/my-cap.ts                ← ① Service Definition（抽象类 MyCapService + 类型）
├── my-cap-upper/my-cap-upper.ts    ← ② Provider A（转大写）
├── my-cap-reverse/my-cap-reverse.ts← ② Provider B（反转）
├── tool-my-cap/tool-my-cap.ts      ← ③ Consumer（包成模型工具 my_cap）
├── seam-upper.patch.yml            ← 挂 upper 的挂载层
└── seam-reverse.patch.yml          ← 挂 reverse 的挂载层（与 upper 只差 Provider 行）
```

### 三个角色的代码（实测通过）

**① Definition —— `my-cap/my-cap.ts`**

```ts
import { Service, type Context } from '@deepseek-ai/cordis'

declare module '@deepseek-ai/cordis' {
  interface Context { myCap: MyCapService }
}

export abstract class MyCapService extends Service {
  constructor(ctx: Context) { super(ctx, 'myCap') }
  abstract execute(request: MyCapRequest): Promise<MyCapResult>
}

export interface MyCapRequest { input: string }
export interface MyCapResult { output: string }

export default MyCapService
```

**② Provider A（大写）—— `my-cap-upper/my-cap-upper.ts`**

```ts
import type { Context } from '@deepseek-ai/cordis'
import { MyCapService, type MyCapRequest, type MyCapResult } from '../my-cap/my-cap.ts'

class MyCapUpper extends MyCapService {
  async execute(request: MyCapRequest): Promise<MyCapResult> {
    return { output: request.input.toUpperCase() }
  }
}

export const name = 'my-cap-upper'
export function apply(ctx: Context) { ctx.plugin(MyCapUpper) }
```

**② Provider B（反转）—— `my-cap-reverse/my-cap-reverse.ts`**：与 A 唯一区别是 `execute` 体：

```ts
return { output: request.input.split('').reverse().join('') }
```

**③ Consumer —— `tool-my-cap/tool-my-cap.ts`**

```ts
import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type {} from '../my-cap/my-cap.ts'   // 仅为类型

export const name = 'tool-my-cap'
export const inject = ['tools', 'myCap']    // ← 依赖抽象服务名

export function apply(ctx: Context) {
  ctx.tools.register(defineTool({
    name: 'my_cap',
    description: 'Execute my capability.',
    parameters: { input: { type: 'string', required: true } },
    output: { schema: { type: 'string' }, render: (_a, v) => [{ type: 'text', text: v }] },
    async execute(args) {
      const result = await ctx.myCap.execute({ input: args.input })  // ← 只认 ctx.myCap
      return result.output
    },
  }))
}
```

> ⚠️ **一个没绕开的坑**：每个插件目录必须有 `package.json` 且含 **`"type": "module"`**，否则 dsh 加载时报
> `Failed to load the ES module ... Make sure to set "type": "module" in the nearest package.json`
> 。（出处：本人实测 2026-09-16；这也是 01 篇"最小工程"的既有约定）

### 关键：两个挂载层只差 Provider 一行

`seam-upper.patch.yml` 与 `seam-reverse.patch.yml`，**唯一区别**：

```yaml
# seam-upper.patch.yml                          # seam-reverse.patch.yml
- insert:                                       - insert:
    - id: my-cap-upper                              - id: my-cap-reverse
      name: '.../my-cap-upper.ts'                     name: '.../my-cap-reverse.ts'
    - id: tool-my-cap          ← 完全相同            - id: tool-my-cap          ← 完全相同
      name: '.../tool-my-cap.ts'                      name: '.../tool-my-cap.ts'
```

### ✅ 实测证据 1：配置层（`--dump-config`）

用 `./start.sh` 起（AGENTS.md 规范：启动一律走 start.sh，它自动带上 codebuddy 层），把 `--dump-config` 透传出去，打印组装后的插件树：

```sh
cd ~/ai-work/dsh/dsh-learn

# 打印挂 upper 的插件树
./start.sh --patch /Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/seam-demo/seam-upper.patch.yml --dump-config > /tmp/tree-upper.yaml

# 打印挂 reverse 的插件树
./start.sh --patch /Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/seam-demo/seam-reverse.patch.yml --dump-config > /tmp/tree-reverse.yaml

# 对比两棵树
diff /tmp/tree-upper.yaml /tmp/tree-reverse.yaml
```

两棵树做 diff，**插件树部分只有 Provider 行不同**：

```
< - id: my-cap-upper                              ──┐ 只有 Provider 行不同
<   ...my-cap-upper.ts                             │
> - id: my-cap-reverse                             │
>   ...my-cap-reverse.ts                          ──┘
```

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）
> **注**：`--dump-config` 的输出里也会带上 `start.sh` 的 `→ 完整命令` 那行（故 diff 会多一条该行的差异），但**插件树节点的差异只有 Provider 一行**，结论不变。

### ✅ 实测证据 2：运行时（headless 真调工具）

用 `DSH_PROFILE=headless` 让 `./start.sh` 起 headless profile（非交互跑一句任务后退出），同一句指令（"调用 my_cap，input 传 'seam'"）分别跑两个 Provider：

```sh
cd ~/ai-work/dsh/dsh-learn

# upper Provider
DSH_PROFILE=headless ./start.sh --patch /Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/seam-demo/seam-upper.patch.yml "调用 my_cap，input 传 'seam'"
# → SEAM                         ← upper Provider 生效

# reverse Provider（Consumer 一字未改）
DSH_PROFILE=headless ./start.sh --patch /Users/melodycchen/ai-work/dsh/dsh-learn/example/plugins/seam-demo/seam-reverse.patch.yml "调用 my_cap，input 传 'seam'"
# → maes                         ← reverse Provider 生效
```

**Consumer（`tool-my-cap`）两次一字未改，Definition（`my-cap`）也一字未改——只换了 Provider 挂载行，行为就从 `SEAM` 变成 `maes`。**

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

> [!success] 本篇核心论点，已从「源码推断」升级为「实测铁证」
> 第二节说"换 Provider 不改 Consumer"是**源码级证据**（grep 证明 Consumer 全文不出现 Provider 名）；本节的 headless 实测把它变成了**运行时可验证的事实**。两条证据相互印证。


---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| **Seam** | 三角色合起来构成的可替换接缝 | 面向接口编程的一整套 | 官方 `practice/index.zh.md` |
| Service Definition | 抽象类 + 全部类型（+ 少量共享实现） | `interface`（+ 公共基类） | 源码 `shell/src/index.ts` |
| Service Provider | 继承抽象类、实现具体执行 | interface 的实现（可多个） | 源码 `bash-local/src/index.ts` |
| Consumer | 声明 `inject: ['shell']`、把能力包成工具 | 只依赖 interface 的调用方 | 源码 `tool-bash/src/index.ts` |
| 依赖方向 | Provider→Def；Consumer→Def；**Provider⊥Consumer** | 依赖倒置原则（DIP） | 官方 `practice/index.zh.md` |
| Request→Spec | 默认值用显式 `resolve()` 填，不藏在 `run()` 里 | 拆出独立的 `Apply()` | 官方「设计要点」 |
| 一个 context 一个 Provider | 挂两个 → 加载期报错 | map 重复注册 | 源码 `reflect.ts:290` |
| **不要预防性拆分** | 不可替换就别拆三个包 | 别为单实现抽 interface | 官方「设计要点」 |

## 踩坑预防（写作阶段已知）

- **⚠️ "Definition = 纯接口" 是误解**：dsh 的 Definition **含具体代码**（`get sandboxMode` 默认实现、`render.ts` 的 `parseExitStatus`），是"interface + 公共基类/工具库"。（出处：源码 `shell/src/index.ts:75` + `render.ts:37`）
- **⚠️ 不要为没有替换需求的工具拆三包**：官方明确警告"预防性拆分"。（出处：官方「设计要点」）
- **⚠️ 一个 context 只挂一个 Provider**：同时挂 `bash-local` 和 `bash-sandbox` 会加载期报错。（出处：源码 `reflect.ts:290`）

## 下一步

- **09 篇预告**：`practice/llm-adapter`（实现一个 LLM 提供方）——**又一条真实 seam**（这次是 `ctx.llm`），把本篇的三角色认知迁移到一个更复杂的域
- **可选深挖**：官方内置 seam 完整清单见 `docs/capability-seams.zh.md`（含 `ctx.llm`、`ctx.shell`、`ctx.credentials`、`ctx.settings` 等）
