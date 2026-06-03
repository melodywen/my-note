---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, 训练产物, checkpoint, lora, loss, 日志, tensorboard]
created: 2026-06-02
updated: 2026-06-02
---

# 04 ms-SWIFT 训练产物文件详解(output 目录怎么看)

> 本页是**实战演练篇**:[[03 ms-SWIFT 测试运行示例|跑完 `swift sft`]] 后,`output/` 里会冒出一堆文件,本页教你**哪些值得看、怎么看**。一句话记住:**训练好不好看 `trainer_state.json` + `images/` 曲线;模型本体是 `adapter_model.safetensors`(LoRA 权重);其余多是"续训用的存档",日常不用管。**
>
> 本文以本机实测产物为例:`output/v1-20260602-121310/`(Qwen3-0.6B + LoRA,1 epoch / 94 步 / 1500 条数据)。

> [!important] <font color="red">【初学者:平时就盯这 4 样,其余先别管】</font>
> 产物文件很多,但**新手日常只需要关注下面 4 个**,看懂它们就够判断"这次训练成不成":
> 1. <font color="red">**loss(损失)**</font> —— **最重要**。整体**往下降**就对了。看 `images/train_loss.png` 一眼即可。详见 [[#1.1 【初学者必看】loss 怎么看好坏|§1.1]]。
> 2. <font color="red">**learning_rate(学习率)**</font> —— 看 `images/train_learning_rate.png` 是不是"**先升后降**"的形状;出问题时它是最该先调的旋钮。详见 [[#1.2 【初学者必看】学习率(learning_rate)怎么看好坏|§1.2]]。
> 3. <font color="red">**token_acc(准确率)**</font> —— 整体**往上升**为好,辅助佐证 loss。
> 4. <font color="red">**adapter_model.safetensors**</font> —— 你的**训练成果本体**(LoRA 权重),推理就加载它(见 §4)。
>
> 其余的 `optimizer.pt`、`scheduler.pt`、`rng_state.pth`、`training_args.bin` 等,**新手阶段完全可以忽略**(只是断点续训用的存档)。

## 0. 整体目录长什么样

```
output/
├── v0-20260602-115446/          ← 第 0 次运行(每跑一次 swift sft 生成一个 vN 目录)
└── v1-20260602-121310/          ← 第 1 次运行(本文以这个为例)
    ├── args.json                ← ① 本次训练的完整参数快照
    ├── logging.jsonl            ← ② 训练日志(每步 loss 等,逐行 JSON)
    ├── images/                  ← ③ 训练曲线图(loss/lr/acc 等 PNG)★最直观
    ├── runs/                    ← ④ TensorBoard 事件文件
    ├── checkpoint-50/           ← 第 50 步的存档(中途快照)
    └── checkpoint-94/           ← 第 94 步的存档(最后一步)★最终模型在这
        ├── adapter_model.safetensors  ← ⑤ LoRA 权重 ★这才是"训练成果本体"
        ├── adapter_config.json        ← ⑥ LoRA 结构配置
        ├── trainer_state.json         ← ⑦ 训练全过程指标 ★复盘最重要
        ├── optimizer.pt / scheduler.pt / rng_state.pth  ← ⑧ 续训用存档(占地方,平时不看)
        ├── args.json / additional_config.json / training_args.bin  ← 各种参数备份
        └── README.md                  ← 自动生成的模型卡
```

> [!key-insight] 先记住"三类文件"
> | 类别 | 文件 | 作用 | 看不看 |
> |---|---|---|---|
> | **成果本体** | `adapter_model.safetensors` + `adapter_config.json` | 微调真正产出的 LoRA 权重,推理/合并就用它 | 不"看"内容,但**最重要**,推理靠它 |
> | **复盘材料** | `trainer_state.json`、`logging.jsonl`、`images/`、`runs/` | 训得好不好、loss 降没降,全看这些 | ★**重点看** |
> | **续训存档** | `optimizer.pt`、`scheduler.pt`、`rng_state.pth` | 断点续训用,恢复优化器/随机数状态 | 平时不看,占磁盘大头 |

## 1. ★ trainer_state.json —— 复盘训练的"病历本"(最该看)

这是**最值得打开**的文件,记录了训练全过程的逐步指标。打开 `checkpoint-94/trainer_state.json`,关键字段:

```json
{
  "epoch": 1.0,                  // 训了几轮(这里 1 轮跑完)
  "global_step": 94,            // 总共走了 94 步
  "max_steps": 94,
  "log_history": [               // ★核心:每隔 logging_steps 记录一次
    {"step": 1,  "loss": 1.846, "grad_norm": 3.74, "learning_rate": 2e-05, "token_acc": 0.618},
    {"step": 5,  "loss": 1.941, "grad_norm": 3.01, "learning_rate": 1e-04, "token_acc": 0.587},
    ...
    {"step": 90, "loss": 1.422, "grad_norm": 1.18, "learning_rate": 5e-07, "token_acc": 0.648}
  ],
  "total_flos": 5.0e14,          // 总浮点运算量
  "best_model_checkpoint": null  // 若开了按指标选优,会指向最好的 checkpoint
}
```

> [!key-insight] `log_history` 里四个数怎么读(判断训练健不健康)
> | 字段 | 含义 | 健康表现 | 你这次的实测 |
> |---|---|---|---|
> | **loss** | 训练损失,模型预测和答案的差距 | **总体往下降** | 1.84 → 1.42,**降了,正常** ✅ |
> | **grad_norm** | 梯度范数,反映参数更新幅度 | 平稳、不爆炸(不出现极大值/NaN) | 3.7 → 1.2,**逐渐平稳,健康** ✅ |
> | **learning_rate** | 学习率 | 按调度先升(warmup)后降 | 2e-5→1e-4→5e-7,**预热后衰减,符合预期** ✅ |
> | **token_acc** | token 级准确率,预测对的 token 占比 | **总体往上升** | 0.59 → 0.65,**略升,正常** ✅ |
>
> ⚠️ **本次是 0.6B 小模型 + 500 条 ×3 数据练手**,loss 只从 1.84 降到 1.42、acc 0.6 出头,属正常——**目的是验证流程跑通,不是追求效果**。真要好效果得换大模型 + 更多数据 + 更多 epoch。

### 1.1 <font color="red">【初学者必看】loss 怎么看好坏</font>

> [!key-insight] loss(损失)= 模型答得有多"错",**越低越好**
> loss 衡量"模型预测"和"标准答案"的差距。训练的本质就是**不断调参数,把 loss 往下压**。

**怎么判断好坏?核心看趋势,不看绝对值:**

| loss 的表现 | 说明 | 好 / 坏 |
|---|---|---|
| **整体往下降**(允许小幅抖动) | 模型在学到东西 | ✅ 好,这是理想状态 |
| **一直横着不动**(比如卡在 2.0 不降) | 没学进去:学习率太小 / 数据有问题 / 参数没解冻 | ❌ 坏 |
| **先降后又一路回升** | 典型**过拟合**:把训练集背下来了,泛化变差 | ⚠️ 警惕,见 [[05 灾难性遗忘]] |
| **突然变成 NaN / inf 或剧烈爆炸** | 数值崩了:学习率太大 / 精度问题(如 Mac 上用 float16) | ❌ 坏,得停下改参数 |
| **抖动剧烈但总体向下** | 正常,小数据 / 小 batch 时尤其明显 | ✅ 可接受 |

> [!key-insight] 三个常见疑问
> 1. **loss 降到多少算"够好"?** —— **没有统一标准**。不同模型/数据/任务的 loss 基准完全不同,所以**只比趋势(降没降)、不比绝对值**。你这次 1.42 不代表"好或坏",只代表"在降"。
> 2. **loss 抖来抖去正常吗?** —— 正常。每步只看 1 条(batch=1)样本,难易不同 loss 自然忽高忽低,**看整体趋势**别盯单点。
> 3. **要不要等 loss 降到 0?** —— **不要**。loss=0 意味着把训练集完全背死(严重过拟合),反而没用。能在新问题上答得好才是目标。

### 1.2 <font color="red">【初学者必看】学习率(learning_rate)怎么看好坏</font>

> [!key-insight] 学习率 = 每一步"迈多大步子"调参数
> 太大→步子太猛,容易"迈过头",loss 震荡甚至爆炸(NaN);太小→步子太碎,学得极慢甚至卡住不降。

**学习率本身不是越高/越低越好,关键看两点:**

**① 看它的"形状"对不对**(这是产物里 `learning_rate` 字段 / `train_learning_rate.png` 该呈现的):

```
学习率
  │        ╱‾‾‾‾╲___
  │      ╱          ╲___          ← 你这次:2e-5 →(升到)1e-4 →(降到)5e-7
  │    ╱                ╲__
  └──────────────────────────► 步数
     ↑warmup预热    ↑余弦衰减
```

- **前段上升(warmup 预热)**:由 `--warmup_ratio 0.05` 控制,开头 5% 的步数里学习率从很小慢慢升到设定值(1e-4)。**为什么?** 模型刚开始参数还很"乱",一上来就大步走容易崩,先小步热身更稳。
- **后段下降(衰减)**:升到峰值后逐渐降到接近 0。**为什么?** 训练后期接近最优解,要小步微调,避免在最优点附近来回跳。
- ✅ **这个"先升后降"的形状出现了,就说明学习率调度正常工作**。你这次完全符合。

**② 看它和 loss 的"联动"是否健康:**

| 现象 | 多半是学习率的什么问题 | 怎么调 |
|---|---|---|
| loss 爆炸 / 变 NaN | 学习率**太大** | 调小,如 1e-4 → 5e-5 / 2e-5 |
| loss 几乎不降、横线 | 学习率**太小**(或数据/解冻问题) | 调大,如 1e-5 → 1e-4 |
| loss 平稳下降 | 学习率**合适** ✅ | 不用动 |

> [!key-insight] 初学者记住:学习率是"最该先调"的旋钮
> 微调出问题,**90% 先怀疑学习率**。LoRA 微调常用 **1e-4 量级**(你这次就是),全参数微调要小得多(1e-5 量级)。不确定时,**先用别人验证过的默认值,别自己乱设**。

### 1.3 epoch 是什么?需要关心吗?

> [!key-insight] epoch(轮)= 把整个训练数据集**完整过一遍**
> 你这次有 1500 条数据,**1 个 epoch = 这 1500 条全部喂给模型学一遍**。`--num_train_epochs 1` 就是只过 1 遍。`epoch: 1.0` 表示跑完了 1 整轮。

**它和 step(步)的关系**(产物里两个都有,别搞混):
- **step(步)**:更新一次参数算 1 步。你这次 `global_step: 94`,即更新了 94 次。
- **epoch(轮)**:数据全过一遍算 1 轮。
- 换算:`步数 = 数据量 ÷ 有效batch × epoch`。你这次 ≈ 1500 ÷ 16 × 1 ≈ 94 步(有效 batch = `batch_size 1 × 梯度累积 16`)。所以 `epoch=1` 对应 `step=94`。

> [!key-insight] <font color="red">epoch 要不要关心?——要,但它是"设定值"不是"观察值"</font>
> - **训练中**:`train_epoch.png`(epoch 随步数线性增长)**不用盯**,它只是个进度条,没有"好坏"。
> - **训练前**:`--num_train_epochs` 的**取值很重要**,直接影响效果和过拟合,这才是你该关心的:
>
> | epoch 设多少 | 后果 | 怎么选 |
> |---|---|---|
> | **太少**(如不够 1) | 没学透,**欠拟合**,效果差 | —— |
> | **适中**(常见 1~3) | 学到位又不过头 | ✅ 微调推荐起步值 |
> | **太多**(如 10+) | 把训练集背死,**过拟合**:loss 还在降但新问题答不好 | 看到 loss 先降后升就是过头了 |
>
> **经验**:[[03 LoRA 与 QLoRA|LoRA]] 微调一般 **1~3 个 epoch** 就够;数据越多,需要的 epoch 越少。练手用 1 即可(你这次就是)。判断 epoch 是否设多了,**回头看 loss 曲线有没有"先降后升"**(过拟合信号,见 [[05 灾难性遗忘]])。

### 1.4 token_acc 是什么?怎么看好坏

> [!key-insight] <font color="red">token_acc(token 准确率)= 模型逐字"猜下一个词"猜对的比例,越高越好</font>
> 大模型本质是"预测下一个 token(词/字片段)"。token_acc 就是:**在训练样本里,模型预测的下一个 token 和标准答案一致的比例**。你这次从 0.59 升到 0.65,意思是约 65% 的 token 猜对了。

**怎么看好坏:**

| token_acc 表现 | 说明 | 好 / 坏 |
|---|---|---|
| **整体缓慢上升** | 模型越学越准,和 loss 下降是一回事的两个视角 | ✅ 好 |
| **横着不动 / 下降** | 没学进去(常和 loss 不降同时出现) | ❌ 坏 |
| **冲到很高(如 >0.95)** | 小数据时警惕**过拟合**(把答案背下来了) | ⚠️ 结合 loss 一起判断 |

> [!key-insight] 初学者别被 token_acc 的绝对值误导
> - **它和 loss 高度相关**:loss 降,acc 基本就升,**两个一起看更稳,不用单独纠结 acc 数值**。
> - **0.65 不代表"模型只有 65 分"**:同一句话有很多种合理说法,模型用了同义表达就会被算"猜错",但回答其实没问题。所以 **token_acc 是辅助参考,真实效果还得靠 `swift infer` 实际问几句**(见 §4 / [[03 ms-SWIFT 测试运行示例]])。
> - **不同数据/任务的 acc 基准差很多**,和 loss 一样**只比趋势、不比绝对值**。

### 1.5 grad_norm 是什么?怎么看好坏

> [!key-insight] grad_norm(梯度范数)= 这一步参数"想改多大"的总幅度,看的是**稳不稳**
> 每一步训练会算出"参数该往哪改、改多少"(梯度),grad_norm 是把这些改动汇总成的一个数。**它不是越大越好或越小越好,关键看平不平稳。**

**怎么看好坏:**

| grad_norm 表现 | 说明 | 好 / 坏 |
|---|---|---|
| **开头略高,之后逐渐平稳回落** | 正常:开头参数乱、改动大,慢慢收敛 | ✅ 好(你这次 3.7→1.2 就是) |
| **平稳在一个小范围内波动** | 训练稳定 | ✅ 好 |
| **突然飙出巨大尖峰** | 梯度爆炸,某步改动失控,常伴随 loss 跳变 | ⚠️ 偶尔一次可接受,频繁出现要警惕 |
| **变成 NaN / inf** | 梯度彻底崩了:学习率太大 / 精度问题(如 Mac 上 float16) | ❌ 坏,训练已失效,要停下改参数 |

> [!key-insight] grad_norm 和学习率、梯度裁剪的关系
> - grad_norm 频繁过大或爆炸 → 多半**学习率太大**,调小即可(呼应 §1.2)。
> - ms-SWIFT 默认会做**梯度裁剪**(把过大的梯度"削平"到一个上限,防爆炸),所以你通常看到的是被控制住的平稳值。
> - **新手优先级**:grad_norm 不用主动盯,**只在 loss 异常(爆炸/NaN)时回头看它确认是不是梯度问题**即可——所以它没进开头那 4 个"必看"项。

## 2. ★ images/ —— 一眼看懂的训练曲线(最直观)

ms-SWIFT 自动把上面那些指标画成 PNG,在 `images/` 下。**不想读 JSON 就直接看图**:

| 图片                          | 画的是        | 怎么看                                |
| --------------------------- | ---------- | ---------------------------------- |
| **train_loss.png**          | loss 随步数变化 | ★最重要,**曲线整体向下** = 在学;横着不动或上扬 = 有问题 |
| **train_token_acc.png**     | token 准确率  | 整体**向上**为好                         |
| **train_grad_norm.png**     | 梯度范数       | 别有夸张尖峰/爆炸                          |
| **train_learning_rate.png** | 学习率调度      | 应是"先升(warmup)后降"的形状,验证调度对不对        |
| train_epoch.png             | epoch 进度   | 一般线性增长,不用太关注                       |
| train_total_flos.png        | 累计算力       | 资源消耗,了解即可                          |
| train_train_runtime.png 等   | 总耗时/吞吐速度   | 性能指标,见下节                           |

> 这些图等价于"穷人版 TensorBoard"——单次训练快速复盘足够用,不用专门起 TensorBoard。

## 3. logging.jsonl —— 逐行日志(脚本化分析用)

每行一条 JSON,内容和 `trainer_state.json` 的 `log_history` 基本一致,但**最后两行是总结**,信息量大:

```jsonl
{"train_runtime": 530.7, "train_samples_per_second": 2.826, "train_steps_per_second": 0.177,
 "train_loss": 1.548, "token_acc": 0.615, "epoch": 1.0, ...}
{"train_dataset": "...size=1500", "model_parameter_info":
 "601.0962M Params (5.0463M Trainable [0.8395%])", "last_model_checkpoint": ".../checkpoint-94"}
```

> [!key-insight] 最后一行藏着两个关键信息
> - **`model_parameter_info`**:总参数 601M,**可训练只有 5.05M(占 0.84%)**——这就是 [[03 LoRA 与 QLoRA|LoRA]] 的威力:只训不到 1% 的参数。
> - **`train_runtime: 530s`(约 8 分 51 秒)/ 2.826 samples/s**:本次在 Mac(MPS)上的真实速度。可见 **Mac 跑训练确实慢**(对比 CUDA 会快很多),印证"Mac 验证流程、训练上 CUDA"。

## 4. ★ adapter_model.safetensors —— 训练成果本体(LoRA 权重)

这才是微调真正**产出的模型文件**(约 19MB),配合 `adapter_config.json` 使用。推理时:

```bash
# 加载基座模型 + 这个 LoRA 权重做推理
swift infer --adapters output/v1-20260602-121310/checkpoint-94 --stream true
```

> [!key-insight] 为什么才 19MB?LoRA "补丁"的本质
> 它**不是完整模型**,只是 LoRA 插进各层的"小矩阵"。基座 Qwen3-0.6B 本体(约 1.2GB)在你的模型缓存里(`~/.cache/modelscope/...`),推理时两者**拼在一起**用。想要独立完整模型,得 `swift export --merge_lora` 合并(见 [[03 ms-SWIFT 测试运行示例]] 第 3 节)。

## 5. adapter_config.json —— LoRA 的"配方"

记录这次 LoRA 是怎么搭的,和你命令行传的参数对应:

```json
{
  "r": 8,                       // --lora_rank 8
  "lora_alpha": 32,             // --lora_alpha 32
  "lora_dropout": 0.05,
  "peft_type": "LORA",
  "base_model_name_or_path": ".../Qwen/Qwen3-0___6B",   // 基于哪个基座
  "target_modules": ["q_proj","k_proj","v_proj","o_proj",  // all-linear 实际展开成这些层
                     "gate_proj","up_proj","down_proj"]
}
```

> `--target_modules all-linear` 被自动展开成了上面 7 个线性层名。想确认"到底给哪些层加了 LoRA",看这里。

## 6. checkpoint-50 vs checkpoint-94 —— 中途存档 vs 最终

- `--save_steps 50` → 每 50 步存一次,所以有 **checkpoint-50**(中途)和 **checkpoint-94**(最后一步)。
- `--save_total_limit 2` → 最多留 2 个,超了删最旧的。
- **一般用最后的 checkpoint-94**;若发现后期过拟合(loss 反升),可回退到中途的 checkpoint-50。

## 7. 那些"平时不用看"的文件(简单了解)

| 文件 | 作用 | 要不要管 |
|---|---|---|
| `optimizer.pt`(39MB) | 优化器状态(动量等) | 仅**断点续训**用,占磁盘大头,平时不看 |
| `scheduler.pt` | 学习率调度器状态 | 同上 |
| `rng_state.pth` | 随机数状态,保证续训可复现 | 同上 |
| `training_args.bin` | HF Trainer 参数(二进制) | 备份,看 `args.json` 即可 |
| `args.json` | ms-SWIFT 完整参数(可读 JSON) | 想确认"当时用了什么参数"时看 |
| `additional_config.json` | 额外配置 | 一般不用看 |
| `README.md` | 自动生成的模型卡 | 了解即可 |
| `runs/events.out.tfevents.*` | TensorBoard 事件文件 | 想用 TensorBoard 看曲线时:`tensorboard --logdir output/v1-xxx/runs` |

> [!key-insight] 断点续训怎么用这些存档?
> 训练中断了,想接着练,用 `--resume_from_checkpoint output/v1-xxx/checkpoint-50`,ms-SWIFT 会读 `optimizer.pt`/`scheduler.pt`/`rng_state.pth` **恢复到中断时的完整状态**(不只是模型权重),接着往下训。这就是它们存在的意义。

## 看产物的推荐顺序

> [!key-insight] 训练跑完,照这个顺序复盘
> 1. **看 `images/train_loss.png`** —— 一眼确认 loss 在降(训练有效)。
> 2. **看 `images/train_token_acc.png`** —— 确认准确率在升。
> 3. **(可选)翻 `trainer_state.json` 的 `log_history`** —— 要精确数值时看。
> 4. **`swift infer --adapters checkpoint-94`** —— 加载 LoRA 实际问几句,主观验证效果。
> 5. **满意了 → `swift export --merge_lora`** 合并成完整模型。

## 继续学习

- [[03 ms-SWIFT 测试运行示例|ms-SWIFT 测试运行示例]](产物从哪来:训练/推理/合并命令)
- [[03.2 显卡监控工具|显卡 / 算力监控工具]](训练时盯硬件,产物里看结果)
- [[03 LoRA 与 QLoRA|LoRA 与 QLoRA]](为什么产物只有 19MB)
- [[05 灾难性遗忘|灾难性遗忘]](loss 异常 / 过拟合时回看本页曲线)
