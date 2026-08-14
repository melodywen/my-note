---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 插件, 框架]
created: 2026-08-14
updated: 2026-08-14
---

# 02 Cordis 框架入门——五个核心概念

## Cordis 是什么

Cordis 是 dsh 底层的插件框架。你可以理解为：

> **dsh = Cordis（框架）+ 一堆插件（功能）**

Cordis 本身不提供任何业务功能，它只做一件事：**管理插件的加载、卸载和互相通信**。

官方文档说得很清楚：*"Every part of the product is a plugin, including the model adapter, the tool registry, the session log, and the agent loop itself."*

翻译：产品的每一部分都是插件——包括模型适配器、工具注册表、会话日志，甚至 Agent 循环本身。

## 五个核心概念

官方的 Cordis 入门文档（cordis-primer）讲了五个核心概念。我用大白话解释一遍。

### 1. 插件是一个对象

一个插件就是一小段代码，它实现了 `Service` 接口。最简单的形式就是一个函数：

```typescript
// 一个最简单的插件
function myPlugin(ctx) {
  // 在这里注册你的能力
  ctx.effect(() => {
    console.log("插件加载了")
    return () => console.log("插件卸载了")  // 清理函数
  })
}
```

插件也可以用类形式（当你需要给别人提供服务时）：

```typescript
class MyService extends Service {
  // 插件生命周期由 Cordis 管理
}
```

**关键点**：插件有生命周期——加载时做什么，卸载时做什么，都要明确。

### 2. 上下文是服务的容器

上下文（Context）就像一个**公共集市**。每个插件把自己的能力挂在集市的某个摊位上：

```
ctx（集市）
├── ctx.llm         ← "模型调用"摊位
├── ctx.tools       ← "工具注册表"摊位
├── ctx.sessions    ← "会话存储"摊位
├── ctx.fs          ← "文件系统"摊位
├── ctx.shell       ← "Shell 执行"摊位
├── ctx.sandbox     ← "沙箱"摊位
└── ...（40+ 个摊位）
```

一个插件要用自己的能力时不直接找另一个插件，而是去摊位上找。这样换掉一个实现不需要改调用方。

**举个真实例子**：
- `ctx.fs` 这个摊位挂着"文件系统"能力
- `dsh-fs-local`（本地文件系统）和 `dsh-fs-sandbox`（沙箱文件系统）都能挂上去
- `dsh-tool-fs`（文件读写工具）去 `ctx.fs` 找文件系统用，不关心具体是哪个实现

### 3. 通过 inject 声明依赖

如果一个插件 A 需要 B 才能工作，不需要手动管加载顺序，只要声明：

```typescript
const pluginA = {
  inject: ['tools'],  // "我需要 ctx.tools 才能启动"
  apply(ctx) {
    // 到这里时 ctx.tools 一定已经存在了
  }
}
```

Cordis 会自动等 B 就绪后再加载 A。不用操心启动顺序。

### 4. 类型化事件用于通信

插件之间不直接互相调用，而是通过**事件**来通信。Cordis 有四种事件分发模式：

| 模式 | 通俗解释 | 例子 |
|---|---|---|
| `emit`（广播） | 大喇叭喊一声，听到的各自反应 | "用户发了一条消息" → UI 更新、日志记录 |
| `waterfall`（瀑布） | 传接力棒，每人可以改一下再传下去 | "模型请求前" → 每个监听器可以修改请求内容 |
| `parallel`（并行） | 同时通知所有人，等全部完成 | "会话结束时" → 持久化、遥测、清理同时做 |
| `serial`（串行） | 一个接一个传，有返回值 | "轮次停止时" → 终止策略检查 |

**最常用的是 waterfall**。它像中间件——每个监听器收到请求，可以修改它，然后调 `next()` 传给下一个。也可以选择不调 `next()` 来**短路**（拒绝执行）。

> 官方原文：*"A listener can also choose to replace the result entirely and downstream listeners will only see the result after replacement."*
> 翻译：监听器也可以完全替换结果，下游监听器只能看到替换后的结果。

### 5. 注册是可逆的

这是 Cordis 最独特的特性。当你通过 `ctx.on()` 注册一个事件监听器、通过 `ctx.effect()` 安装一个资源时，**插件卸载时这些注册会自动撤销**。

```typescript
function myPlugin(ctx) {
  ctx.effect(() => {
    const timer = setInterval(() => console.log("tick"), 1000)
    return () => clearInterval(timer)  // 卸载时自动清理
  })
  
  ctx.on('some-event', () => {
    // 这个监听器也会在卸载时自动移除
  })
}
```

这意味着插件可以**热插拔**——加载时不留痕迹，卸载时干净利落。这是 dsh "一切皆插件"的基石。

> 官方原文：*"There is no privileged core to patch: you extend dsh by mounting a plugin beside the others, and registrations are effects that unwind when their plugin unloads."*
> 翻译：没有需要打补丁的特权内核——你通过把插件挂载到其他插件旁边来扩展 dsh，而各项注册都是副作用，会在插件卸载时自动撤销。

## 一个完整的例子：插件怎么协作

假设模型要读一个文件，整个流程是这样的：

```
模型说"读一下 src/main.ts"
    ↓
agent-loop 收到请求
    ↓
去 ctx.tools 摊位找到"文件读取"工具
    ↓
工具去 ctx.fs 摊位找到文件系统实现
    ↓
ctx.fs 可能是 fs-local（直接读本地文件）
也可能是 fs-sandbox（通过沙箱读）
    ↓
读完后触发 tool/result 事件
    ↓
ctx.sessions 把结果记入会话日志
```

每一环都是插件，每一环都可以替换。换掉 `ctx.fs` 的实现，整个文件操作就从"读本地"变成"读远程沙箱"，而调用方完全不用改。

## 小结

| 概念 | 一句话 | 通俗比喻 |
|---|---|---|
| **插件是对象** | 一小段有生命周期的代码 | 集市上的一个摊主 |
| **上下文是容器** | 所有服务挂载的公共空间 | 集市本身 |
| **inject 声明依赖** | 告诉框架"我需要谁" | "我要等张三来了才开张" |
| **事件通信** | 插件之间通过事件交互 | 大喇叭喊话 / 传接力棒 |
| **注册可逆** | 卸载时自动清理 | 摆摊不留垃圾 |

## 官方文档参考

本文基于官方以下文档整理：
- [cordis-primer.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-primer.md) / [中文版](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-primer.zh.md)
- [architecture.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md) / [中文版](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.zh.md)

## 下一篇

- [[03 Agent 的一次完整对话是怎么跑的|03 Agent 的一次完整对话是怎么跑的]]——Turn、Step 和工具执行流水线
