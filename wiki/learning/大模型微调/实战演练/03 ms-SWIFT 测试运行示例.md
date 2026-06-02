---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, 示例, sft, infer, lora]
created: 2026-06-02
updated: 2026-06-02
---

# 03 ms-SWIFT 测试运行示例

> 本页是**实战演练篇**:[[02 ms-SWIFT 安装部署|装好 ms-SWIFT]] 之后,跑几个最小示例确认环境真能用。一句话记住:**`swift sft` 训、`swift infer` 推、`swift eval` 评、`swift deploy` 部署 —— 先用小模型 + 内置数据集跑通,再换自己的模型和数据。**

## 0. 跑示例前的准备

```bash
conda activate swift            # 进入装好 ms-SWIFT 的环境
swift --help                    # 能打印帮助说明装好了
```

> [!key-insight] 国内下载模型/数据慢?先设魔搭源
> ms-SWIFT 默认可从 ModelScope(魔搭)拉模型,国内速度快。设置环境变量后,示例里的模型会自动从魔搭下载:
> ```bash
> export USE_MODELSCOPE_HUB=1     # 走魔搭下载(国内推荐)
> # 或显式指定:swift sft --model Qwen/Qwen2.5-0.5B-Instruct --model_type qwen2_5
> ```

## 1. 完整微调示例(`swift sft`)

一条贴近实战的 LoRA 微调命令:微调 **Qwen3-4B**,混合三个数据集(中文 + 英文 + 自我认知),并给模型设定身份(`swift-robot`)。**显存占用约 13GB**,一张消费级卡(如 RTX 3090/4090)即可跑。

### CUDA(NVIDIA 显卡)运行指令

```bash
# 显存约 13GB
CUDA_VISIBLE_DEVICES=0 \
swift sft \
    --model Qwen/Qwen3-4B-Instruct-2507 \
    --train_type lora \
    --dataset 'AI-ModelScope/alpaca-gpt4-data-zh#500' \
              'AI-ModelScope/alpaca-gpt4-data-en#500' \
              'swift/self-cognition#500' \
    --torch_dtype bfloat16 \
    --num_train_epochs 1 \
    --per_device_train_batch_size 1 \
    --per_device_eval_batch_size 1 \
    --learning_rate 1e-4 \
    --lora_rank 8 \
    --lora_alpha 32 \
    --target_modules all-linear \
    --gradient_accumulation_steps 16 \
    --eval_steps 50 \
    --save_steps 50 \
    --save_total_limit 2 \
    --logging_steps 5 \
    --max_length 2048 \
    --output_dir output \
    --warmup_ratio 0.05 \
    --dataloader_num_workers 4 \
    --model_author swift \
    --model_name swift-robot
```

### Mac(Apple Silicon / MPS)运行指令

Mac 没有 NVIDIA 显卡,走苹果的 **MPS** 后端。相比 CUDA 版有三处必须改:

```bash
# 1) 去掉 CUDA_VISIBLE_DEVICES(Mac 无 CUDA)
swift sft \
    --model Qwen/Qwen3-4B-Instruct-2507 \
    --train_type lora \
    --dataset 'AI-ModelScope/alpaca-gpt4-data-zh#500' \
              'AI-ModelScope/alpaca-gpt4-data-en#500' \
              'swift/self-cognition#500' \
    --torch_dtype float16 \
    --num_train_epochs 1 \
    --per_device_train_batch_size 1 \
    --per_device_eval_batch_size 1 \
    --learning_rate 1e-4 \
    --lora_rank 8 \
    --lora_alpha 32 \
    --target_modules all-linear \
    --gradient_accumulation_steps 16 \
    --eval_steps 50 \
    --save_steps 50 \
    --save_total_limit 2 \
    --logging_steps 5 \
    --max_length 2048 \
    --output_dir output \
    --warmup_ratio 0.05 \
    --dataloader_num_workers 0 \
    --model_author swift \
    --model_name swift-robot
```

> [!key-insight] Mac 版相比 CUDA 版改了哪三处、为什么
> | 改动 | CUDA | Mac | 原因 |
> |---|---|---|---|
> | **设备指定** | `CUDA_VISIBLE_DEVICES=0` | **删掉** | Mac 无 CUDA 设备,MPS 会自动启用 |
> | **精度** | `--torch_dtype bfloat16` | `--torch_dtype float16` | MPS 对 bfloat16 支持不完整,易报错;用 float16 更稳 |
> | **数据加载进程** | `--dataloader_num_workers 4` | `--dataloader_num_workers 0` | macOS 多进程 DataLoader 常出问题,设 0 用主进程更稳 |
>
> 另外 **4B 模型在 Mac 上很吃内存**(建议 32GB 以上统一内存),且训练速度比 NVIDIA 卡慢很多 —— Mac 更适合**验证流程能跑通**,真正训练还是上 CUDA。内存吃紧可把 `--max_length` 调小(如 1024)。

> [!key-insight] 命令里的关键参数在干嘛
> | 参数 | 含义 |
> |---|---|
> | `--model` | 微调的基座模型,这里是 [[Qwen]] 4B 指令版 |
> | `--train_type lora` | 用 [[03 LoRA 与 QLoRA\|LoRA]] 高效微调,显存友好 |
> | `--dataset '...#500' '...' '...'` | 同时挂载多个数据集,各取前 500 条;含中/英 alpaca + `self-cognition`(教模型认识自己) |
> | `--lora_rank 8` / `--lora_alpha 32` | LoRA 的秩与缩放系数,控制可训练参数量和学习强度 |
> | `--target_modules all-linear` | 对**所有线性层**插 LoRA,覆盖更全、效果更好 |
> | `--gradient_accumulation_steps 16` | 梯度累积,等效放大 batch(1×16=16),小显存也能稳训 |
> | `--eval_steps` / `--save_steps` | 每 50 步评估/保存一次 checkpoint |
> | `--save_total_limit 2` | 最多保留 2 个 checkpoint,省磁盘 |
> | `--warmup_ratio 0.05` | 前 5% 步数学习率预热,训练更稳 |
> | `--model_author` / `--model_name` | 配合 `self-cognition` 数据集,把模型身份设成 `swift / swift-robot`,问它"你是谁"会这么答 |
>
> 训练完成后,LoRA 权重保存在 `output/vx-xxxx/checkpoint-xxx/` 目录下。


## 2. 推理验证(`swift infer`)

训练完用微调后的权重做推理,看回答是否符合预期。

**命令行交互式推理:**

```bash
swift infer \
  --adapters output/vx-xxxx/checkpoint-xxx \
  --stream true \
  --max_new_tokens 512
```

> `--adapters` 填上一步训出来的 checkpoint 路径;`--stream true` 流式输出(像聊天一样逐字蹦)。启动后直接在终端输入问题即可对话。

**直接推理原始模型(不加载 LoRA):**

```bash
swift infer --model Qwen/Qwen2.5-0.5B-Instruct --stream true
```

> [!key-insight] 验证微调效果的正确姿势
> 想知道"微调到底有没有用",就**同一个问题分别问原始模型和微调后模型**,对比回答差异。这正是 [[01 Qwen3 高效微调环境准备\|实战篇]] 里"验"这一环的核心。要量化对比,见下方第 4 节评测。

## 3. 合并 LoRA 权重(`swift export`)

LoRA 训出来的是"补丁",推理时要和基座模型一起加载。想得到一个**独立完整的模型**(方便部署/分发),把 LoRA 合并进基座:

```bash
swift export \
  --adapters output/vx-xxxx/checkpoint-xxx \
  --merge_lora true \
  --output_dir output/merged
```

> 合并后 `output/merged` 就是一个完整模型,可直接用 `swift infer --model output/merged` 加载,不再需要 `--adapters`。

## 4. 评测(`swift eval`)

用 [[01 EvalScope|EvalScope]] 对模型跑标准评测集,量化打分:

```bash
swift eval \
  --model output/merged \
  --eval_dataset ceval \
  --eval_limit 100
```

> `--eval_dataset` 选评测集(如中文的 `ceval`、`cmmlu`);`--eval_limit` 限制条数,先小规模试跑。**微调前后各跑一次,对比分数**就能看出微调收益。

## 5. 部署为 API 服务(`swift deploy`)

把模型起成一个 OpenAI 兼容的 HTTP 接口,供其他程序调用:

```bash
swift deploy \
  --model output/merged \
  --infer_backend vllm \
  --port 8000
```

> 启动后即可用标准 OpenAI 客户端访问 `http://localhost:8000/v1`。`--infer_backend vllm` 用 [[02 ms-SWIFT 安装部署|安装篇]]里装的 vLLM 加速;没装 vLLM 可去掉该参数用默认后端。

## 6. 用 Python 脚本调用(进阶)

不想用命令行,也可在 Python 里调 ms-SWIFT 的 API,适合集成进自己的流程:

```python
from swift.llm import sft_main, TrainArguments

sft_main(TrainArguments(
    model='Qwen/Qwen2.5-0.5B-Instruct',
    train_type='lora',
    dataset=['AI-ModelScope/alpaca-gpt4-data-zh#500'],
    num_train_epochs=1,
    output_dir='output',
))
```

> 命令行参数和 `TrainArguments` 的字段基本一一对应。先用 CLI 跑通、确认参数没问题,再搬到脚本里做自动化。

## 跑示例的推荐顺序

> [!key-insight] 第一次上手照这个顺序走
> 1. **`swift infer` 原始模型** —— 先确认模型能加载、能对话(环境 OK)。
> 2. **`swift sft` 小数据微调** —— 用 `#500` 小切片快速训一次,确认训练链路通。
> 3. **`swift infer --adapters`** —— 加载刚训的 LoRA,问相同问题对比效果。
> 4. **`swift export --merge_lora`** —— 合并成完整模型。
> 5. **`swift eval` / `swift deploy`** —— 量化评测 / 起服务,按需选用。
>
> 全程用 **0.5B 小模型 + 几百条数据**,几分钟就能跑完一轮,验证完再换大模型和真实数据集。

## 继续学习

- [[02 ms-SWIFT 安装部署|ms-SWIFT 安装部署]](还没装的先看这篇)
- [[04 ms-SWIFT|ms-SWIFT(魔搭生态全家桶)]](框架全流程能力总览)
- [[01 EvalScope|EvalScope(大模型评测框架)]](第 4 步评测用到)
- [[01 Qwen3 高效微调环境准备|Qwen3 高效微调环境准备]](实战环境四件套总览)
