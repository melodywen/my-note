---
type: concept
status: developing
area: growth
tags: [learning, SFT, 数据集]
created: 2026-06-01
updated: 2026-06-01
---

# SFT 与指令微调

## 核心要点

- **SFT (Supervised Fine-Tuning,有监督微调)**:用标注数据微调预训练模型,使其更好执行特定任务。
- **指令微调 (Instruction Tuning)**:SFT 的一种特殊形式,数据集由(指令,输出)对构成,专注于让模型理解并遵循人类指令。

> [!key-insight] 关系
> 指令微调 ⊂ SFT。区别在数据结构:指令微调强调"人类指令 + 期望输出"的配对。

## 数据集格式

- **Alpaca**:Instruction / Input / Response,应用最广
- **ChatML**:`<|im_start|>...` 对话系统优化
- 简单格式:Instruction/Input/Output

## 数据构建原则

> [!key-insight] 质量 > 数量
> 高质量指令数据直接决定模型表现与能力边界。

- 四要素:多样性、高质量、一致性、可扩展性
- 质量评分:相关性30% + 准确性30% + 清晰度20% + 安全性20%,阈值 ≥0.6
- 流程:需求分析 → 收集/生成 → 清洗 → 质量筛选 → 增强 → 划分 → 输出
- 策略:从几百条小规模起步,逐步扩展

## 相关链接

- [[大模型微调概述]]
- [[SFT数据集构建完全指南]]
- 综合页:[[Research: 大模型微调]]
