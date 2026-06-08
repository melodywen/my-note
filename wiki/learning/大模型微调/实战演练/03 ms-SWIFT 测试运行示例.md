---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, 示例, sft, infer, lora, qwen3, qwen3-vl, qwen3.5, 多模态]
created: 2026-06-02
updated: 2026-06-02
---

# 03 ms-SWIFT 测试运行示例

> 本页是**实战演练篇**:[[02 ms-SWIFT 安装部署|装好 ms-SWIFT]] 之后,跑几个最小示例确认环境真能用。一句话记住:**`swift sft` 训、`swift infer` 推、`swift eval` 评、`swift deploy` 部署 —— 先用小模型 + 内置数据集跑通,再换自己的模型和数据。**
>
> 📖 **官方参考手册(快速开始)**:https://swift.readthedocs.io/zh-cn/latest/GetStarted/Quick-start.html —— 本页示例命令以该手册为基准。

> [!warning] 版本差异:`--train_type` 已改名为 `--tuner_type`
> 老教程/旧版 ms-SWIFT(3.x)用 **`--train_type lora`**;但 **4.2.x 版本已把该参数改名为 `--tuner_type`**(默认值就是 `lora`)。本机实测 **4.2.3** 版本,用 `--train_type` 会直接报错:
> ```
> ValueError: remaining_argv: ['--train_type', 'lora']
> ```
> 官方手册当前示例也已统一改用 `--tuner_type`。下文命令均已采用新参数名。查看自己的版本:`pip show ms-swift`。

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

> 以下为**官方手册当前示例命令**(已用新参数名 `--tuner_type`)。

```bash
# 显存约 13GB,单卡 3090/4090 可跑
CUDA_VISIBLE_DEVICES=0 \
swift sft \
    --model Qwen/Qwen3-4B-Instruct-2507 \
    --tuner_type lora \
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

Mac 没有 NVIDIA 显卡,走苹果的 **MPS** 后端。相比 CUDA 版有几处必须改。下面是**本机(M4 Pro / 48GB)实测可跑通**的版本:

```bash
# 注意:直接敲 swift 可能调到系统 /usr/bin/swift,建议用 conda 环境的绝对路径
# 例: /opt/homebrew/Caskroom/miniconda/base/envs/ms-swift/bin/swift sft ...
swift sft \
    --model Qwen/Qwen3-0.6B \
    --tuner_type lora \
    --dataset 'AI-ModelScope/alpaca-gpt4-data-zh#500' \
              'AI-ModelScope/alpaca-gpt4-data-en#500' \
              'swift/self-cognition#500' \
    --torch_dtype float32 \
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

> [!key-insight] Mac 版相比 CUDA 版改了哪几处、为什么
> | 改动 | CUDA | Mac | 原因 |
> |---|---|---|---|
> | **设备指定** | `CUDA_VISIBLE_DEVICES=0` | **删掉** | Mac 无 CUDA 设备,MPS 会自动启用 |
> | **模型大小** | `Qwen3-4B-Instruct-2507` | **`Qwen3-0.6B`** | 4B 在 Mac 上很慢且吃内存;0.6B(float32 仅约 2.4GB)练手轻松,验证流程足够 |
> | **精度** | `--torch_dtype bfloat16` | **`--torch_dtype float32`** | MPS 对 bfloat16 支持差(算子常缺失报错),float16 训练又易 NaN,**float32 最稳** |
> | **数据加载进程** | `--dataloader_num_workers 4` | `--dataloader_num_workers 0` | macOS 多进程 DataLoader 常出问题,设 0 用主进程更稳 |
> | **参数名** | — | `--tuner_type`(非 `--train_type`) | 见本页顶部版本差异提示 |
>
> 另外 **Mac 上 MPS 跑训练本身就容易踩算子坑** —— ms-SWIFT 没针对 MPS 做完整适配,即使类型选对,也可能卡在某个不支持的算子上。Mac 更适合**验证流程能跑通**,真正训练还是上 CUDA(`bfloat16` + NVIDIA 才是 ms-SWIFT 的主力场景)。

> [!tip] `swift` 命令找不到 / 调错了?(`No such file or directory` / 用到系统 swift)
> macOS 自带一个 `/usr/bin/swift`(那是 Apple 的 Swift 语言编译器),若它在 PATH 里排在 conda 环境前面,敲 `swift sft` 会调错,报 `unable to invoke subcommand: swift-sft`。两种解法:
> - **临时**:用绝对路径 `/opt/homebrew/Caskroom/miniconda/base/envs/ms-swift/bin/swift sft ...`
> - **永久**:在 `~/.zshrc` 里把 conda 环境 bin 放到 PATH 最前 `export PATH="/opt/homebrew/Caskroom/miniconda/base/envs/ms-swift/bin:$PATH"`,然后 `source ~/.zshrc`

> [!key-insight] 每个参数逐一解释(一个都不漏)
> | 参数 | 取值 | 单独解释 |
> |---|---|---|
> | `--model` | `Qwen/Qwen3-4B-Instruct-2507` | 要微调的**基座模型** ID,这里是 [[Qwen]] 3 代 4B 指令版(2507 是版本号),会从魔搭/HF 自动下载 |
> | `--tuner_type`(旧名 `--train_type`) | `lora` | **微调方式**用 [[03 LoRA 与 QLoRA\|LoRA]](只训练插入的小矩阵,省显存);填 `full` 则是全参数微调。⚠️ 4.2.x 已从 `--train_type` 改名为 `--tuner_type`,见本页顶部提示 |
> | `--dataset`(第 1 个) | `AI-ModelScope/alpaca-gpt4-data-zh#500` | **中文** alpaca-gpt4 指令数据集,`#500` 表示只取前 500 条 |
> | `--dataset`(第 2 个) | `AI-ModelScope/alpaca-gpt4-data-en#500` | **英文** alpaca-gpt4 指令数据集,同样取前 500 条;与中文一起喂保证中英能力 |
> | `--dataset`(第 3 个) | `swift/self-cognition#500` | **自我认知**数据集,教模型回答"你是谁/谁造的",取前 500 条;配合下方 `model_author/model_name` 生效 |
> | `--torch_dtype` | `bfloat16`(CUDA)/`float32`(Mac) | 模型权重的**计算精度**;CUDA 上用 bfloat16 省显存又稳;Mac/MPS 对 bfloat16 支持差、float16 易 NaN,**建议 float32** |
> | `--num_train_epochs` | `1` | **训练轮数**,把数据集完整过几遍,这里过 1 遍(练手够用) |
> | `--per_device_train_batch_size` | `1` | **每张卡训练**时一次喂几条样本,显存小就设 1 |
> | `--per_device_eval_batch_size` | `1` | **每张卡评估**时一次喂几条样本,同样设 1 |
> | `--learning_rate` | `1e-4` | **学习率**,即每步参数更新的幅度;LoRA 微调常用 1e-4 量级 |
> | `--lora_rank` | `8` | **LoRA 的秩 r**,即插入的低秩矩阵维度;越大可训练参数越多、表达力越强也越吃显存,8 是常用小值 |
> | `--lora_alpha` | `32` | **LoRA 缩放系数**,实际作用强度≈alpha/rank(32/8=4);配合 rank 控制 LoRA 影响力度 |
> | `--target_modules` | `all-linear` | **给哪些层插 LoRA**,`all-linear` 表示所有线性层都插,覆盖最全、效果通常更好 |
> | `--gradient_accumulation_steps` | `16` | **梯度累积步数**,累积 16 步再更新一次参数,等效 batch=1×16=16;小显存模拟大 batch 的关键 |
> | `--eval_steps` | `50` | 每训练 **50 步**在验证集上评估一次 |
> | `--save_steps` | `50` | 每训练 **50 步**保存一次 checkpoint(与 eval_steps 对齐) |
> | `--save_total_limit` | `2` | **最多保留 2 个** checkpoint,超出自动删旧的,省磁盘 |
> | `--logging_steps` | `5` | 每 **5 步**打印一次训练日志(loss 等),方便实时观察 |
> | `--max_length` | `2048` | 单条样本的**最大 token 长度**,超过会截断;越大越吃显存 |
> | `--output_dir` | `output` | 训练**产物输出目录**(LoRA 权重、日志、checkpoint 都放这) |
> | `--warmup_ratio` | `0.05` | **学习率预热比例**,前 5% 的训练步里学习率从 0 慢慢升到设定值,开头训练更稳 |
> | `--dataloader_num_workers` | `0`(Mac)/`4`(CUDA) | **数据加载的子进程数**,越多读数据越快;macOS 多进程易出错故设 0,Linux/CUDA 设 4 |
> | `--model_author` | `swift` | 配合 `self-cognition`,设定模型的**作者/创建者**身份,问"谁造的你"会答 swift |
> | `--model_name` | `swift-robot` | 配合 `self-cognition`,设定模型的**名字**,问"你是谁"会答 swift-robot |
>
> 训练完成后,LoRA 权重保存在 `output/vx-xxxx/checkpoint-xxx/` 目录下。

> [!key-insight] 深入理解 `gradient_accumulation_steps` 与训练步数
>
> ### 什么是梯度累积?
>
> 正常训练时,每处理一个 batch 就会计算梯度并**立即更新参数**(做一次 optimizer step)。但显存不够大时,batch_size 只能设很小(比如 1),这会导致梯度估计噪声大、训练不稳。
>
> **梯度累积**的思路:先连续跑 N 个 mini-batch,把每次算出的梯度**累加起来**,攒够 N 步后再统一做一次参数更新。效果上等价于用了 N 倍大的 batch,但**显存只占一个 mini-batch 的量**。
>
> ### 核心公式:等效批量大小
>
> ```
> effective_batch_size = per_device_train_batch_size × gradient_accumulation_steps × num_gpus
> ```
>
> 以本页示例为例:
> ```
> effective_batch_size = 1 × 16 × 1(单卡) = 16
> ```
> 即:虽然每次只喂 1 条样本(显存只需承担 1 条的开销),但攒 16 次梯度后才更新一次参数,**训练效果等同于 batch_size=16**。
>
> ### 核心公式:总训练步数(optimizer steps)
>
> ```
> total_optimizer_steps = ⌈total_samples / effective_batch_size⌉ × num_train_epochs
> ```
>
> 以本页示例为例(三个数据集各 500 条,共 1500 条,1 个 epoch):
> ```
> total_optimizer_steps = ⌈1500 / 16⌉ × 1 = 94 步
> ```
>
> **注意区分两种"步":**
> | 概念 | 含义 | 本例数量 |
> |---|---|---|
> | **forward step**(前向步) | 每喂一个 mini-batch 就算一步 | 1500 步 |
> | **optimizer step**(优化器步/参数更新步) | 累积够 `gradient_accumulation_steps` 次后做一次参数更新 | 94 步 |
>
> **ms-SWIFT / HuggingFace Trainer 里所有 `xxx_steps` 参数(如 `logging_steps`、`eval_steps`、`save_steps`)计数的都是 optimizer step,不是 forward step。**
>
> ### 各 `xxx_steps` 参数与梯度累积的关系
>
> | 参数 | 本例取值 | 实际含义 |
> |---|---|---|
> | `logging_steps=5` | 每 5 次**参数更新**打印一次日志 → 实际每处理 5×16=80 条样本打印一次 |
> | `eval_steps=50` | 每 50 次**参数更新**评估一次 → 实际每处理 50×16=800 条样本评估一次 |
> | `save_steps=50` | 每 50 次**参数更新**保存一次 → 同上 |
>
> ### 怎么选 `gradient_accumulation_steps`?
>
> | 场景 | 建议 |
> |---|---|
> | 显存够大,能直接开大 batch | 不需要累积,设 1 即可 |
> | 显存小(如消费级卡跑大模型) | `per_device_train_batch_size=1`,靠 `gradient_accumulation_steps` 把等效 batch 拉到 8~32 |
> | 多卡训练 | 等效 batch = batch_size × accumulation × 卡数,注意别让等效 batch 过大(>64 时 LR 需配合调整) |
>
> **经验法则**:等效 batch_size 在 **8~32** 之间通常是微调的甜区;太小梯度噪声大,太大收敛变慢且泛化可能变差。本例 `1×16=16` 正好在这个范围。
>
> ### 一张图理解整个训练循环
>
> ```
> ┌─ forward step 1 ─┐
> │  喂 1 条样本      │ → 算梯度,累加到缓冲区
> ├─ forward step 2 ─┤
> │  喂 1 条样本      │ → 算梯度,继续累加
> ├─      ...        ─┤
> ├─ forward step 16 ─┤
> │  喂 1 条样本      │ → 算梯度,累加完毕
> └──────────────────┘
>         ↓
>   ★ optimizer step ★  ← 用累积的梯度更新参数(这才算"1步")
>         ↓
>   logging_steps / eval_steps / save_steps 都在数这个
> ```
>
> ### 小结
>
> `gradient_accumulation_steps` 是**显存不够时模拟大 batch 训练的核心手段**。理解它的关键:
> 1. 它乘以 `per_device_train_batch_size`(再乘卡数)= 等效 batch size
> 2. 所有 `xxx_steps` 参数都按 optimizer step(参数更新次数)计数,不是按样本数
> 3. 调大它不会增加显存,但会让每个 optimizer step 花更长时间(因为要多跑几次前向+反向)


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
    tuner_type='lora',
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

## 7. Qwen3 家族怎么选:带不带 VL、3 还是 3.5

> 跑示例时 `--model` 填哪个,直接决定了能力边界和命令写法。**带不带 VL(能否看图/看视频)、Qwen3 与 Qwen3.5 的架构差异、以及选型速查**,已单独拆成一篇:
>
> 👉 **[[03.1 Qwen3 家族选型(VL 与 3.5)|Qwen3 家族选型:带不带 VL、3 还是 3.5]]**

## 8. 训练时怎么盯显卡?

> 训练跑起来后,要监控显存/利用率/温度。`nvidia-smi`、`nvitop` 等工具的用法已单独拆成一篇:
>
> 👉 **[[03.2 显卡监控工具|显卡 / 算力监控工具]]**

## 本机实测踩坑小结(M4 Pro / 48GB / ms-SWIFT 4.2.3)

> [!key-insight] 这次跑通前踩的几个坑(按出现顺序)
> 1. **`swift-sft: No such file or directory`** —— PATH 里系统 `/usr/bin/swift`(Apple 的 Swift 编译器)排在 conda 环境前面,调错了命令。→ 用 conda 环境绝对路径,或把环境 bin 放 PATH 最前。
> 2. **`ValueError: remaining_argv: ['--train_type', 'lora']`** —— 4.2.3 已把 `--train_type` 改名为 `--tuner_type`(默认就是 lora,也可直接删掉这行)。
> 3. **bfloat16 在 Mac 上不靠谱** —— MPS 对 bf16 算子支持不全;float16 训练易 NaN。最终用 **`float32`** 才稳。
> 4. **4B 在 Mac 上太重** —— 换成 **`Qwen3-0.6B`** 练手,float32 仅约 2.4GB,M4 Pro 轻松跑。
> 5. **`Requirement already satisfied` 不是错** —— 那只是 pip 跳过已装依赖的正常日志,只需关注 `ERROR`/`Conflict` 行。
>
> 一句话:**Mac 是用来验证流程能跑通的,真正训练上 CUDA。**

## 继续学习

- [[02 ms-SWIFT 安装部署|ms-SWIFT 安装部署]](还没装的先看这篇)
- [[04 ms-SWIFT|ms-SWIFT(魔搭生态全家桶)]](框架全流程能力总览)
- [[01 EvalScope|EvalScope(大模型评测框架)]](第 4 步评测用到)
- [[01 Qwen3 高效微调环境准备|Qwen3 高效微调环境准备]](实战环境四件套总览)
