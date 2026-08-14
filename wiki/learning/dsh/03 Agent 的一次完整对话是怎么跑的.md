---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, agent-lifecycle, turn, step]
created: 2026-08-14
updated: 2026-08-14
---

# 03 Agent 的一次完整对话是怎么跑的

## 三个层次：Round > Turn > Step

在理解一次对话怎么跑之前，先搞清楚 dsh 里的三个时间层次：

```
Round（轮）
  └── Turn（次）
        └── Step（步）
```

用大白话：

| 层次 | 是什么 | 例子 |
|---|---|---|
| **Step（步骤）** | 一次模型请求 + 这次请求触发的工具调用 | 模型说"帮我读一下 config.json"→工具读了→结果返回给模型 |
| **Turn（轮次）** | 用户发一条消息后，模型连续做的所有步骤 | 用户说"修一下 bug"→模型读文件→改代码→跑测试→跑通→回复用户 |
| **Round（回合）** | 外层策略驱动的一次迭代 | Ralph 循环中的一轮：派一个全新子 Agent 去试一次 |

**一个 Turn 包含多个 Step，一个 Round 包含一个 Turn。**

## 一次完整对话的流程

以下基于官方 [agent-lifecycle.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/agent-lifecycle.md) 的时序图整理。这是用户发一条消息后发生的事情：

### 第 1 步：用户发消息

```
用户在输入框打字 → "帮我看看这个项目的结构"
    ↓
消息进入 Agent 的 inbox（收件箱）
    ↓
Driver（驱动器）被唤醒
```

### 第 2 步：开启一个 Turn

```
Driver 发出 turn/start 事件
    ↓
从 inbox 里取出用户的消息
```

### 第 3 步：组装模型请求

```
Driver 调用 agent/pre-step 事件（waterfall）
    ↓
监听器可以：改写消息 / 拒绝消息 / 放行
    ↓
如果放行：
    ↓
从 ctx.systemPrompt 收集所有提示词片段
从 ctx.tools 收集所有工具的 schema
组装成完整的模型请求
```

### 第 4 步：调用模型

```
Driver 调用 ctx.llm 发送请求
    ↓
模型流式返回内容（assistant/chunk 事件一个个到达）
    ↓
如果模型没有调用工具 → 直接回复用户，Turn 结束
如果模型要调用工具 → 进入工具执行流程
```

### 第 5 步：工具执行（如果模型要调工具）

这是最复杂的部分。官方有一个完整的工具执行流水线图：

```
模型说"调用 bash 工具，命令是 npm test"
    ↓
记录 tool/call 事件（先记日志，还没执行）
    ↓
┌─ tools/pre-execute（前置检查）─────────────┐
│  钩子、权限检查、沙箱策略                       │
│  可以：允许 / 拒绝 / 要求用户确认                │
└──────────────────────────────────────┘
    ↓ 通过
┌─ 单调守卫（Monotonic Guards）──────────────┐
│  身份保护、工具特定检查                         │
└──────────────────────────────────────┘
    ↓ 通过
┌─ tools/execute（执行）────────────────────┐
│  超时控制、重试、指标收集                       │
│  实际执行工具的代码                              │
└──────────────────────────────────────┘
    ↓ 执行完
┌─ tools/post-execute（后置处理）────────────┐
│  可以：接受 / 阻止 / 替换结果 / 追加上下文         │
└──────────────────────────────────────┘
    ↓
┌─ finalizeContent（最终化）────────────────┐
│  工具自己的内容不变式检查                        │
└──────────────────────────────────────┘
    ↓
记录 tool/result 事件
    ↓
结果返回给模型
```

### 第 6 步：模型继续（可能有多个 Step）

```
模型收到工具结果后，可能：
  a) 还需要调更多工具 → 回到第 5 步（新的 Step）
  b) 任务完成了 → 回复用户
    ↓
如果没有更多工作 → 发出 agent/turn-stopping 事件
    ↓
Turn 结束，发出 turn/end 事件
    ↓
Agent 回到 idle 状态，等用户下一条消息
```

## 整个流程一图概览

```
用户发消息
    │
    ▼
turn/start ──────────────────────────────────────────┐
    │                                                │
    ▼                                                │
  agent/pre-step（waterfall）                        │
    │ 放行                                            │
    ▼                                                │
  step/start                                         │
    │                                                │
    ▼                                                │
  组装请求（提示词 + 工具 schema）                     │     一个
    │                                                │     Step
    ▼                                                │
  agent/request → ctx.llm ──→ 模型返回                │
    │                                                │
    ├─ 模型只回复文字 ──→ assistant/message            │
    │                       │                        │
    │                       ▼                        │
    │                  step/end                       │
    │                                                │
    └─ 模型要调工具 ──→ tool/call                     │
                          │                         │
                          ▼                         │
                     工具执行流水线                    │
                    （pre → execute → post）          │
                          │                         │
                          ▼                         │
                     tool/result                     │
                          │                         │
                          ▼                         │
                     模型继续 ──→ 可能更多 Step ──────┘
    │
    ▼
  agent/turn-stopping（serial）
    │
    ▼
turn/end
    │
    ▼
Agent idle，等用户下一条消息
```

## 一个真实的例子

用户说："帮我看看这个项目有没有测试失败的"

```
Turn 开始
  │
  ├─ Step 1: 模型收到消息
  │   → "我需要跑一下测试"
  │   → 调用 tool-bash, 命令: "npm test"
  │   → pre-execute: 权限检查通过
  │   → execute: 跑 npm test
  │   → post-execute: 接受结果
  │   → tool/result: "3 个测试失败"
  │
  ├─ Step 2: 模型看到测试失败了
  │   → "我需要看看失败的测试代码"
  │   → 调用 tool-fs, 读文件: "src/test/foo.test.ts"
  │   → 工具执行: 读取文件内容
  │   → tool/result: 文件内容
  │
  ├─ Step 3: 模型分析了代码
  │   → "我发现 bug 了，在第 42 行"
  │   → 调用 tool-fs, 编辑文件
  │   → 工具执行: 修改文件
  │   → tool/result: 修改成功
  │
  ├─ Step 4: 模型重新跑测试
  │   → 调用 tool-bash, 命令: "npm test"
  │   → tool/result: "全部通过"
  │
  └─ 模型回复: "我修好了，3 个测试现在全部通过。"
      → assistant/message
      → turn 结束

Turn 结束，Agent idle
```

4 个 Step 组成一个 Turn，每个 Step 都是一次模型请求 + 工具调用。

## 会话日志：一切都被记录

官方有一个核心原则：**模型可见即已记录**。

> *"Anything that reaches a model request must be reconstructable from the log."*
> 翻译：抵达模型请求的一切都必须能从日志重建。

这意味着：
- 用户发的每条消息 → 记入日志
- 模型的每次回复 → 记入日志
- 每次工具调用和结果 → 记入日志
- 每次注入的上下文 → 记入日志

这就是 **Trajectory** 功能的数据来源——你可以回放整个对话过程，因为每一步都被完整记录了。

## 小结

| 概念 | 一句话 |
|---|---|
| **Step** | 一次模型请求 + 它触发的工具调用 |
| **Turn** | 用户发一条消息后模型做的全部工作（含多个 Step） |
| **Round** | 外层策略的一次迭代（如 Ralph 循环的一轮） |
| **工具执行流水线** | pre-execute → guards → execute → post-execute → finalize → result |
| **会话日志** | 模型看到的一切都被记录，可回放 |

## 官方文档参考

- [agent-lifecycle.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/agent-lifecycle.md) / [中文版](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/agent-lifecycle.zh.md)——完整的 Mermaid 时序图
- [tool-execution-pipeline.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/tool-execution-pipeline.md) / [中文版](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/tool-execution-pipeline.zh.md)——工具执行流水线图
- [architecture.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md) 的 Turn Flow 章节

## 下一篇

- [[04 四种 Agent 模式有什么区别|04 四种 Agent 模式有什么区别]]——Standard / Code / Minimal / Cordis
