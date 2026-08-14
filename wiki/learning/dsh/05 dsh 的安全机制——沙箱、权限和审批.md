---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, 安全, 沙箱, 权限]
created: 2026-08-14
updated: 2026-08-14
---

# 05 dsh 的安全机制——沙箱、权限和审批

## 为什么需要安全机制

Agent 能读写文件、执行命令、搜索网页。这意味着它有能力做好事（帮你写代码），也有能力做坏事（删掉重要文件、执行恶意命令）。

dsh 用**三层防线**来管住 Agent：

```
第 1 层：沙箱（Sandbox）—— 限制能做什么
第 2 层：权限预设（Permission Preset）—— 限制做到什么程度
第 3 层：审批（Approval）—— 关键操作前问用户
```

## 第 1 层：沙箱（Sandbox）

沙箱限制了 Agent 能碰什么文件、能跑什么命令。

dsh 的沙箱通过 `ctx.sandbox` 这个服务实现。在执行任何命令前，Agent 要把命令交给沙箱，沙箱根据策略决定是否放行。

有三档沙箱模式：

| 模式 | 能做什么 | 不能做什么 |
|---|---|---|
| `read-only` | 读文件 | 写、删、执行命令 |
| `workspace-write` | 在工作目录内读写、执行命令 | 碰工作目录外的文件 |
| `danger-full-access` | 什么都行 | 无限制 |

**默认是 `workspace-write`**——Agent 可以在你的项目目录里随便折腾，但不能碰外面的文件。

> 官方原文（来自 architecture.md）：*"Filesystem and subprocess providers share one execution world, so pointing them at a remote sandbox moves Bash, PTY, and LSP with them."*
> 翻译：文件系统和进程提供方共享同一个执行世界，所以把它们指向远程沙箱，Bash、PTY 和 LSP 都跟着搬过去。

这意味着：换一个沙箱实现（比如从本地换到 E2B 云沙箱），所有需要执行命令的地方都会自动走远程沙箱，不用改代码。

## 第 2 层：权限预设（Permission Preset）

权限预设把沙箱模式和审批策略打包成用户能理解的选项：

| 预设 | 沙箱模式 | 审批策略 | 什么时候用 |
|---|---|---|---|
| `read-only` | read-only | 每次都问 | 只想让 Agent 看代码，不许改 |
| `workspace-write` | workspace-write | 每次都问 | **默认**，日常工作 |
| `danger-full-access` | danger-full-access | 从不问 | 你完全信任 Agent 时 |

通过环境变量 `DSH_PERMISSION_MODE` 控制，或者在 Web UI 设置里切换。

## 第 3 层：审批（Approval）

即使沙箱允许了，某些操作在执行前还会**弹窗问你**。

审批通过 `ctx.approval` 这个服务实现。它是一个**一次性决策**——每次需要审批的操作都单独问，不会"记住你的选择"。

```
Agent 要执行 npm install
    ↓
tools/pre-execute 检查到需要审批
    ↓
ctx.approval 发出询问
    ↓
Web UI 弹窗: "Agent 想执行: npm install，允许吗？"
    ↓
用户点"允许" → 继续执行
用户点"拒绝" → 工具被跳过
```

如果没人回答（比如 Headless 模式），默认**拒绝**（fail closed）。

> 官方文档说：*"absence fails closed to unavailable"*——没有回答方时以不可用关闭。

## 工具执行流水线中的安全检查

把三层防线放到工具执行流水线里看：

```
模型要调一个工具
    ↓
tools/pre-execute（前置检查）
  ├── 钩子检查
  ├── 权限检查 ← 第 2 层：权限预设
  └── 沙箱策略 ← 第 1 层：沙箱
    ↓ 如果需要确认
ctx.approval ← 第 3 层：审批
    ↓ 用户确认
单调守卫（Monotonic Guards）
  └── 身份保护、工具特定检查
    ↓ 全部通过
tools/execute（实际执行）
```

三层防线不是平行的，而是**串联**的——一层过了才到下一层。

## Seam（能力接缝）：为什么换一个实现就够了

dsh 的安全设计有一个重要概念叫 **Seam（接缝）**。

> 官方术语表原文：*"seam — a swappable capability with three roles: a Service Definition, one or more Service Providers, and one or more Consumers."*

翻译：Seam 是一种可替换能力，包含三个角色：
- **Service Definition**：定义接口（"我需要能执行命令的东西"）
- **Service Provider**：实现接口（"我就是一个能执行命令的本地 Bash"）
- **Consumer**：使用接口（"我是模型用的 Bash 工具，我需要执行命令"）

以 Shell 为例：

```
Service Definition:  ctx.shell（"我需要一个能执行 Shell 命令的东西"）
       ↓
Service Provider:    dsh-bash-local（本地 Bash）
                或   dsh-bash-sandbox（沙箱 Bash）
                或   dsh-pwsh-local（本地 PowerShell）
       ↓
Consumer:            dsh-tool-bash（模型调的 Bash 工具）
```

**换一个 Provider，Consumer 不用改**。比如从本地 Bash 换成远程 E2B 沙箱，模型用的工具不变，只是底层执行环境变了。

这就是为什么 dsh 说"换一个提供方就能改变整个产品"。

## 安全相关的关键服务

从官方的 [capability-seams.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/capability-seams.md) 文档中，和安全相关的服务有：

| 服务 | 作用 |
|---|---|
| `ctx.sandbox` | 进程沙箱——限制能执行什么 |
| `ctx.sandboxPolicy` | 沙箱策略——保存模式和工作区根目录 |
| `ctx.approval` | 审批——一次性权限决策 |
| `ctx.permissionPresets` | 权限预设——用户可切换的权限组合 |
| `ctx.fs` | 文件系统——读写文件（可被沙箱限制） |
| `ctx.shell` | Shell 执行——跑命令（可被沙箱限制） |
| `ctx.subprocess` | 子进程——启动进程（沙箱在这里拦截） |

## 第三方安全审计

有人已经对 dsh 做了完整的安全审计，结论是：

| 维度 | 评价 |
|---|---|
| **Agent 行为侧** | 生产级——工具执行管道、审批机制、沙箱、凭据模型都做得不错 |
| **插件代码侧** | **没有安全设计**——插件运行在宿主进程中，有 host 级权限，安装/更新/篡改路径没有签名验证 |

`!!js` 配置可以在加载时执行任意 JavaScript，等同于远程代码执行（RCE）。所以**不要安装不信任的插件**。

## 小结

| 防线 | 机制 | 控制什么 |
|---|---|---|
| 沙箱 | 限制文件和命令范围 | 能碰什么 |
| 权限预设 | 打包沙箱+审批策略 | 整体策略 |
| 审批 | 关键操作前问用户 | 逐次确认 |
| Seam | 可替换的安全实现 | 换实现不改调用方 |

## 官方文档参考

- [architecture.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md) 的 "Capability seams" 章节
- [capability-seams.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/capability-seams.md) / [中文版](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/capability-seams.zh.md)——完整的服务依赖图
- [glossary.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/glossary.md) / [中文版](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/glossary.zh.md)——seam 的定义
- [tool-execution-pipeline.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/tool-execution-pipeline.md)——工具执行流水线中的安全检查位置

## 下一篇

- [[06 dsh 能干什么——实际使用场景和社区生态|06 dsh 能干什么——实际使用场景和社区生态]]
