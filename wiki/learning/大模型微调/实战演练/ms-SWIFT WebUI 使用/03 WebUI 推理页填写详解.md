---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, webui, 推理, 部署, lora]
created: 2026-06-02
updated: 2026-06-02
---



# 03 WebUI 推理页填写详解

> 本篇是 [[01 ms-SWIFT WebUI 总览]] 里"LLM推理页"那部分的**单独放大版**:只讲一件事——**在 WebUI 推理页里，每个字段怎么填，才能把我自己训练出来的 LoRA(`checkpoint-xxx`)加载起来对话**。
>
> 一句话先记住:**推理页的"部署模型"蓝按钮 = 后台帮你跑一条 `swift deploy`**。所以这些字段，本质就是 `swift deploy` 的命令行参数。

## 1. 各字段速查表

从上到下，对照界面：

| 区块                | 对应参数                 | 怎么填                                                                          |
| ----------------- | -------------------- | ---------------------------------------------------------------------------- |
| **模型id或路径**       | `--model`            | 填**基座模型** id，如 `Qwen/Qwen3-0.6B`。<font color="red">不要填 checkpoint 目录！</font> |
| **模型类型**          | `--model_type`       | 一般自动识别，Qwen3 选 `qwen3`                                                       |
| **模板**            | `--template`         | Qwen3 选 `qwen3`                                                              |
| **合并LoRA**        | `--merge_lora`       | **取消勾选**(Mac 用 transformers 不需要合并)                                           |
| **推理框架**          | `--infer_backend`    | 选 `transformers`(=pt 原生，Mac 能跑);`vllm` 仅 NVIDIA                              |
| **adapter id或路径** | `--adapters`         | 填**训练产出的 LoRA 绝对路径**，如 `/Users/.../output/v1-xxx/checkpoint-94`              |
| **生成参数**          | `--max_new_tokens` 等 | 默认即可，想回答长点就调大 `max_new_tokens`                                               |
| **System字段**      | `--system`           | 系统提示词，可留空                                                                    |
| **选择可用GPU**       | `--device`           | Mac 选 `cpu`(无 CUDA)                                                          |
| **端口**            | `--port`             | 推理服务端口，记住它，Postman/curl 要用                                                   |
| **部署模型(蓝按钮)**     | = `swift deploy`     | ★点它才真正起服务                                                                    |

## 2. 核心心智:model 和 adapters 是两个东西

这是新手最容易错的一点：

> [!important] <font color="red">model 填基座，adapters 填你训练的 LoRA，两者分开填</font>
> - **基座模型**(`Qwen/Qwen3-0.6B`):原始大模型，几亿参数的"底子"。
> - **LoRA 适配器**(`checkpoint-94`):你训练产出的"补丁"，只有几 MB，**不能单独运行**，必须贴在基座上。
>
> 推理时框架做的事:**先加载基座 → 再把你的 LoRA 补丁贴上去 → 合成你微调后的模型**。
> 所以 `model` 和 `adapters` 必须分别填，**不能把 checkpoint 目录填进 model**。

```
基座 Qwen3-0.6B  +  你的 LoRA(checkpoint-94)  =  你微调后的模型
   (--model)          (--adapters)
```

## 2.5 「合并LoRA」(`--merge_lora`)到底是什么、几时改

这个勾选框最容易让人懵，单独讲透。先回到上面那个公式：

```
基座 Qwen3-0.6B  +  你的 LoRA(checkpoint-94)  =  你微调后的模型
```

推理时，"基座 + LoRA"有**两种拼法**，`--merge_lora` 就是在这两种里选：

|     | 不勾(动态加载)                 | 勾选(合并)                                     |
| --- | ------------------------ | ------------------------------------------ |
| 干的事 | 加载基座，**运行时**实时叠加 LoRA 补丁 | **提前**把 LoRA 算进基座权重，生成一份全新的完整模型            |
| 类比  | 照片 + 一层滤镜叠加显示            | 把滤镜**烤进**照片，存成新图                           |
| 产物  | 不产生新模型，原 checkpoint 不动   | 在 `checkpoint-xx-merged/` 生成一份完整模型(和基座一样大) |
| 速度  | 每步推理多一点点叠加开销             | 推理时就是普通模型，**略快**                           |
| 占用  | 省磁盘(LoRA 才几 MB)          | 多占磁盘(0.6B 也要上 GB)                          |

> [!key-insight] 一句话区分
> **不勾** = "基座和补丁分开放着，用的时候临时拼"。
> **勾选** = "先把补丁焊死进基座，存成一个新模型"。
> 两种方式**推理结果完全一样**，区别只在"要不要提前生成一份合并好的完整模型"。

### 几时**不勾**(默认、推荐)

> [!important] <font color="red">绝大多数情况都不勾,尤其是你现在(Mac + transformers)</font>
> - **用 `transformers`(pt) 后端**:它天生支持运行时动态加载 LoRA,直接填 `--adapters` 即可,**不需要合并**。
> - **想随时换不同 LoRA**:同一个基座,今天贴 checkpoint-94、明天贴 checkpoint-200,不勾的话切换很灵活,不用各存一份大模型。
> - **省磁盘**:LoRA 只有几 MB,合并后每份都是完整模型大小。
> - **你 Mac 这套**:`infer_backend=transformers` + `cpu`,**保持不勾**就对了。

### 几时**要勾**(合并)

> [!warning] 主要是为了用 vLLM 加速
> - **要用 `vllm` 后端**:<font color="red">vLLM 不支持运行时动态加载 LoRA 适配器(在 ms-SWIFT 这条路径下)</font>,必须**先合并**成完整模型,再交给 vLLM 跑。这是最常见的"必须勾"场景。
> - **要把模型导出/分发给别人**:合并后是一份独立完整模型,对方拿去直接用,不用再带着基座 + LoRA 两份东西。
> - **要做量化(GPTQ/AWQ 等)**:通常也需要先合并成完整模型再量化。
>
> 注意:vLLM 仅 NVIDIA 显卡能用,**Mac 跑不了**。所以你现在根本用不到合并。

### 决策速查

| 我的情况 | merge_lora |
|---|---|
| Mac / 想快速验证微调效果 / 用 transformers | **不勾** ✅ |
| 想用 vLLM 加速(NVIDIA) | **勾** |
| 想把模型打包给别人、或做量化 | **勾** |
| 不确定 | **不勾**(默认最安全) |

> [!key-insight] 合并是"一次性"动作,可以单独做
> 其实不一定在推理页勾。你也可以用 `swift export --merge_lora true --adapters <路径>` **单独**先合并好,得到一份 merged 模型,之后推理直接把那份 merged 当普通 `--model` 填就行(连 adapters 都不用填了)。详见 [[05 ms-SWIFT 推理命令详解]]。

## 3. 怎么知道该填哪个 model / template?

打开你训练产出目录里的 **`args.json`**(本机实测 `output/v1-20260602-121310/checkpoint-94/args.json`),里面写得清清楚楚：

```json
{
  "model": "Qwen/Qwen3-0.6B",
  "model_type": "qwen3",
  "template": "qwen3",
  "tuner_type": "lora"
}
```

> [!key-insight] 不确定填什么就去翻 `args.json`
> 训练时用的什么基座、什么模板，部署时就照抄。`args.json` 是训练参数的"出生证明"。

## 4. 踩坑:方案一(model 留空)会直接报错

我实测过两种填法：

| 方案 | model 字段 | 结果 |
|---|---|---|
| 方案一 | **留空** | <font color="red">❌ 点部署直接报错</font> |
| 方案二 | 填 `Qwen/Qwen3-0.6B` | ✅ 正常 |

方案一报错信息(WebUI 进程崩):

```
TypeError: stat: path should be string, bytes, os.PathLike
or integer, not NoneType
  File ".../swift/ui/llm_infer/llm_infer.py", line 220, in ...
    os.path.exists(model)
```

> [!warning] 这是 WebUI 的 bug，不是你填错
> 命令行 `swift deploy --adapters <路径>`(**不填 model**)实测能成功——因为框架会自己从 `adapter_config.json` 里读出基座。但 **WebUI 没处理 model 为空的情况**，`os.path.exists(None)` 直接崩。
>
> **规避办法:用方案二，老老实实把基座填进 model 字段。**

## 5. 正确填法(本机实测，照抄即可)

| 字段 | 填什么 |
|---|---|
| 模型id或路径 | `Qwen/Qwen3-0.6B` |
| 模型类型 | `qwen3` |
| 模板 | `qwen3` |
| 合并LoRA | **不勾** |
| 推理框架 | `transformers` |
| adapter id或路径 | `/Users/melodycchen/ai-work/ms-swift/output/v1-20260602-121310/checkpoint-94` |
| 选择可用GPU | `cpu` |
| 端口 | 用界面显示的(如 8000) |

> [!key-insight] adapters 用**绝对路径**最稳
> WebUI 的工作目录不一定是你以为的那个，相对路径容易找不到。直接复制完整绝对路径。

填好点**"部署模型"**，日志出现 `Uvicorn running on http://0.0.0.0:<端口>` 就成了。

## 6. 等价的命令行(理解 WebUI 在干嘛)

WebUI 方案二，本质就是后台跑这条：

```bash
swift deploy \
  --model Qwen/Qwen3-0.6B \
  --adapters /Users/melodycchen/ai-work/ms-swift/output/v1-20260602-121310/checkpoint-94 \
  --infer_backend pt \
  --port 8000
```

> 部署成功后，服务里的 **model id 会变成 `Qwen3-0.6B`**(带了你的 LoRA)，而不是没微调时的 `Qwen3-0.6B-Base`。Postman 调用时 model 字段要填这个，详见 [[02 用 Postman 调用推理 API]]。

## 继续学习

- [[02 用 Postman 调用推理 API|用 Postman 调用推理 API]](部署成功后怎么调)
- [[01 ms-SWIFT WebUI 总览|ms-SWIFT WebUI 总览]](WebUI 整体地图)
- [[05 ms-SWIFT 推理命令详解|ms-SWIFT 推理命令详解]](命令行推理:pt vs vLLM)
