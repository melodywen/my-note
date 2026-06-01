---
type: concept
status: developing
area: growth
tags: [learning, 微调, 框架, llama-factory]
created: 2026-06-01
updated: 2026-06-01
---

# LLaMA-Factory(全能型微调瑞士军刀)

> 本页讲 **LLaMA-Factory**:它是什么、五大功能特点、以及它为什么是"全能 + 易用"的代表。一句话记住:**模型支持最广、方法最全、还自带图形界面(UI),适合入门和复杂任务。**

## 一句话定位

**LLaMA-Factory 是一个统一且高效的微调框架,旨在为超过 100 种大语言模型(LLMs)和视觉语言模型(VLMs)提供便捷的微调支持,让用户灵活定制模型以适应各种下游任务。**

- 官方仓库:`github.com/hiyouga/LLaMA-Factory`
- 关键词:**统一、广覆盖、多模态、带 UI**。

> [!key-insight] 它和 [[02 Unsloth|Unsloth]] 的根本差异
> Unsloth 把"单卡速度/省显存"压到极致;LLaMA-Factory 走的是另一条路 —— **大而全**:模型多、方法多、任务类型多,还有零代码的图形界面。速度不是它的卖点,**全面和易用**才是。

## 主要功能和特点(五点)

| # | 特点 | 内容 |
|---|---|---|
| 1 | **广型支持** | 支持对 **100+ LLMs 和 VLMs** 微调,涵盖最新模型,如 Llama 3、GLM-4、Mistral Small、PaliGemma2 等。 |
| 2 | **高效的微调方法** | 集成了 [[03 LoRA 与 QLoRA\|LoRA(Low-Rank Adaptation)]]、**QLoRA(Quantized LoRA)** 等多种方法,提高训练速度并减少显存占用。 |
| 3 | **多模态任务支持** | 除传统文本任务外,还支持图像识别、音频理解等多种任务类型。 |
| 4 | **实验监控** | 提供丰富的实验监控工具,如 **LlamaBoard、TensorBoard、Wandb、MLflow**,可视化训练过程。 |
| 5 | **快速接入** | 提供类似 **OpenAI 风格的 API、Gradio UI 和命令行界面**,并实现了高效的推理能力。 |

## 三种使用方式,丰俭由人

| 方式 | 谁适合 | 特点 |
|---|---|---|
| **Gradio UI(LlamaBoard)** | 新手、想快速试 | **零代码**,浏览器点点就能配数据、调参、开训、看曲线 |
| **命令行(CLI)** | 想脚本化、批量跑 | 配一个 YAML 就能复现实验,适合做对比 |
| **OpenAI 风格 API** | 要把微调好的模型接进应用 | 训完直接起服务,接口与 OpenAI 兼容 |

> [!key-insight] 为什么初学者常从它入手
> 一个 **LlamaBoard 图形界面**就把"准备数据 → 选模型 → 选 LoRA/QLoRA → 开训 → 看监控"全串起来了,**不用写一行训练代码**。配合 100+ 模型和多模态支持,几乎你想试的任何任务它都能接。

## 适用场景

- ✅ **想要图形界面、零代码上手** —— LlamaBoard 最舒服。
- ✅ **需要横向对比多个模型 / 多种方法**(SFT、[[03 LoRA 与 QLoRA|LoRA/QLoRA]]、DPO、PPO)。
- ✅ **多模态任务**(图像、音频)。
- ✅ **多硬件环境**(NVIDIA / AMD / 昇腾 NPU)、分布式训练。
- ⚠️ **极致单卡速度/省显存** → 这块 [[02 Unsloth|Unsloth]] 更强(LLaMA-Factory 也能集成 Unsloth 加速)。

## 继续学习

- [[01 四大微调框架概述|四大微调框架概述]](LLaMA-Factory 在四套工具中的定位)
- [[02 Unsloth|Unsloth]](对比:极致单卡 vs 全能易用)
- [[03 LoRA 与 QLoRA|LoRA 与 QLoRA]](LLaMA-Factory 内置的核心方法)
- [[04 SFT 与指令微调|SFT 与指令微调]]
- 参考:LLaMA-Factory GitHub(`github.com/hiyouga/LLaMA-Factory`)
