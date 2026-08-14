---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, 使用场景, 社区, 生态]
created: 2026-08-14
updated: 2026-08-14
---

# 06 dsh 能干什么——实际使用场景和社区生态

## dsh 到底能干什么

一句话：**把大模型变成能干活的 Agent。**

大模型本身只会聊天——你问它答。dsh 给模型穿上"工作服"，让它能：

| 能力 | 说明 |
|---|---|
| 读写文件 | 在你的项目目录里读代码、改代码 |
| 执行命令 | Bash 命令，跑测试、装依赖、构建项目 |
| Web 搜索 | 联网搜资料、查文档 |
| 子 Agent 委派 | 把大任务拆成小任务，派给子 Agent 并行处理 |
| 计划模式 | 先调研再动手，不急着改代码 |
| 会话持久化 | 对话记录保存下来，可以恢复、分叉、回放 |
| Trajectory 回放 | 看每一步模型看到了什么、做了什么 |
| 技能系统 | 可复用的工作流模板 |

## 四种使用方式

### 1. Web UI——日常写代码

```bash
dsh web
```

打开浏览器，配好 API Key，选一个项目目录，开始对话。体验类似 Claude Code 或 Cursor，但用 DeepSeek 模型，完全本地运行。

### 2. Headless——自动化任务

```bash
dsh --profile headless "检查仓库并修复失败的测试"
```

不启动浏览器，给任务就跑，跑完打印结果退出。适合 CI/CD 流水线、批量处理。

### 3. Python SDK——嵌入自己的程序

```python
with DeepSeekHarness(
    provider="deepseek-official",
    model="deepseek-v4-flash",
    cwd="/path/to/project",
    session_root="/path/to/sessions",
    cordis="/path/to/config.yml",
) as harness:
    result = harness.run("修复失败的测试", session_id="task-001")
```

### 4. 自定义 Profile——搭自己的 Agent

```bash
# 创建自定义 Profile
dsh plugin --profile myagent add some-plugin

# 启动
dsh --profile myagent
```

## 社区已经做出来的东西

### 插件

| 插件 | 作者 | 干什么 |
|---|---|---|
| **dsh-compaction** | 社区 | 语义压缩上下文，比官方方式便宜 35.6 倍 |
| **dsh-memory-director** | 社区 | 跨会话记忆——每轮结束后决定记什么、忘什么 |
| **dsh-aura-scheduler** | 社区 | 主动调度——Agent 不等用户说话，自适应节奏主动发言 |

### 基于 dsh 理念的项目

| 项目 | Stars | 说明 |
|---|---|---|
| **deepseek-tui** | 2.3k+ | Rust 写的终端 Agent，实现了多子 Agent 并行 fan-out（1 个 V4-Pro 派 16 个 V4-Flash 并行干活） |
| **dscode** | — | 用 dsh 自己开发自己的项目——所有功能都是 dscode 运行在 DeepSeek V4 Pro 上编辑自己源码实现的 |
| **HenryZ838978/deepseek-harness** | — | DeepSeek V4 协议适配层，用 4 种格式（Python 库 / CLI / MCP 服务器 / Anthropic Skill）封装同一套协议契约 |

## dsh 的核心设计洞察

读完官方文档和源码后，我认为 dsh 有四个值得注意的设计：

### 1. 一切皆 Patch

dsh 没有传统意义上的"配置文件"。连 `dsh-base` 本身也是一个 patch（`cordis.patch.yml`），只是以 npm 包的形式分发。你改任何东西都是在"叠加一层 patch"。

### 2. 插件不是可选的

"Everything is a Plugin"不是说插件可选，而是说**所有功能都以插件形式存在**。连 LLM 调用、会话管理、沙箱这些核心能力都是插件。这使得 dsh 可以通过替换插件来完全改变行为。

### 3. 注册是可逆的

Cordis 的核心特性——插件加载时注册的所有东西（事件监听器、工具、服务），在卸载时都会自动撤销。这意味着插件可以热插拔，不会留下垃圾。

### 4. 模型可见即已记录

任何到达模型请求的内容都必须能从会话日志重建。这就是 Trajectory 功能的基础——每一步都被完整记录，可以回放。

## 和竞品对比

| 维度 | dsh | Claude Code | Cursor |
|---|---|---|---|
| **模型** | DeepSeek（可接其他） | Claude | 多模型 |
| **开源** | MIT 全开源 | 闭源 | 闭源 |
| **插件架构** | 一切皆插件，热插拔 | 无 | 有扩展但非插件化 |
| **子 Agent** | 内置，可并行 | 无 | 无 |
| **会话可回放** | 完整事件流 + Trajectory | 无 | 无 |
| **可定制性** | 极高 | 低 | 低 |
| **成熟度** | Developer Preview | 成熟 | 成熟 |

## 现在的局限

1. **还很早期**——Windows 下有 Bug、插件安全没做、文档不完善
2. **插件安全**——插件运行在宿主进程中，有 host 级权限，没有签名验证
3. **社区刚起步**——插件不多，踩坑的人还不够多

## 学习路线进度

- [x] 00 — dsh 概述
- [x] 01 — dsh 是怎么运转的——从一条命令说起
- [x] 02 — Cordis 框架入门——五个核心概念
- [x] 03 — Agent 的一次完整对话是怎么跑的
- [x] 04 — 四种 Agent 模式有什么区别
- [x] 05 — dsh 的安全机制——沙箱、权限和审批
- [x] 06 — dsh 能干什么——实际使用场景和社区生态（本页）
- [ ] 07 — 编写自定义插件
- [ ] 08 — 实战：用 dsh 构建 Agent

## 相关链接

- [[00 dsh 概述|dsh 概述]] — 前置阅读
- [[01 dsh 是怎么运转的——从一条命令说起|dsh 是怎么运转的]]
- [[02 Cordis 框架入门——五个核心概念|Cordis 框架入门]]
- [[03 Agent 的一次完整对话是怎么跑的|Agent 的一次完整对话]]
- [[04 四种 Agent 模式有什么区别|四种 Agent 模式]]
- [[05 dsh 的安全机制——沙箱、权限和审批|安全机制]]
