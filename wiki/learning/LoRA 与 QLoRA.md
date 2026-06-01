---
type: concept
status: developing
area: growth
tags: [learning, LoRA, QLoRA, PEFT]
created: 2026-06-01
updated: 2026-06-01
---

# LoRA 与 QLoRA

## 核心要点

两种最主流的高效微调(PEFT)方法,均属"重参数化"思路。

### LoRA (Low-Rank Adaptation)

- 原理:冻结预训练权重 W,在旁路注入可训练的低秩矩阵 A、B(W + BA),仅训练 A、B(基于"权重更新具有低内在秩"的假设)。
- 参数量从数十亿级降至百万级。
- 推理时可合并回原权重,**无额外延迟**。
- 出处:[[LoRA原始论文]](Hu et al. 2021, arXiv:2106.09685)。

### QLoRA (Quantized LoRA)

- 原理:原始权重量化为 INT4/INT8 低精度存储,适配器层用 FP16 训练 —— "量化存储 + 高精度计算"。
- 在 LoRA 基础上进一步降显存。

## 关键指标对比

| 特性 | LoRA | QLoRA |
|------|------|-------|
| 量化 | 无 | INT4/INT8 |
| 7B 显存 | 约 16GB | 约 6GB |
| 70B 显存 | — | 约 48GB(单卡 24GB 可微调 70B) |
| 显存降幅 | 比全量降 80%+ | 比 LoRA 再降 40-50% |
| 训练速度 | 提升 3-5 倍 | — |
| 推理 | 无延迟 | 加速 20-30%,复杂推理有轻微精度损失 |

> [!key-insight] 选型
> 消费级 GPU / 中小模型选 LoRA;超大模型或极低显存场景选 QLoRA。

## 相关链接

- [[全量微调与高效微调]]
- [[大模型微调概述]]
- [[LoRA原始论文]]
- 综合页:[[Research: 大模型微调]]
