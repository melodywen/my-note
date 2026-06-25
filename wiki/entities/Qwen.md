---
type: entity
entity_type: product
status: seed
title: "Qwen"
created: 2026-06-25
updated: 2026-06-25
tags:
  - entity
  - 大模型
  - qwen
  - 阿里
related:
  - "[[01 Qwen3 高效微调环境准备]]"
  - "[[03.1 Qwen3 家族选型(VL 与 3.5)]]"
  - "[[01 Qwen3 混合推理模型微调数据集准备]]"
---

# Qwen（通义千问）

> 阿里巴巴（通义实验室）研发的开源大语言模型系列，中文社区微调实战里最常用的基座之一。本库的微调示例（ms-SWIFT 等）大多以 Qwen3 作为 `--model`。

## 是什么

- **Qwen / 通义千问**：阿里开源的 LLM 家族，提供从 0.5B 到数百 B 的多档参数规模。
- 在 [[03 ms-SWIFT 测试运行示例]] 中，`--model Qwen/Qwen3-4B-Instruct-2507` 即指定 Qwen3 4B 指令版作为微调基座，可从魔搭(ModelScope)/HuggingFace 自动下载。

## 常见型号（本库涉及）

- **Qwen3-0.6B**：Mac/MPS 练手轻量版（float32 仅约 2.4GB）。
- **Qwen3-4B-Instruct-2507**：CUDA 单卡微调示例基座（约 13GB 显存）。
- **Qwen3-VL**：视觉多模态版（能看图），见 [[03.1 Qwen3 家族选型(VL 与 3.5)|Qwen3 家族选型]]。

## 相关页面

- [[01 Qwen3 高效微调环境准备]] — 拿 Qwen3 做微调的环境四件套
- [[03.1 Qwen3 家族选型(VL 与 3.5)]] — 带不带 VL、Qwen3 与 3.5 怎么选
- [[01 Qwen3 混合推理模型微调数据集准备]] — Qwen3 混合推理模型的数据集准备
- [[02 Qwen3 4B-8B 微调数据量经验]] — 4B/8B 微调数据量经验
