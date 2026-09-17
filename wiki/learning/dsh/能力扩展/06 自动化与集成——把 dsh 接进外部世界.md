---
type: practice
status: done
area: growth
tags: [learning, dsh, DeepSeek, cordis, 阶段三, 能力扩展, integration, headless, mcp, sdk, github, 有出处, 已实测]
created: 2026-09-16
updated: 2026-09-16
---

# 06 自动化与集成——把 dsh 接进外部世界

> [!info] 版本锚点
> - 源码：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）；全局包 `dsh 0.1.5-rc.1`
> - 前置：回顾 09 篇（profile）、03 篇（存储）、全部 headless 实践
> - **本篇是阶段三 ③（自动化与集成）的综述**——偏"集成/部署"，多数需外部条件
> - 写法说明：本系列采用**完整重讲式**；**Headless 部分已实测**，其余讲清"是什么/怎么用/需什么前置"

## 这一篇在讲什么

前面你都在 dsh **内部**折腾（写插件、配 profile）。**③ 换视角**：**把 dsh 当成一个"能给外部系统调用的能力"**。

**五条集成线**：

| 集成线                   | 一句话                 | 前置条件               |
| --------------------- | ------------------- | ------------------ |
| **Headless**          | 命令行跑一个任务，打印答案退出     | **无**（本地即用）✅       |
| **Python SDK**        | 从 Python 程序调 dsh    | Python 3.10+ / key |
| **GitHub 评审**         | PR 转 ready 时自动建评审会话 | webhook + TLS 隧道   |
| **MCP**               | 让模型用**外部服务器**的工具    | MCP server         |
| **ACP / API Gateway** | 多端 / 远程暴露           | 复杂基建               |

> **出处**：`docs/architecture.zh.md:25`——*"`dsh-headless` 增加不带服务器的一次性运行器，`dsh-sdk-app` 增加 SDK JSON-RPC 服务器，`dsh-acp-app` 增加仅用于自动化的 ACP 服务器。"*

---

## 一、Headless：最实用的集成（已实测）

**它就是"命令行一次性任务"**——`dsh --profile headless "<任务>"` → 打印答案 + 退出。

> **出处**：`apps/cli/README.zh.md:14`——*"`dsh --profile headless "job"` | 运行一个全新的持久化会话，打印最终答案并退出。"*

### ✅ 实测（CI 适用性）

```sh
dsh --profile headless --patch <codebuddy> "只回答两个字：收到"
# → 收到
# 退出码: 0
```

> **出处**：本人实测（2026-09-16，`dsh 0.1.5-rc.1`）

**关键特性**（CI 友好）：
- **stdout 只有最终答案**（`--help` 说："stream reasoning to **stderr**, print the final assistant message, and exit"）
- **非零退出码 = 失败**（脚本可判断）
- **会落盘持久化会话**（"全新的持久化会话"）

> **出处**：`dsh --profile headless --help`（实测）

### ⚠️ 版本注意：`--json` / `--session-id` 当前未实现

bundle 头注释提到 `--session-id` 和 `--json` 选项，但**当前版本 `--help` 只列了 `task`**——传 `--session-id` 报 `error: unknown option`。

> **出处**：本人实测（2026-09-16）——`dsh --profile headless --session-id ... ` → `unknown option '--session-id'`

**📌 教训**：**bundle 注释 ≠ 当前 CLI 事实**——用前先 `--help` 核实（dsh 快速迭代）。

### CI 用法示意

```yaml
# .github/workflows/dsh.yml（示意）
- run: dsh --profile headless "检查代码并修复失败的测试"
```

**这就是"Headless 跑 CI"**——把 dsh 当成一个能操作仓库的命令。

---

## 二、GitHub 评审：webhook 驱动的自动 PR review

**机制**：一个签名 webhook 端点，**PR 从 draft 变 ready 时，自动在对应仓库建一个评审会话**。

> **出处**：`guide/github-review.zh.md`（逐字）

**流程**：
```
GitHub 发 PR ready_for_review webhook
  → dsh 的 /github 端点验签
  → 规则匹配（来源/仓库/事件/动作）
  → 建根 Session（标题、只读评审提示词）
  → 在对应 Workspace 下跑评审
```

**关键设计**（都值得记住）：
- **只读**：Session 用 `standard` agent preset + **`read-only` permission preset**——*"禁止修改文件、分支、PR 或 GitHub 状态"*
- **精确匹配**：只接受特定 `repository` + `action: ready_for_review`
- **不受信元数据**：PR 字段标为"untrusted metadata"
- **响应弱于结果**：HTTP `202` 只表示"签名+JSON 已接受、调度了规则"——**不代表已匹配或建 Session**
- **规则是普通 JS**：`run()` 可查询内部策略、映射仓库到本地路径

> **出处**：`guide/github-review.zh.md`（"规则行为"/"程序化扩展"/"交付语义"节）

**前置**（较重的基建）：
- 本地 checkout（注册为 Web Workspace）
- **`DSH_GITHUB_WEBHOOK_SECRET`**（高熵密钥）
- **TLS 反向代理/隧道**（把公网 URL 转发到 loopback）
- GitHub webhook 订阅 Pull requests

> **出处**：`guide/github-review.zh.md`（"前置条件"节）

> **Go 类比**：像**给 CI 加一个 webhook 接收器**——GitHub 事件 → 你的服务 → 触发动作。dsh 把这个"动作"变成了"建评审会话"。

---

## 三、MCP：让模型用外部工具

**MCP（Model Context Protocol）** = **让模型用外部服务器提供的工具**。

> **出处**：`subsystems/mcp.zh.md`——*"模型上下文协议（MCP）让模型使用外部服务器提供的工具。每个已配置服务器都会提供普通 Harness 工具，支持取消、权限检查、结果记录和受支持的图像输出。"*

**机制**：
- 配一个 MCP server（**stdio 命令**或 **Streamable HTTP URL**）
- dsh 发现它的工具，暴露成 **`mcp__<serverName>__<tool>`**

> **出处**：`guide/mcp-memory.zh.md`——*"启动已配置的 stdio 命令或连接已配置的 Streamable HTTP URL，发现 MCP 工具，并以 `mcp__<serverName>__<tool>` 的形式公开这些工具。"*

**安全设计**（值得记）：
- **stdio 桥接器启动子进程前**，**主动移除**"名称通常表示凭据的变量"和**所有 `DSH_*` 变量**——其余继承
- 服务器指令加入系统提示词（受信边界清晰）

> **出处**：`guide/mcp-memory.zh.md`（"DSH 负责什么"节）

**官方样例**：`mcp-memory`（连第三方记忆系统）、`schedule` 等。

> **Go 类比**：像**给你的服务挂一个"外部插件进程"**——通过协议（stdio/HTTP）通信，工具被透明转发。

---

## 四、Python SDK：从程序调用

**机制**：`deepseek-harness-sdk` 提供 `DeepSeekHarness` 类，程序里 `with` 上下文调用。

> **出处**：`guide/python-sdk.zh.md`

```python
from deepseek_harness import DeepSeekHarness

with DeepSeekHarness(
    provider="deepseek-official", model="deepseek-v4-flash",
    cwd=str(workspace), dsh_home=str(dsh_home), profile="sdk-minimal",
) as harness:
    result = harness.run("Inspect the repository...", session_id="example-001")
```

**关键点**：
- **`sdk-minimal` profile**（刻意精简的独立配置树）
- **不会静默读 `~/.dsh`**（显式传 `dsh_home`）
- 前置：Python 3.10+ / DeepSeek key / 隔离 workspace

> **出处**：`guide/python-sdk.zh.md`（"在程序中使用 SDK"节）

> **注**：你是 Go 背景，Python SDK 的价值主要是"**知道 dsh 能被程序嵌入**"。

---

## 五、ACP / API Gateway：多端与远程（简）

- **`dsh-acp-app`**：*"仅用于自动化的 ACP 服务器"*（另一种集成协议）
- **API Gateway**：dsh 内部把能力经 **Typert 远程调用协议**暴露（Host ↔ Client）——回扣 01 篇的模型目录（`@Remote('modelCatalog')`）

> **出处**：`docs/architecture.zh.md:25`；01 篇的 session-controller `@Remote`

---

## 一页纸总结

| 集成线 | 一句话 | 前置 | 出处 |
|---|---|---|---|
| **Headless** | 命令行一次性任务，打印答案退出 | 无 ✅ | `apps/cli/README:14` |
| Headless 特性 | stdout 只出答案；非零退出=失败 | — | `--help` 实测 |
| **GitHub 评审** | PR ready → 建只读评审会话 | webhook+隧道 | `guide/github-review` |
| **MCP** | 模型用外部服务器工具（`mcp__x__y`） | MCP server | `subsystems/mcp` |
| **Python SDK** | 程序里 `DeepSeekHarness` 调用 | Python+key | `guide/python-sdk` |
| **ACP** | 仅自动化的 ACP 服务器 | 复杂 | `architecture:25` |

## 踩坑预防

- **⚠️ CLI 选项先 `--help` 核实**：bundle 注释提到 `--json`/`--session-id`，但当前版本未实现（`unknown option`）。（出处：实测）
- **⚠️ Headless 输出分流**：最终答案走 stdout，**reasoning 走 stderr**——脚本捕获 stdout 才干净。（出处：`--help`）
- **⚠️ GitHub 评审是只读的**：用 `read-only` permission preset，禁改文件/分支/PR。（出处：`github-review`）
- **⚠️ MCP stdio 会清洗环境变量**：凭据类 + `DSH_*` 被移除。（出处：`mcp-memory`）

## 下一步

- **阶段三完成** ✅（①模型接入 ②上下文记忆 ③自动化集成）
- **深水区**（AGENTS.md 规划）：agent-loop 内核 / 多 Agent 协作 / Web UI 定制 / mini-dsh 从零实现 / Agent 自进化闭环
- **横向技能**：提示词工程 / 可观测性 / 安全实践 / 成本意识
