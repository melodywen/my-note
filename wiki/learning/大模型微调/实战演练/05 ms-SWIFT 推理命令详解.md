---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, 推理, infer, vllm, lora, mac, mps]
created: 2026-06-02
updated: 2026-06-02
---

# 05 ms-SWIFT 推理命令详解(用不用 vLLM、Mac 能不能跑)

> 本页是**实战演练篇**:[[04 ms-SWIFT 训练产物文件详解|训练产物]] 拿到后,用 `swift infer` 加载 LoRA 做推理。本页讲透两条常见推理命令的区别。一句话记住:**第一条是"原生后端直接推"(慢但通用、Mac 也能跑);第二条是"合并 LoRA + vLLM 加速推"(快但只认 NVIDIA,Mac 跑不了)。**

> [!warning] 先澄清一个超容易混的词:vLLM ≠ VL
> - **VL**(Vision Language)= 视觉多模态,指模型**能不能看图**,见 [[03.1 Qwen3 家族选型(VL 与 3.5)]]。
> - **vLLM** = 一个**推理加速引擎**(高性能跑模型的后端),和"看不看图"毫无关系。
> 本页讲的是 **vLLM**(加速引擎)。你那条命令里的 `--infer_backend vllm` 就是它。

## 0. 两条命令放一起对比

**命令 A:交互式命令行推理(原生后端)**
```bash
CUDA_VISIBLE_DEVICES=0 \
swift infer \
    --adapters output/vx-xxx/checkpoint-xxx \
    --stream true \
    --temperature 0 \
    --max_new_tokens 2048
```

**命令 B:merge-lora + vLLM 加速推理**
```bash
CUDA_VISIBLE_DEVICES=0 \
swift infer \
    --adapters output/vx-xxx/checkpoint-xxx \
    --stream true \
    --merge_lora true \              # ← 多了:把 LoRA 合并进基座
    --infer_backend vllm \           # ← 多了:用 vLLM 引擎加速
    --vllm_max_model_len 8192 \      # ← 多了:vLLM 的最大上下文长度
    --temperature 0 \
    --max_new_tokens 2048
```

> [!key-insight] 两条命令的差异就三行
> | 参数 | 命令 A | 命令 B | 作用 |
> |---|---|---|---|
> | `--merge_lora` | 无(默认 false) | **true** | 把 LoRA "补丁"合并进基座成一个完整模型,vLLM 才好加载 |
> | `--infer_backend` | 无(默认 pt) | **vllm** | 换推理引擎:`pt`=原生 PyTorch(通用慢),`vllm`=高性能(快) |
> | `--vllm_max_model_len` | 无 | **8192** | 仅 vLLM 用,限定最大上下文长度,影响显存预分配 |
>
> 其余参数两者一样:`--adapters`(LoRA 路径)、`--stream true`(流式输出)、`--temperature 0`(贪心解码,输出最确定/可复现)、`--max_new_tokens 2048`(最多生成 2048 个新 token)。

## 1. 为什么一条用 vLLM、一条不用?——速度 vs 通用性的取舍

> [!key-insight] 一句话:**A 图省事、B 图快**
> - **命令 A(不用 vLLM)**:用 ms-SWIFT 默认的 **PyTorch 原生后端(pt)**。加载简单、什么环境都能跑,但**推理慢**——适合训练完**快速验证一下效果**("模型学没学到东西")。
> - **命令 B(用 vLLM)**:换成 [[02 ms-SWIFT 安装部署|vLLM]] 高性能引擎,靠 PagedAttention、连续批处理等技术,**吞吐量高、生成快几倍**——适合**正式部署 / 大批量推理 / 压测**。

**为什么用 vLLM 之前要先 `--merge_lora`?**

LoRA 训出来是"补丁"(`adapter_model.safetensors`),推理时本需"基座 + 补丁"两部分拼着用。但 **vLLM 对动态加载 LoRA 支持有限**,最省心的方式是先把补丁**合并进基座**,得到一个独立完整模型,vLLM 直接加载这个完整模型即可。所以命令 B 把 `--merge_lora true` 和 `--infer_backend vllm` 配套使用。

> [!key-insight] 选哪条?
> - **刚训完,想问几句看效果** → **命令 A**(原生后端,简单)。
> - **要起服务 / 批量跑 / 追求速度** → **命令 B**(合并 + vLLM)。
> - 命令 A 的 `pt` 后端**功能最全、兼容性最好**;vLLM 快但有环境和硬件门槛(见下节)。

## 2. ★ NVIDIA 显卡 vs Mac:两条命令都能跑吗?

> [!important] <font color="red">核心结论</font>
> | | 命令 A(原生 pt 后端) | 命令 B(vLLM 加速) |
> |---|---|---|
> | **NVIDIA(CUDA)** | ✅ 能跑 | ✅ 能跑(vLLM 的主场) |
> | **Mac(Apple Silicon/MPS)** | ✅ 能跑(去掉 `CUDA_VISIBLE_DEVICES`) | ❌ **跑不了**,vLLM 不支持 MPS |

### 2.1 命令 A 在 Mac 上:能跑,但要改一处

去掉开头的 `CUDA_VISIBLE_DEVICES=0`(Mac 无 CUDA),其余照旧:

```bash
# Mac 版:删掉 CUDA_VISIBLE_DEVICES,会自动走 MPS
swift infer \
    --adapters output/vx-xxx/checkpoint-xxx \
    --stream true \
    --temperature 0 \
    --max_new_tokens 2048
```

> 推理比训练对 MPS 友好得多(不涉及反向传播那些缺失算子),所以**命令 A 在你的 M4 Pro 上通常能正常跑**,用来验证微调效果没问题。

### 2.2 命令 B 在 Mac 上:跑不了,原因如下

> [!warning] <font color="red">vLLM 目前不支持 Apple Silicon / MPS</font>
> vLLM 是为 **NVIDIA GPU(CUDA)** 深度优化的引擎(其核心 PagedAttention、CUDA kernel 都依赖 CUDA),官方主线**不支持 MPS 后端**。在 Mac 上加 `--infer_backend vllm` 会直接报错或无法安装。
>
> **Mac 上想加速怎么办?**
> - 老老实实用**命令 A 的 pt 后端**(够用,只是不如 vLLM 快)。
> - 或导出后用 Mac 友好的方案,如 **MLX**(苹果自家框架)、**llama.cpp / Ollama**(GGUF 量化)——但这些超出 ms-SWIFT `--infer_backend vllm` 的范畴,属于另起一套部署链路。

### 2.3 `CUDA_VISIBLE_DEVICES=0` 这行在两个平台的含义

- **NVIDIA**:指定**用第几号显卡**(0 = 第一张卡)。多卡机器上用它选卡或限定可见范围。
- **Mac**:**无意义,直接删掉**。Mac 没有 CUDA 设备,MPS 会自动启用,留着它不会选到任何卡。

## 3. 几个推理参数补充说明

| 参数 | 作用 | 备注 |
|---|---|---|
| `--stream true` | 流式输出,像打字一样逐字蹦 | 交互体验好;关掉则一次性返回整段 |
| `--temperature 0` | 采样温度,0 = 贪心解码 | **0 输出最确定、可复现**;调高(如 0.7)更有创造性但更随机 |
| `--max_new_tokens 2048` | 最多生成多少个新 token | 防止无限生成;按需调整 |
| `--vllm_max_model_len 8192` | vLLM 最大上下文长度 | **仅 vLLM 用**;设太大会多占显存,够用即可 |
| `--merge_lora true` | 合并 LoRA 进基座 | 合并后也可单独用 `swift export` 持久化,见 [[03 ms-SWIFT 测试运行示例]] §3 |

## 4. 验证微调效果的正确姿势

> [!key-insight] 推理不只是"能跑",而是"对比看效果"
> 想知道微调到底有没有用,**同一个问题分别问原始模型和微调后模型**,看回答差异:
> ```bash
> # 微调后(加 --adapters)
> swift infer --adapters output/vx-xxx/checkpoint-xxx --stream true
> # 原始模型(不加 --adapters)
> swift infer --model Qwen/Qwen3-0.6B --stream true
> ```
> 比如这次训了 `self-cognition`,就问"你是谁",看微调后会不会答"swift-robot"。要量化对比,用 `swift eval`(见 [[03 ms-SWIFT 测试运行示例]] §4)。

## 继续学习

- [[04 ms-SWIFT 训练产物文件详解|训练产物文件详解]](推理加载的 checkpoint 从哪来)
- [[03 ms-SWIFT 测试运行示例|ms-SWIFT 测试运行示例]](训/推/评/部署全流程命令)
- [[03.1 Qwen3 家族选型(VL 与 3.5)|Qwen3 家族选型]](别把 vLLM 和 VL 搞混)
- [[02 ms-SWIFT 安装部署|ms-SWIFT 安装部署]](vLLM 怎么装)
