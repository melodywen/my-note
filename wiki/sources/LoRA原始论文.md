---
type: source
status: summarized
source_type: paper
author: "Hu et al. (Microsoft)"
date_published: 2021-06-18
url: "https://arxiv.org/abs/2106.09685"
confidence: high
tags: [source, paper, LoRA]
created: 2026-06-01
updated: 2026-06-01
---

# 来源:LoRA: Low-Rank Adaptation of Large Language Models

## 概要

LoRA 的原始论文(arXiv:2106.09685)。提出冻结预训练权重、在 Transformer 每层注入可训练的低秩分解矩阵,大幅减少可训练参数。

## 关键事实

- 核心方法:冻结预训练模型权重 W,在旁路注入低秩矩阵 A、B(W + BA),仅训练 A、B。
- 不要求权重更新矩阵满秩,基于"权重更新具有低内在秩"的假设。
- 相比全量微调,可训练参数大幅减少,且推理时可合并回原权重,无额外延迟。
- 是后续 QLoRA 等高效微调方法的基础。

## 提取的概念/实体

- [[LoRA 与 QLoRA]]

## 原始素材位置

外部链接,见 frontmatter url。
