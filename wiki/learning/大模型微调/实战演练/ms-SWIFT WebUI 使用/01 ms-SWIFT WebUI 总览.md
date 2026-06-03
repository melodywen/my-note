---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, webui, ui, 部署, 推理]
created: 2026-06-02
updated: 2026-06-02
---



# 01 ms-SWIFT WebUI 总览

> 本目录专讲 **ms-SWIFT 的图形界面(WebUI)**:`swift web-ui` 起的那个网页,把命令行的训/推/评/部署做成了表单点选。一句话记住:**WebUI 只是命令行的"可视化外壳",它在底层照样是去拼 `swift sft` / `swift deploy` 这些命令。**

## 0. WebUI 是什么、怎么启动

ms-SWIFT 自带一个 Gradio 网页界面,启动后浏览器里就能点。

```bash
swift web-ui                       # 启动 WebUI(默认端口 7860 左右)
SWIFT_UI_LANG=en swift web-ui      # 切英文界面
```

> 启动后访问提示的本地地址(如 `http://localhost:7860`)。注意:**WebUI 本身的端口**(网页地址)和**它帮你部署的推理服务端口**(下面的 8002)是**两个不同的端口**,别混。

## 1. 顶部标签页:对应命令行的几大功能

界面顶部一排标签,每个对应一类 `swift` 命令:

| 标签            | 对应命令                           | 干嘛                           |
| ------------- | ------------------------------ | ---------------------------- |
| **LLM预训练/微调** | `swift sft` / `swift pt`       | 训模型,见 [[03 ms-SWIFT 测试运行示例]] |
| **LLM人类对齐**   | `swift rlhf`                   | DPO/KTO 等对齐,见 [[06 RLHF 人类对齐详解]]   |
| **LLM GRPO**  | `swift rlhf --rlhf_type grpo`  | 强化学习训练,见 [[06 RLHF 人类对齐详解]] §6     |
| **LLM推理**     | `swift infer` / `swift deploy` | 加载模型对话 / 起 API 服务 ← 你截图在这页   |
| **LLM导出**     | `swift export`                 | 合并 LoRA / 量化                 |
| **LLM评测**     | `swift eval`                   | 跑评测集打分                       |
| **LLM采样**     | `swift sample`                 | 采样生成数据                       |

## 2. LLM推理页:加载自己训练的模型

推理页字段较多,而且**填错(尤其 model 留空)会直接报错**,所以单独成篇详讲:

> [!key-insight] 推理页怎么填 → 见 [[03 WebUI 推理页填写详解]]
> 核心就一句:**model 填基座(`Qwen/Qwen3-0.6B`),adapters 填你训练的 LoRA 路径,两者分开填**。点蓝色"部署模型"按钮 = 后台跑一条 `swift deploy`,把模型起成 **OpenAI 兼容的 HTTP API 服务**,日志出现 `Uvicorn running on http://0.0.0.0:<端口>` 即就绪。

## 3. 你这次的状态:服务其实**完全正常**

看你截图日志最后几行:
```
[INFO:swift] swift.__version__: 4.2.3
[INFO:swift] model_list: ['Qwen3-0.6B-Base']
INFO:   Application startup complete.
INFO:   Uvicorn running on http://0.0.0.0:8002 (Press CTRL+C to quit)
```

> [!important] <font color="red">服务已成功起在 8002 端口,模型 id 是 `Qwen3-0.6B-Base`</font>
> 实测验证(在本机 curl):
> - `GET http://localhost:8002/v1/models` → 正常返回模型列表 ✅
> - `POST http://localhost:8002/v1/chat/completions` → 正常返回回答 ✅
>
> **所以"发内容没反应"不是服务挂了**,原因见下一篇 [[02 用 Postman 调用推理 API]] 的排查清单(多半是:用了网页 Chatbot 但模型 id/模板没对上、或在 Chatbot 区而非 API、或界面卡住)。

## 继续学习

- [[03 WebUI 推理页填写详解|WebUI 推理页填写详解]](★怎么把自己训练的 LoRA 加载起来)
- [[02 用 Postman 调用推理 API|用 Postman 调用推理 API]](★你最关心的:怎么用 Postman 调 8002)
- [[05 ms-SWIFT 推理命令详解|ms-SWIFT 推理命令详解]](WebUI 底层就是这些命令)
- [[03 ms-SWIFT 测试运行示例|ms-SWIFT 测试运行示例]](命令行全流程)
