---
type: concept
status: developing
area: growth
tags: [learning, 微调, function-calling, tool-use, MCP, Model-Context-Protocol, 推理, 应用层]
created: 2026-06-03
updated: 2026-06-03
---

# 09 Function Calling 与 MCP 原理详解

> 本篇深入讲解：**模型是怎么学会「调用工具」的？推理时工具调用是怎么发生的？MCP 在其中扮演什么角色？** 一句话先给结论：
>
> **模型本身不会「直接调用」任何东西。模型只是在生成文本，当它生成了一段符合工具调用格式的 JSON，应用层（你写的代码）拦截这段 JSON、执行对应的工具（可能是 MCP 服务）、把结果塞回对话历史，再让模型继续生成。**

---

## 1. 先厘清两个概念：Function Calling vs MCP

很多人把这两个搞混，但它们是**完全不同层级的东西**：

| | Function Calling（函数调用） | MCP（Model Context Protocol） |
|---|---|---|
| **是什么** | 模型的能力：生成结构化 JSON 来描述「要调用哪个工具、参数是什么」 | 应用层协议：定义了「AI 应用」和「外部工具/数据源」之间怎么通信 |
| **发生在哪层** | **模型内部**（生成 token 的过程） | **应用层**（模型生成完工具调用文本后，由你的代码执行） |
| **谁实现的** | 模型训练时学会的（SFT 数据里包含工具调用样本） | Anthropic 制定的标准协议，任何 AI 应用都可以实现 |
| **类比** | 人「想说」一句话 | 这句话通过「电话协议」传给对方 |

**一句话：** Function Calling 是模型「会说工具调用的语言」；MCP 是工具提供方和 AI 应用之间的「接线标准」。

---

## 2. Function Calling 的训练原理：模型学到了什么？

### 2.1 核心事实：模型只是在「学说话」

Function Calling 的训练，**本质上和普通 SFT 没有任何区别**——都是让模型学会「在某个上下文中，接下来应该输出什么 token」。

区别在于：**训练数据里包含了工具调用的样本**，模型通过这些样本学会了：
- 什么时候应该调用工具（而不是自己回答）
- 工具调用的 JSON 格式长什么样
- 工具返回结果后，怎么基于结果继续回答

### 2.2 训练数据长什么样？

Function Calling 的 SFT 数据，每条样本是一个**多轮对话**，其中穿插了 `tool_call` 和 `tool_result`：

```json
{
  "messages": [
    {"role": "user", "content": "北京今天天气怎么样？"},
    {"role": "assistant", "content": null, "tool_calls": [
      {"id": "call_001", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\": \"北京\"}"}}
    ]},
    {"role": "tool", "tool_call_id": "call_001", "content": "{\"city\": \"北京\", \"temp\": \"28°C\", \"condition\": \"晴\"}"},
    {"role": "assistant", "content": "北京今天天气晴朗，气温 28°C。"}
  ]
}
```

模型在 SFT 时看到这样的数据，就学会了：
1. 用户问天气 → 我应该输出 `tool_calls`（而不是直接回答）
2. `tool_calls` 的 JSON 格式要长这样
3. 工具返回结果后 → 我应该基于结果生成最终回答

### 2.3 训练时模型「知道」工具的存在吗？

**不知道。** 模型训练时：
- 不知道有 `get_weather` 这个工具
- 不知道这个工具需要 `city` 参数
- 它只知道：**在看到这样的对话历史后，接下来应该生成这样的文本**

工具的「定义」（名称、描述、参数 schema）是**推理时**通过 `tools` 参数传给模型的（OpenAI 格式：`messages` + `tools` 字段）。模型在推理时「看到」工具定义，结合训练时学到的模式，才知道「哦，我现在可以调用这些工具」。

> [!key-insight] 训练 vs 推理的关键区别
> | | 训练时 | 推理时 |
> |---|---|---|
> | 模型看到什么 | 包含 tool_call/tool_result 的对话历史 | 用户消息 + 工具定义（tools 参数）|
> | 模型学到/用到什么 | 「看到工具定义后，应该生成 tool_call JSON」的模式 | 根据当前工具和对话，决定要不要调用 |
> | 工具的定义是哪来的 | 训练数据里的（隐含在样本里） | **你传进来的**（`tools` 参数）|

---

## 3. 推理时的完整流程：工具调用是怎么发生的？

这是最核心的部分。很多人以为「模型自己调用了工具」，其实不是。

### 3.1 完整流程图

```
用户: "北京今天天气怎么样？"
        │
        ▼
  ┌─────────────────────────────────────┐
  │  你的应用代码（推理入口）              │
  │  把用户消息 + tools 定义发给模型      │
  └──────────────┬──────────────────────┘
                   │
                   ▼
  ┌─────────────────────────────────────┐
  │  模型推理（生成 token）                │
  │  → 输出:                             │
  │  {"tool_calls": [                    │
  │    {"id":"call_001",                 │
  │     "function":{"name":"get_weather", │
  │                 "arguments":"{\"city\":\"北京\"}"}}]} │
  └──────────────┬──────────────────────┘
                   │
                   ▼  ← 关键：应用层拦截！
  ┌─────────────────────────────────────┐
  │  你的应用代码检测到「模型要调工具」    │
  │  → 解析 tool_calls JSON             │
  │  → 找到 get_weather 的实现           │
  │  → 执行它（可能是本地函数，也可能是   │
  │     通过 MCP 协议调用远程服务）        │
  └──────────────┬──────────────────────┘
                   │
                   ▼
  ┌─────────────────────────────────────┐
  │  工具执行完成，拿到结果:              │
  │  {"city":"北京","temp":"28°C",...}  │
  └──────────────┬──────────────────────┘
                   │
                   ▼
  ┌─────────────────────────────────────┐
  │  应用代码把结果塞回对话历史:           │
  │  messages.append({                   │
  │    role: "tool",                    │
  │    content: "{\"temp\":\"28°C\",...}"│
  │  })                                 │
  └──────────────┬──────────────────────┘
                   │
                   ▼
  ┌─────────────────────────────────────┐
  │  再次调用模型（带着更新后的历史）       │
  │  → 模型继续生成:                     │
  │  "北京今天天气晴朗，气温 28°C。"      │
  └─────────────────────────────────────┘
                   │
                   ▼
              输出给用户
```

### 3.2 关键认知：模型「调工具」的全过程

| 步骤 | 谁在做 | 具体在做什么 |
|---|---|---|
| 1. 模型生成 tool_call JSON | **模型**（推理时） | 自回归生成 token，输出一段 JSON |
| 2. 解析 JSON，找到对应工具 | **应用层代码** | 你的代码解析 `tool_calls[0].function.name` |
| 3. 执行工具 | **应用层代码** | 调用函数 / 发 HTTP 请求 / 通过 MCP 调用 |
| 4. 拿到结果 | **工具服务端** | 真正执行查询/计算/API 调用 |
| 5. 结果塞回对话 | **应用层代码** | `messages.append({role:"tool", content: result})` |
| 6. 模型继续生成 | **模型**（第二轮推理） | 看到 tool result，生成最终回答 |

**模型只做了第 1 步和第 6 步。中间的 2~5 步，全是应用层代码在做。**

### 3.3 代码层面长什么样？

以 OpenAI SDK 风格为例（ms-SWIFT / LLaMA-Factory 的推理 API 也类似）：

```python
# 伪代码，展示核心逻辑

tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "获取指定城市的天气",
            "parameters": {"type": "object", "properties": {"city": {"type": "string"}}}
        }
    }
]

messages = [{"role": "user", "content": "北京今天天气怎么样？"}]

# 第一轮：模型生成 tool_call
response = client.chat.completions.create(
    model="qwen3-4b",
    messages=messages,
    tools=tools,          # ← 把工具定义传进去
)

# 检查模型是否要调工具
if response.choices[0].message.tool_calls:
    tool_call = response.choices[0].message.tool_calls[0]
    func_name = tool_call.function.name        # "get_weather"
    func_args = json.loads(tool_call.function.arguments)  # {"city": "北京"}

    # ← 应用层执行工具（这里可能是 MCP 调用）
    result = execute_tool(func_name, func_args)  # ← 关键！

    # 把 tool_call 和 tool_result 都加入历史
    messages.append({"role": "assistant", "content": None, "tool_calls": [tool_call]})
    messages.append({"role": "tool", "tool_call_id": tool_call.id, "content": result})

    # 第二轮：模型基于 tool result 继续生成
    response = client.chat.completions.create(
        model="qwen3-4b",
        messages=messages,
    )

print(response.choices[0].message.content)  # "北京今天天气晴朗..."
```

---

## 4. MCP 在其中扮演什么角色？

### 4.1 MCP 是什么（用大白话）？

MCP（Model Context Protocol）是 Anthropic 推出的一个**开放协议**，定义了：

> **AI 应用（Host）** 和 **工具/数据源（Server）** 之间，怎么通信。

没有 MCP 之前，每个 AI 应用要接入一个工具，都要**自己写一套集成代码**（OpenAI 函数调用格式、Google 格式、本地 Python 函数……每家不一样）。

有了 MCP 之后：
- **工具提供方**：按 MCP 协议写一个 Server（暴露工具列表 + 调用接口）
- **AI 应用方**：按 MCP 协议连接 Server，自动发现工具、调用工具
- **两边对接**：一套协议，不用每家都写适配

### 4.2 MCP 在工具调用流程中的位置

```
AI 应用（你的代码）
    │
    ├── 没有 MCP: 直接调用本地 Python 函数
    │   execute_tool() → local_python_func(args)
    │
    ├── 有 MCP: 通过 MCP 协议调用远程服务
    │   execute_tool() → mcp_client.call_tool(name, args)
    │                       │
    │                       ▼
    │                  MCP Server（可能是另一台机器上的进程）
    │                  → 执行真正的工具逻辑
    │                  → 返回结果
    │
    └── 共同点: 对模型来说完全透明！模型不知道工具是怎么执行的
```

**关键：MCP 是应用层的东西，模型完全无感。** 模型只管生成 JSON，至于这个 JSON 描述的工具是本地函数还是 MCP 远程服务，模型不知道也不关心。

### 4.3 MCP Server 是「启动时加载」的吗？

这取决于你的应用架构，有两种模式：

#### 模式 A：MCP Server 独立进程（Stdio 模式）

```
你的 AI 应用进程
    │
    ├── 启动时: subprocess.Popen() 拉起 MCP Server 子进程
    │   （MCP Server 作为一个独立进程运行）
    │
    ├── 运行时: 通过 stdin/stdout 和 MCP Server 通信
    │   → 发 JSON-RPC 请求（"列出你的工具"/"调用 get_weather"）
    │   → 收 JSON-RPC 响应
    │
    └── 关闭时: 杀掉 MCP Server 子进程
```

- MCP Server 是**独立进程**，你的应用通过 stdio 和它通信
- 「启动时加载」= 你的应用启动时，把 MCP Server 进程拉起来
- 模型**不参与**这个启动过程

#### 模式 B：MCP Server 是 HTTP 服务（SSE/HTTP 模式）

```
你的 AI 应用
    │
    ├── 运行时: HTTP 请求 → MCP Server（已部署好的 Web 服务）
    │   → GET /tools  （发现工具）
    │   → POST /call  （调用工具）
    │
    └── MCP Server 可能早就跑着了（跟你应用无关）
```

- MCP Server 是**预先部署好的 HTTP 服务**
- 你的应用运行时才连接它
- 更松耦合

### 4.4 模型「知道」MCP 的存在吗？

**完全不知道。** 对模型来说：

```
模型看到的（tools 参数）:
[
  {"type": "function", "function": {"name": "get_weather", "description": "...", "parameters": {...}}}
]

模型生成的（输出文本）:
{"tool_calls": [{"id": "call_001", "function": {"name": "get_weather", "arguments": "{\"city\":\"北京\"}"}}]}

模型完全不知道:
  - get_weather 是本地函数还是 MCP 远程服务
  - MCP Server 进程在哪台机器上
  - 调用花了多长时间
  - 结果是怎么拿到的

模型只知道:
  "我应该输出这个格式的 JSON，然后应用层会处理后续"
```

---

## 5. 训练 Function Calling 模型的具体做法

如果你想**微调一个支持 Function Calling 的模型**（比如让 Qwen3-4B 学会调用你自定义的工具），需要：

### 5.1 准备训练数据

数据格式参考 OpenAI 的 `messages` 格式，每条样本包含：
- `user` 消息（用户请求）
- `assistant` 消息带 `tool_calls`（模型决定调工具）
- `tool` 消息（工具返回结果）
- `assistant` 消息（模型基于结果回答）

> [!tip] 不想自己标？用现成数据集
> - **ToolBench / ToolAlpaca**: 通用工具调用数据集
> - **Gorilla**: 专注 API 调用的数据集
> - **ms-SWIFT 内置数据集**: 搜索 `tool` 相关数据集

### 5.2 微调时的关键参数

```bash
swift sft \
    --model Qwen/Qwen3-4B-Instruct \
    --dataset your_tool_calling_data.jsonl \
    --torch_dtype bfloat16 \
    --num_train_epochs 3 \
    --per_device_train_batch_size 2 \
    --gradient_accumulation_steps 8 \
    --learning_rate 1e-4 \
    --tuner_type lora \
    --lora_rank 16          # Function Calling 比普通 SFT 复杂，rank 可以稍大
```

### 5.3 推理时怎么让模型用你的工具？

微调完后，推理时需要：

```python
# 1. 定义你的工具（OpenAI 格式）
my_tools = [
    {
        "type": "function",
        "function": {
            "name": "query_database",
            "description": "查询内部数据库",
            "parameters": {"type": "object", "properties": {"sql": {"type": "string"}}}
        }
    }
]

# 2. 推理时传入 tools 参数
response = predict(
    model="your_finetuned_qwen3_4b",
    messages=[{"role": "user", "content": "查一下销售额最高的产品"}],
    tools=my_tools,          # ← 告诉模型有哪些工具可用
    tool_choice="auto",      # auto = 模型自己决定是否调工具
)
```

---

## 6. 常见误解澄清

| 误解 | 事实 |
|---|---|
| 「模型训练时把 MCP Server 加载进去了」 | 模型训练时只看到文本数据，完全不知道 MCP 的存在 |
| 「模型自己调用了工具」 | 模型只生成了工具调用的 JSON 文本，真正执行工具的是你的应用层代码 |
| 「MCP 是模型的能力」 | MCP 是应用层协议，和模型无关；任何模型（只要支持 Function Calling 格式输出）都可以配合 MCP 使用 |
| 「启动时模型就知道了所有工具」 | 推理时通过 `tools` 参数传入，模型每次推理都能看到（在 context 里） |
| 「工具调用是一次生成完成的」 | 通常是**两次生成**：第一次生成 tool_call，拿到结果后第二次生成最终回答（多轮工具调用可以更多次） |

---

## 7. 总结：一张图记住全流程

```
┌───────────┐
│                      训练阶段                                   │
│  数据: [用户问] → [助手:tool_call JSON] → [工具:result] → [助手:回答] │
│  模型学到: "看到工具和这个问题，我应该输出 tool_call JSON"           │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌───────────┐
│                      推理阶段                                   │
│  1. 应用: 用户问 + tools定义 → 发给模型                          │
│  2. 模型: 生成 tool_call JSON ← 模型只做这个                      │
│  3. 应用: 拦截JSON → 执行工具(本地/MCP) → 拿结果 ← 应用层做这个    │
│  4. 应用: 结果塞回历史 → 再发给模型                              │
│  5. 模型: 生成最终回答 ← 模型只做这个                             │
└───────────┘

MCP 的位置: 第 3 步里，"执行工具"可以通过 MCP 协议调用远程服务
模型的视角: 完全不知道 MCP 的存在，只知道要生成特定格式的 JSON
```

---

## 继续学习

- [[04 SFT 与指令微调|SFT 与指令微调]]（Function Calling 本质是特殊的 SFT 数据）
- [[03 LoRA 与 QLoRA|LoRA 微调]]（用 LoRA 微调 Function Calling 模型）
- [[03 ms-SWIFT 测试运行示例|ms-SWIFT 推理]]（推理时 `tools` 参数怎么传）
- 外部参考: [MCP 官方文档](https://modelcontextprotocol.io) | [OpenAI Function Calling](https://platform.openai.com/docs/guides/function-calling)
