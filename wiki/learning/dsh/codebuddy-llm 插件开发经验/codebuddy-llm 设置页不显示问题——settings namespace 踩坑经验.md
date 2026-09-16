---
type: practice
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 插件, llm-adapter, settings, 踩坑复盘]
created: 2026-09-16
updated: 2026-09-16
---

# codebuddy-llm 设置页不显示问题——settings namespace 踩坑经验

> [!info] 版本锚点
> - dsh：**0.1.5-rc.1**（全局 npm 安装，编译产物）
> - 官方源码：master `0d1f50007f`（`~/ai-work/dsh/deepseek-harness/`，2026-09-16 fetch）
> - 插件：`dsh-learn/plugins/codebuddy-llm/`（commit `230901e`）
> - 耗时：约 2 小时（从「设置页看不到 CodeBuddy」到修复验收）

## 目的

插件写完、对话能聊、模型选择器里有全部 37 个模型——但打开 **设置 → 模型页，CodeBuddy 就是不显示**。会话内模型选择器正常，说明 provider 注册没问题，问题出在设置页自己的数据链路上。这篇笔记复盘完整的定位-修复-验证过程，重点是三个可迁移的经验：**设置页的 join 过滤机制**、**编译产物与 master 源码的分裂**、**外部插件引用宿主包的解析技巧**。

## 根因：设置页按 namespace join 过滤

设置页（`packages/client/ui-settings-models/src/client/store.ts:195-209`）的数据来自两个 RPC 的 join：

```
llm.providers       → provider 目录（含 codebuddy：settingsNs: 'codebuddy-llm'）
settings.describe   → 已注册的 namespace 视图（含 schema/value/base/user 层）
```

行卡片分类逻辑：

```ts
const namespace = namespaces.get(entry.settingsNs)     // ← join 键！
const configured = namespace !== undefined
  && (entry.settingsPath.length === 0 || schema.getPath(namespace.value, entry.settingsPath) !== undefined)
```

- `configured`（行卡片，像 DeepSeek 那样）——**namespace 必须已注册**且 settingsPath 可解析
- `addable`（只进「添加提供方」下拉）——`!configured && settingsNs !== ''`
- 其余静默不显示

我们的插件注册了 `registerConfigurableProviders`（settingsNs 非空），所以落在 **addable**——不是消失，是躲进下拉框里了。**行卡片 = 目录条目 + settings namespace 注册，缺一不可**。

> [!warning] 关键认知
> `registerConfigurableProviders` 只把 provider 送进目录，**不注册 settings namespace**。想让设置页认你，必须另行通过 settings 服务注册同名 namespace。这是两个独立注册，官方插件 llm-deepseek 两者都做了。

## 修复：三步走

### 1. 官方模式怎么写（master 源码）

`packages/llm/llm-deepseek/src/index.ts:147-154`：

```ts
ctx.inject(['settings'], (settingsCtx) => {
  settingsCtx.settings.installSection(ctx, NS, Config, config, {
    setSource: (source) => { current = source },
    onChange: ensureRegistrationFacts,
  })
})
```

### 2. 外部插件的两个坑

**坑一：import 解析不到**。`--patch` 按绝对路径加载插件文件，插件目录解析不到 `@deepseek-ai/*` 包（Node ESM 裸说明符从文件自身路径向上找 node_modules，我们的目录向上没有）。解法——**从 dsh CLI 入口反向定位宿主安装树**：

```ts
// dsh bin 是 symlink，realpath 后指向 <nvm>/lib/node_modules/@deepseek-ai/dsh/lib/bin.js
// createRequire(该路径) 就能解析到宿主自带的 schemastery
const req = createRequire(realpathSync(process.argv[1]))
const Schema = req('@deepseek-ai/schemastery')
```

两级候选（realpath 后 / 原样）+ 全链路失败降级为仅环境变量——配置面是增强不是前置条件，对话永远不受影响。

**坑二：installSection 是编译版 API，master 已改名**。详见下节。

### 3. 两层合成：env 为 base 层，UI 为 user 层

settings 的合成语义（`packages/settings/settings/src/index.ts` 的 `mergeLayers`）：

- `base`：注册时传入的基线（我们的环境变量值）
- `user`：用户在设置页/settings.yaml 写的覆盖层
- `resolved = schema(mergeLayers(base, user))`——**user 覆盖 base**，用户改完下一次请求生效

我们的 schema 三字段：`baseURL` / `domain`（X-Domain 回退值）/ `maxSystemPrompt`（清洗阈值）。

## 踩坑

### 踩坑 1：编译产物 ≠ master 源码（最贵的一课，约 30 分钟）

最初全程逆向 `~/.nvm/.../dsh/node_modules/`（编译产物）——`installSettingsSection` 函数、`ctx.settings.register()` 签名全套都挖出来了，方案都写完落盘了。直到 AGENTS.md 提醒「源码优先」，去 master 一查：

| | 编译产物（0.1.5-rc.1） | master（0d1f50007f） |
|---|---|---|
| 注册入口 | standalone `installSettingsSection(ctx, NS, Config, config, hooks)` 导出自 dsh-settings | `settingsCtx.settings.installSection(...)`——settings 服务方法 |
| 底座 | `register(ns, schema, options)` | 同名 `register`，一致 ✅ |

**教训**：Developer Preview 阶段两套 API 面貌并存。编译产物能告诉你「现在装的这版怎么跑」，只有 master 能告诉你「官方打算怎么演进」。最终选了**两版公共底座** `settings.register(ns, schema, { base })`——两版都在、语义一致，赌它最稳定。引用源码一律给 master 路径 + commit。

### 踩坑 2：编辑器缓冲区覆盖，AI 改动两次被静默回退（约 20 分钟）

过程：我的 Batch A/B/C 编辑全部落盘成功 → 冒烟测试却发现模块里根本没有新代码（37 个模型、inject 未调用、无降级 warn）→ grep 确认 `registerSettingsSection` 归零、`git status` 干净得像没动过。

真相：**用户编辑器里开着同一文件的旧缓冲区，保存即覆盖**（后来 13:56 的用户提交也证实了这点）。文件 mtime 变了、内容回 HEAD、我的编辑痕迹全无。

**教训**：
- 证据链：mtime 变化 + `git status` 意外 clean + 编辑成功返回 vs 文件内容缺失——三者矛盾时**先怀疑并发写入，别怀疑自己编辑失败**
- 解法：**别在共享文件上直接多轮编辑**。把文件复制到临时目录（`/tmp` 或系统临时区），在隔离区完成全部编辑 + 验证，最后一次性原子拷回（拷回前比对 md5 确认目标仍是预期基线）
- AI 协作铁律：写文件前先看 mtime，写完立刻验证内容还在；对「编辑成功但内容消失」保持零容忍

### 踩坑 3：NaN 让清洗阈值静默失效（bugbot 抓的）

`ENV` 层的 `maxSystemPrompt` 做了 `Number.isFinite + >=0` 校验，settings 层却原样透传。用户在设置页写入非法值 → `NaN > 0` 恒 false → 清洗静默关闭 → 上游拒绝超长 system 提示词。

**教训**：**同一配置项在多个来源入口必须有同一归一化函数**。`toMaxSystemPrompt()` 一处定义，ENV 层和 settings 层都过它，非法值显式回落默认。bugbot 的拦截是对的，这类「同类模式不同待遇」的不一致自己 review 时最容易漏。

### 踩坑 4：dsh-settings 的 register 签名里 schema 是「可调用对象」

不是 zod、不是 JSON Schema 对象——是 **schemastery**：`schema(data)` 返回解析值，`schema.toJSON()` 供 UI 渲染。dsh 生态全家桶（llm-deepseek 的 Config 也是）都用它。给宿主写 plugin 前先认准 `import z from '@deepseek-ai/schemastery'` 这个 import 形态，别拿 zod 往上套。

### 踩坑 5：编辑卡片「其余字段在 settings.yaml 中」是预期行为

修复后点开编辑卡片，发现三个字段**没有内联表单**，只有一句「其余字段在 settings.yaml 中，请直接编辑对应段 (codebuddy-llm)」。第一反应是渲染失败了，去查 master 的 `ProviderEditor.tsx` 才发现：

```ts
/** Per-adapter-family curated field sets (unknown namespaces get the hint alone). */
type EditorLayout = 'deepseek' | 'pi-ai' | 'unknown'
```

编辑器是**按适配器家族手写的**，unknown 家族就是只给提示。这是 UI 的设计约定——第三方 provider 的字段走 settings.yaml 直编，不做内联表单。

**教训**：判断「是不是 bug」前先读对应组件的设计注释。「看起来不对」的行为，一半是约定，另一半才轮到缺陷。想去掉这个提示需要给 `ui-settings-models` 提 PR（本地 fork 不值得，settings.yaml 直编已够用）。

## 方法论沉淀

1. **UI 不显示 ≠ 数据没注册**。先查数据链路（哪个 RPC、什么 join、哪层过滤），再查注册链路。这次 join 键就是 `settingsNs`，目录里有、namespace 没注册，恰好落进「既不显示也不报错」的静默档
2. **逆向编译产物定位「现在怎么跑」，读 master 源码决定「怎么写才对」**——两件事都要做，顺序别反
3. **外部插件引用宿主包**：`createRequire(realpathSync(argv[1]))` 定位宿主安装树，比硬编码路径或 NODE_PATH 都稳
4. **配置项多入口必须单点归一化**（见踩坑 3）
5. **共享文件并发编辑**：隔离区开发 + 原子落位 + md5 基线校验（见踩坑 2）
6. **验收要覆盖降级路径**：不只验「注册成功后设置页出现了」，也验「settings 服务缺席时对话还能不能跑」——配置面是增强，主链路不能被它绑架

## 结论

- 修复 = 注册 `codebuddy-llm` settings namespace（两版公共底座 `settings.register`）+ 配置两层合成（env base / UI user）+ 全链路降级
- 验收：mock 冒烟（注册/覆盖/回退三态）→ 真实服务器无 warn → Playwright 见到行卡片 → settings.yaml 手改复验 → bugbot 清零 → 提交 `554e4cd` + `230901e`
- 最值钱的收获是踩坑 1 和 2：**源码优先不是形式主义，是防止拿过期 API 写出「现在能跑但下版就废」的代码**；**并发写入的排查意识**则是 AI 协作时代的通用生存技能

## 相关

- 插件源码：`~/ai-work/dsh/dsh-learn/plugins/codebuddy-llm/codebuddy-llm.ts`
- 设置页 join：`packages/client/ui-settings-models/src/client/store.ts:195-209`（master `0d1f50007f`）
- 官方注册模式：`packages/llm/llm-deepseek/src/index.ts:147-154`
- mergeLayers：`packages/settings/settings/src/index.ts`
- 验收截图：`dsh-learn/.playwright-mcp/codebuddy-settings-models-page.png`
