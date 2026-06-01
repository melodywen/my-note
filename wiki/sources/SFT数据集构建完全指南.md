---
type: source
status: summarized
source_type: article
author: "CSDN(qq_16242613)"
date_published: 2025-10-30
url: "https://blog.csdn.net/qq_16242613/article/details/151893183"
confidence: medium
tags: [source, SFT, 数据集]
created: 2026-06-01
updated: 2026-06-01
---

# 来源:大模型指令微调(SFT)数据构建完全指南

## 概要

讲解 SFT 指令微调数据集的格式、构建流程与质量评估方法。

## 关键事实

- 数据格式:Alpaca 格式(Instruction/Input/Response,最广泛)、简单格式、ChatML 格式(对话优化)。
- 核心论断:数据质量优于数量,高质量数据直接决定模型表现与能力边界。
- 构建流程(7 阶段):需求分析 → 数据收集/生成 → 清洗格式化 → 质量评估筛选 → 数据增强 → 划分验证 → 输出。
- 质量评分:相关性30% + 准确性30% + 清晰度20% + 安全性20%,阈值 ≥0.6 保留。
- 策略:从小规模(几百条)开始,逐步扩展到数千条乃至生产规模。

## 提取的概念/实体

- [[04 SFT 与指令微调|SFT 与指令微调]]
- [[微调数据集构建]]

## 原始素材位置

外部链接,见 frontmatter url。
