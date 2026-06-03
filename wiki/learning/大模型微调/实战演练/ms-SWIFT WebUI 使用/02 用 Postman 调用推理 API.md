---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, postman, api, openai, 推理, 排查]
created: 2026-06-02
updated: 2026-06-02
---

# 02 用 Postman 调用推理 API

> 你用 WebUI 的"部署模型"把服务起在了 **8002 端口**(见 [[01 ms-SWIFT WebUI 总览]])。这个服务是 **OpenAI 兼容**的,所以 Postman、curl、任何 OpenAI 客户端都能调。本页给出**可直接复制的真实请求**(已在本机实测通过)。

## 1. 关键前提:你的服务信息(实测确认)

| 项 | 值 |
|---|---|
| **服务地址** | `http://localhost:8002` |
| **模型 id(`model` 字段必须用这个)** | <font color="red">**`Qwen3-0.6B-Base`**</font> |
| **协议** | OpenAI 兼容(`/v1/...`) |

> [!important] <font color="red">model 字段必须填 `Qwen3-0.6B-Base`,不是 `Qwen3-0.6B`</font>
> 服务实际注册的模型 id 是 `Qwen3-0.6B-Base`(见日志 `model_list: ['Qwen3-0.6B-Base']`)。**填错 id 会报错或无响应**,这是最常见的"没反应"原因之一。不确定就先查模型列表(下面接口 ①)。

## 2. 三个常用接口(Postman 直接照抄)

### ① 查模型列表(先验证服务通不通)

- **Method**:`GET`
- **URL**:`http://localhost:8002/v1/models`

返回(实测):
```json
{"data":[{"id":"Qwen3-0.6B-Base","object":"model","owned_by":"swift"}],"object":"list"}
```
能返回这个 → 服务 OK,且确认了 `model` 该填什么。

### ② 对话接口(最常用)★

- **Method**:`POST`
- **URL**:`http://localhost:8002/v1/chat/completions`
- **Headers**:`Content-Type: application/json`
- **Body**(选 raw → JSON):

```json
{
  "model": "Qwen3-0.6B-Base",
  "messages": [
    {"role": "user", "content": "你好,你是谁"}
  ],
  "max_tokens": 256,
  "temperature": 0
}
```

返回(实测,已成功):
```json
{
  "model": "Qwen3-0.6B-Base",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "您好，我是Assistant。我是一个人工智能助手..."},
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 12, "completion_tokens": 50, "total_tokens": 62}
}
```

### ③ 流式输出(像打字一样)

Body 里加 `"stream": true`:
```json
{
  "model": "Qwen3-0.6B-Base",
  "messages": [{"role": "user", "content": "讲个笑话"}],
  "stream": true,
  "max_tokens": 256
}
```
返回会是一串 `data: {...}` 的 SSE 流。Postman 能显示,但看流式效果不如 curl 直观。

## 3. curl 等价命令(终端快速测)

```bash
# 查模型
curl http://localhost:8002/v1/models

# 对话
curl http://localhost:8002/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-0.6B-Base",
    "messages": [{"role": "user", "content": "你好,你是谁"}],
    "max_tokens": 256,
    "temperature": 0
  }'
```

## 4. ★ "发内容没反应"排查清单

> [!important] <font color="red">先记住:服务本身是好的</font>
> 我在本机实测,`/v1/chat/completions` 能正常返回回答。所以"没反应"基本不是服务挂了,而是下面几种情况:

| 可能原因 | 怎么确认 | 解决 |
|---|---|---|
| **1. model id 填错** | 用接口 ① 查真实 id | `model` 必须填 `Qwen3-0.6B-Base` |
| **2. 网页 Chatbot 区域没刷新 / 卡住** | 看 WebUI 最底部 Chatbot 输入框 | 刷新页面;或干脆绕开网页,直接用 Postman/curl 调 8002 |
| **3. CPU 推理太慢,以为没反应** | 看日志有没有在动 | <font color="red">**Mac 上是 CPU(你 GPU 选了 cpu),0.6B 也要等几秒到十几秒**,耐心等返回,别以为卡住</font> |
| **4. 调错端口** | 确认 URL 是 `:8002` | WebUI 网页端口(7860)≠ 推理服务端口(8002),Postman 要调 **8002** |
| **5. Base 模型没对话模板** | 看回答是否答非所问 | `Qwen3-0.6B-Base` 是**基座**(非 Instruct),对话能力弱、可能乱答;练对话建议用 Instruct 版或加载你训练的 LoRA |

> [!key-insight] <font color="red">最可能的两个原因(按你这次情况)</font>
> 1. **CPU 推理慢**:Mac 走 CPU,生成几十个 token 要等一会儿,网页上看着像"没反应",其实在算。
> 2. **用的是 Base 模型**:`Qwen3-0.6B-Base` 是基座模型,**没经过对话微调**,在网页 Chatbot 里可能答得很差或不像对话。想要正常对话,应加载 **Instruct 版**或你自己训出的 **LoRA**(`--adapters` 填 checkpoint 路径)。

## 5. 想用 Python(OpenAI SDK)调

因为是 OpenAI 兼容接口,标准 SDK 直接改 base_url 即可:
```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8002/v1", api_key="EMPTY")
resp = client.chat.completions.create(
    model="Qwen3-0.6B-Base",
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.choices[0].message.content)
```

## 继续学习

- [[01 ms-SWIFT WebUI 总览|ms-SWIFT WebUI 总览]](服务从哪起的、端口怎么来的)
- [[05 ms-SWIFT 推理命令详解|ms-SWIFT 推理命令详解]](命令行 swift deploy / infer)
- [[04 ms-SWIFT 训练产物文件详解|训练产物文件详解]](加载自己训的 LoRA)
