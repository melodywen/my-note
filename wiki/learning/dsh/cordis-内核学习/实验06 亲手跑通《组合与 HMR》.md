---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 内核, 阶段一, 动手实验, 有出处]
created: 2026-09-16
updated: 2026-09-16
---

# 实验06 亲手跑通《组合与 HMR》——看见"改代码自动热重载 + 诊断 PENDING"

> [!info] 版本锚点
> - 对应官方：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；`@deepseek-ai/cordis@4.0.2`
> - 本次实测新增依赖：`cordis-plugin-hmr@1.0.17`、`cordis-plugin-logger-console@1.0.2`、`cordis-plugin-timer@1.1.4`
> - 前置：读完《01》《附》《附2》《实验02–05》
> - **本文是动手文档**：你照着**贴代码、跑命令**，我负责讲清楚每个现象为什么发生

## 这个实验要验证什么

一句话：**验证"把 `cordis.yml` 当成一个可编辑的应用"——改配置/改代码能热更新，且能诊断'卡住不加载'的插件。**

前五讲都是"跑一次、看输出"。06 讲第一次把组合**当成活的**：

1. **配置项元数据**：`id`、`disabled`——让 loader 能"改"而不是"删了重建"。
2. **HMR**：保存 `.ts` 文件 → 插件自动卸载旧实例 + 加载新代码。
3. **诊断 PENDING**：插件一直没输出？主动查它的 fiber 状态。

官方原话：

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"到目前为止构建的每项能力都是插件，`cordis.yml` 则选择应用的插件树。本章会改变这种组合、热重载一个插件，并诊断始终无法加载的插件。"*

用你的 Go 经验类比：像 **fswatch + 自动重启**（如 air/reflex），但 Cordis 的 HMR 是**精确到插件**的热替换（只重载改动的那个插件，不是重启整个进程）。

---

## 先讲理论（动手前必读）

### 概念① 配置项不只有 `name`：`id` 与 `disabled`

```yaml
- id: greeter          # 稳定标识
  name: './greeter.ts'
- id: consumer
  name: './consumer.ts'
  disabled: true       # 保留条目，但跳过挂载
```

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"`id` 为 Cordis 配置项提供稳定标识，使 loader 能区分修改现有 Cordis 配置项与先删除再添加。`disabled: true` 会卸载插件而不删除其 Cordis 配置项；改回原值后，插件以及所有因依赖其服务而处于 PENDING 的插件都会再次加载。"*

**为什么 `id` 重要**（官方第 59 行展开）：

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"不带该字段的 Cordis 配置项在每次读取时都会获得一个新生成的 id，所以只要配置文件发生任何编辑，即使自身文本未变，它也会被视为先删除再添加并重新挂载。"*

Go 类比：`id` 像**给每个配置项分配的主键**——有主键才能做 diff（upDate vs delete+insert）；没主键，loader 每次都得"全删重加"，热更新的粒度就废了。

### 概念② 组与 `isolate`（了解即可）

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"组可以嵌套一份 Cordis 配置项子列表，并将其作为一个单元加载和卸载；`isolate` 则为一个组提供某项服务名称的独立实例，因此两个组可以各自看到配置不同的 `shell` 提供方，互不影响。"*

**Go 类比**：组 ≈ 子模块/命名空间；`isolate` ≈ **同一个 interface 在同一进程里的多份独立实现**（像多租户各用各的配置）。细节官方指向 cordis-primer，本文不深入。

### 概念③ HMR：先卸载、再加载

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"卸载会释放 effect（第 2 章），加载则遵循依赖关系（第 3 章），因此 HMR 可以先卸载、再加载，以替换正在运行的插件。`@deepseek-ai/cordis-plugin-hmr` 插件会监视文件，并在保存时执行这一过程。"*

**关键洞察**：HMR **不是新机制**，而是 02（卸载释放 effect）+ 03（加载遵循依赖）的**自然组合**。这再次印证：Cordis 的"注册可逆 + 依赖驱动"是所有高级能力的地基。

### 概念④ 诊断 PENDING：主动查 fiber 状态

依赖驱动加载有另一面：`inject` 的服务没人提供 → 插件**永远 PENDING、不输出、不报错**。

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"如果插件的 `inject` 指定了无人提供的服务，它就会一直等待，不输出任何内容。这不是错误，因为 PENDING 是合法状态，提供方可能稍后才挂载。"*

诊断方法是遍历 `ctx.registry` 找 PENDING 的 fiber：

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"每个上下文都能枚举插件注册表……"*

Go 类比：像加个**健康检查端点**，把所有 goroutine/服务状态暴露出来，排查"为什么这个组件没起来"。

---

## 第 1 步：准备课时目录（本讲多三个依赖）

```sh
cd ~/ai-work/dsh/test_workspace/cordis-tutorial
mkdir -p lesson-06-composition && cd lesson-06-composition
cp ../lesson-02-lifecycle/{bin.js,package.json,package-lock.json} .
npm install @deepseek-ai/cordis-plugin-hmr@1.0.17 \
            @deepseek-ai/cordis-plugin-logger-console@1.0.2 \
            @deepseek-ai/cordis-plugin-timer@1.1.4
```

> **出处**：三个包名见官方 06 讲 `cordis.yml` 示例（`docs/cordis-tutorial/06-composition-and-hmr.zh.md:30-35`）；版本为 npm 实测可用版本（2026-09-16）

---

## 第 2 步：场景① `disabled` —— 保留条目但不挂载

写 `needs-timer.ts`（一个依赖 `timer` 服务、但会打印自己名字的插件）：

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'needs-timer'
export const inject = ['timer']

export function apply(ctx: Context) {
  console.log('needs-timer loaded')
}
```

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`（代码逐字一致）

`cordis.yml`：

```yaml
- id: stats
  name: './needs-timer.ts'
  disabled: true
- id: probe
  name: './diagnose.ts'
```

跑：

```sh
npm start
```

**输出：空**（无 `needs-timer loaded`）——`disabled: true` 让它**压根没挂载**。

> **出处**：实测（2026-09-16）

---

## 第 3 步：场景③ 诊断 PENDING —— 本讲最实用的一节

写 `diagnose.ts`（遍历注册表，找出 PENDING 的 fiber）：

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'diagnose'

const PENDING = 0   // 见下方「版本差异」说明

export function apply(ctx: Context) {
  setTimeout(() => {
    for (const runtime of ctx.registry.values()) {
      for (const fiber of runtime.fibers) {
        if (fiber.state === PENDING) {
          console.log(`${fiber.name} is PENDING — a required service is missing (state=${fiber.state})`)
        }
      }
    }
  }, 500)
}
```

> [!warning] ⚠️ 版本差异：npm 版不导出 `FiberState`
> 官方文档写 `import { FiberState, type Context } from '@deepseek-ai/cordis'`，但**实测 npm 版 `cordis@4.0.2` 不导出 `FiberState`**，直接 import 会得到：
> ```
> SyntaxError: The requested module '@deepseek-ai/cordis' does not provide an export named 'FiberState'
> ```
> **根因**：master 源码里 `FiberState` 是 `export const enum`（`vendor/cordis/src/fiber.ts:147`）——`const enum` 编译后被内联，**不产生运行时导出**。npm 版实际只导出 `Fiber` 与 `RegistryService`（实测 `Object.keys`）。
> **解法**：`fiber.state` 运行时是数字，用其数字值比较即可。枚举值：`PENDING=0, LOADING=1, ACTIVE=2, FAILED=3, DISPOSED=4, UNLOADING=5`（出处：`vendor/cordis/src/fiber.ts:147-155`）。
> **出处**：本人实测（`cordis@4.0.2`，2026-09-16）

### 场景③a：依赖缺失 → 打印 PENDING

```yaml
- name: './needs-timer.ts'
- name: './diagnose.ts'
```

```sh
npm start
```

输出：

```
needs-timer is PENDING — a required service is missing (state=0)
```

> **出处**：实测（2026-09-16）——`state=0` 实测确认是 PENDING

**注意**：`needs-timer.ts` 的 `apply` **从未运行**（没打印 `loaded`），因为它被 PENDING 卡住。

### 场景③b：补上提供方 → 加载

```yaml
- name: '@deepseek-ai/cordis-plugin-timer'
- name: './needs-timer.ts'
- name: './diagnose.ts'
```

```sh
npm start
```

输出：

```
needs-timer loaded
```

（PENDING 消失——`timer` 服务就绪后，`needs-timer` 的 fiber 从 PENDING 变 ACTIVE，`apply` 终于执行。）

> **出处**：实测（2026-09-16）；官方对应说明见 `docs/cordis-tutorial/06-composition-and-hmr.zh.md:109`

### 场景③c：深挖——"为什么会是 PENDING"（源码级）

上面看到了现象，但**"为什么 `needs-timer` 会是 PENDING"**值得挖到底。它不是猜的，是 fiber 状态机的必然结果。

#### ① fiber 出生时默认就是 PENDING

> **出处**：`vendor/cordis/src/fiber.ts:194`——`public state = FiberState.PENDING`

每个插件 fiber 创建瞬间，状态**初始化为 `PENDING`**。源码注释（`fiber.ts:141-143`）解释：PENDING = *"waiting for required services"*（等待所需服务）。

#### ② `needs-timer` 声明了 `inject = ['timer']`，但无人提供 `timer`

此时 `cordis.yml` 里没有 `@deepseek-ai/cordis-plugin-timer` → `timer` 服务不存在。

#### ③ 依赖检查失败 → epoch 停在 INACTIVE → `_getState()` 返回 PENDING

加载时 fiber 逐个检查 `inject` 的服务（`fiber.ts:316` 调 `_checkImpl`），再由 `_refresh` 汇总：

> **出处**：`vendor/cordis/src/fiber.ts:611-621`——
> ```ts
> _refresh() {
>   let epoch = ''
>   for (const name of Object.keys(this.inject)) {
>     const impl = this._store[name]
>     if (!impl) {            // ← timer 找不到
>       epoch = INACTIVE      // ← 标记"不活跃"
>       break
>     }
>     epoch += ':' + impl.fiber.uid
>   }
>   this._setEpoch(epoch)
> }
> ```

epoch 变 `INACTIVE` 后，状态判定落到 `_getState`：

> **出处**：`vendor/cordis/src/fiber.ts:575-580`——
> ```ts
> private _getState() {
>   if (this.uid === null) return FiberState.DISPOSED
>   if (this._error) return FiberState.FAILED
>   if (this._runner.epoch !== INACTIVE) return FiberState.ACTIVE   // 只有"活跃"才 ACTIVE
>   return FiberState.PENDING                                        // ← 其余都是 PENDING
> }
> ```

**结论**：依赖没齐 → epoch 停在 INACTIVE → `_getState()` 返回 `PENDING`（枚举值 **0**）。**`apply` 从不执行**，所以 `needs-timer loaded` 永远不打印。

#### ④ `diagnose` 凭什么"看出来"——直接读 `.state`

`diagnose` 不猜测，它**直接读每个 fiber 的 `.state` 字段**（就是上面源码算出的值）：

```ts
for (const runtime of ctx.registry.values()) {   // 遍历所有插件
  for (const fiber of runtime.fibers) {          // 每个 fiber 实例
    if (fiber.state === PENDING) {               // PENDING === 0
      console.log(`${fiber.name} is PENDING — ... (state=${fiber.state})`)
    }
  }
}
```

- `ctx.registry` = 插件注册表（03 讲"两个 name"里提到的那个 registry）
- 它对 `timer`、`ctx.stats` 这些**一无所知**——只读状态，所以这招是**通用**的
- `setTimeout(..., 500)` 让它**等所有插件完成加载/判定**后再扫

#### ⑤ 完整因果链（一图记住）

```
needs-timer 声明 inject=['timer']
      │
      ▼
cordis.yml 没有 timer 提供方
      │
      ▼
fiber 检查依赖：timer 找不到 → epoch = INACTIVE    (fiber.ts:611-621)
      │
      ▼
_getState()：epoch 非活跃 → 返回 FiberState.PENDING (=0)    (fiber.ts:575-580)
      │
      ▼
needs-timer 的 apply 从不执行（所以没打印 "loaded"）
      │
      ▼
diagnose 遍历 ctx.registry → 读到 fiber.state === 0 → 打印那句
      │
      ▼
【补上 timer 提供方】→ epoch 变活跃 → state 转 ACTIVE → apply 执行、PENDING 打印消失
```

> **出处**：因果链综合 `vendor/cordis/src/fiber.ts:194`（默认 PENDING）、`:316`（`_checkImpl`）、`:611-621`（`_refresh`）、`:575-580`（`_getState`）+ 本人实测（2026-09-16）

> [!note] 为什么状态是数字 0 而不是 `FiberState.PENDING`
> `FiberState` 是 `const enum`（`fiber.ts:147`），**编译时被内联成数字**、npm 版不导出该符号。枚举顺序即数值：`PENDING=0, LOADING=1, ACTIVE=2, FAILED=3, DISPOSED=4, UNLOADING=5`。所以 `state=0` 就是 PENDING 的"数字真身"。

> [!tip] 官方补充：不加 PENDING 过滤会看到什么
> > **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"不加 PENDING 过滤条件进行迭代时，还会看到 loader 自身的插件（Loader、Include）处于 ACTIVE，因为配置文件本身也是通过插件挂载的。"*

---

## 第 4 步：场景② HMR —— 改代码自动热重载（本讲高潮）

### 4.1 写 `hello.ts` 与 `cordis.yml`

`hello.ts`：

```ts
import type { Context } from '@deepseek-ai/cordis'

export const name = 'hello'

export function apply(ctx: Context) {
  console.log('hello from my first plugin')
}
```

`cordis.yml`（HMR 三件套）：

```yaml
- id: logger
  name: '@deepseek-ai/cordis-plugin-logger-console'
- id: timer
  name: '@deepseek-ai/cordis-plugin-timer'
- id: hmr
  name: '@deepseek-ai/cordis-plugin-hmr'
  config:
    root: ['.']
- id: hello
  name: './hello.ts'
```

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`（代码逐字一致）

**为什么需要 logger-console 和 timer？** 官方解释：

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"HMR 通过 Cordis logger 服务记录日志，因此没有控制台导出器时看不到其消息；它还会 `inject` `timer` 服务来实现去抖，如果没有 `@deepseek-ai/cordis-plugin-timer`，它就会永远停在 PENDING，而且不发出任何提示。"*

即：**HMR 插件自己也 inject `timer`**——所以场景③的"依赖缺失静默 PENDING"陷阱，HMR 自己也可能踩。

### 4.2 ⚠️ 必须加 `--expose-internals`（实测踩到的坑）

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"HMR 通过 Loader 的原生辅助工具读取 Node 的 loader 内部结构。请在 tsx 下运行 Cordis：`node --import tsx ../../vendor/cordis/bin.js`"*

我用本工程的 `npm start`（= `node --import tsx bin.js`）直接跑，**报错**：

```
Error: --expose-internals is required for HMR service
```

**根因**：`package.json` 的 `start` 脚本**没带 `--expose-internals`**，而 HMR 要读 Node 内部 loader API。**解法**：给工程加一个 HMR 专用脚本（`package.json` 的 `scripts`）：

```json
"start": "node --import tsx bin.js",
"start:hmr": "node --expose-internals --import tsx bin.js"
```

跑 HMR 场景用：

```sh
npm run start:hmr
```

> **出处**：本人实测（2026-09-16）——不加 `--expose-internals` 报 `--expose-internals is required for HMR service`；`npm run start:hmr` 即正常

> [!note] 为何 `npm start` 跑 HMR 会报错、`npm run start:hmr` 才对
> `npm start` 固定执行 `start` 脚本（`node --import tsx bin.js`），**不含** `--expose-internals`；HMR 强制要求该 flag。所以：**非 HMR 场景用 `npm start`；HMR 场景必须用 `npm run start:hmr`**。

### 4.3 启动并热重载

```sh
npm run start:hmr
```

启动日志：

```
hello from my first plugin
2026-09-16 17:42:53 [I] hmr watching [ '.' ]
```

**现在编辑 `hello.ts`，把日志改成 `hello from my EDITED plugin`，保存**——等待约 1–3 秒：

```
hello from my first plugin
2026-09-16 17:42:53 [I] hmr watching [ '.' ]
2026-09-16 17:43:00 [I] hmr reload plugin at hello.ts
hello from my EDITED plugin
```

> **出处**：本人实测（2026-09-16）——与官方输出格式一致

**逐行看发生了什么**：

| 行 | 含义 |
|---|---|
| `hello from my first plugin` | 首次加载，旧代码执行 |
| `hmr watching [ '.' ]` | HMR 开始监视当前目录 |
| `hmr reload plugin at hello.ts` | 检测到 `hello.ts` 保存 → 重载 |
| `hello from my EDITED plugin` | 新代码加载，`apply` 再次运行 |

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"旧实例先卸载（其所有 effect 都会回卷），新代码随后加载，`apply` 再次运行。按 Ctrl-C 停止进程。"*

**编辑 `cordis.yml` 本身也会触发热更新**——loader 按 `id` 比较条目，只动变化的部分。

> **出处**：`docs/cordis-tutorial/06-composition-and-hmr.zh.md`——*"编辑 `cordis.yml` 本身也会触发更新：loader 按 `id` 比较 Cordis 配置项，只挂载、卸载或重新配置发生变化的部分。"*

---

## 一页纸总结

| 概念 | 一句话 | Go 类比 | 出处 |
|---|---|---|---|
| `id` | 配置项的稳定标识，支持 diff | 配置项主键 | 官方 06 讲 |
| `disabled` | 保留条目但跳过挂载，可逆 | 开关式禁用 | 官方 06 讲 + 实测 |
| 组 / `isolate` | 子列表作为单元；服务独立实例 | 子模块 / 多租户 | 官方 06 讲 |
| HMR | 监视文件，卸载旧+加载新 | fswatch + 热重启（但精确到插件） | 官方 06 讲 + 实测 |
| 诊断 PENDING | 遍历 `ctx.registry` 找卡住的 fiber | 健康检查端点 | 官方 06 讲 + 实测 |
| **PENDING 机制** | fiber 默认 PENDING；依赖不齐→epoch INACTIVE→状态保持 PENDING | 依赖就绪前不调用构造器 | `fiber.ts:194/611/575` |
| HMR 不是新机制 | = 02(卸载) + 03(依赖加载) 的组合 | 可逆注册 + 依赖驱动 | 官方 06 讲 |

## 踩坑记录

- **npm 版不导出 `FiberState`**：官方代码 `import { FiberState }` 在 npm `cordis@4.0.2` 上报 `does not provide an export named 'FiberState'`——因源码里它是 `const enum`（编译内联，无运行时导出）。改用数字值 `PENDING=0`。（出处：实测 + `vendor/cordis/src/fiber.ts:147`）
- **HMR 必须加 `--expose-internals`**：本工程 `npm start` 没带该 flag，跑 HMR 报 `Error: --expose-internals is required for HMR service`。已加 `start:hmr` 脚本，HMR 场景用 `npm run start:hmr`。（出处：实测）
- **HMR 插件自身依赖 `timer` 与 logger**：缺 `cordis-plugin-timer` 它永远 PENDING 且**无提示**；缺 console logger 看不到它的日志。（出处：官方 06 讲）
- **PENDING 不是"卡死"而是"准就绪"**：fiber 状态默认就是 PENDING（`fiber.ts:194`），依赖齐了自动转 ACTIVE——所以 `disabled`/卸载再恢复时，依赖它的插件会**自动重新加载**（官方 06 讲第 19 行）。（出处：源码 + 官方 06 讲）
- **配置项不加 `id` 会被反复重挂**：无 `id` 时每次读配置都生成新 id，任何编辑都导致"删了重建"，热更新粒度失效。（出处：官方 06 讲）
- **本讲多三个依赖**：`cordis-plugin-hmr` / `-logger-console` / `-timer` 需额外安装。（出处：实测）
