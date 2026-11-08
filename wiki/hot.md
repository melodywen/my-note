---
type: meta
title: "Hot Cache"
updated: 2026-11-05
---

# 最近上下文 (Hot Cache)

## 最近更新
2026-11-08。新增 claude-mem 学习文档三篇:[[claude-mem-配置详解]]、[[claude-mem-安装部署]]、[[claude-mem-调教清单]];接 codebuddy 优先用 `openai-compatible`,`SEARCH_RECENCY_DAYS` 默认 90 天会让旧记忆搜不到;存储与读取、跨端共享两篇待写;均未实测。
2026-11-08。新增 [[OpenCode与DSH共享记忆-选型调研]] 与 [[claude-mem-深入调研]]:claude-mem 领先(安装时须避开云登录与托管观察者,默认向量嵌入是英文模型);memsearch 架构最贴合但仅 2.8k 星;均未实测。
2026-11-05。opencode-mem 摘要语言本机固定为 `zh`(glm-5.2 在 auto 下会写成瑞典语/索马里语/法语等),见 [[opencode-mem-值得调整的配置]] 第 11 节;缺 `promptId` 的 37 条老记忆已清,网页恢复。
2026-11-05。opencode-mem 已关闭 markdown 后端(v2.41.0 重启会抹掉 `promptId`,网页崩溃),见 [[opencode-mem-值得调整的配置]] 第 12 节;`opencode-mem-vault` 仓库不再使用。
2026-11-05。另新增 [[opencode-mem-值得调整的配置]](必改:opencodeProvider/Model;嵌入模型已定 Xenova/bge-m3(默认 nomic 对非英文疑似不佳,存第一批记忆前定好);重要记忆置顶/调保留天数)。
2026-11-05。新增学习笔记 [[opencode-mem-调研与上手指南]](opencode-mem 检索、冲突与迭代、安装配置;默认配置基本不处理知识冲突,需手动开 updateOnCapture/dreaming;默认 30 天未更新会被清理,重要记忆要置顶)。

(以下为此前记录)
2026-06-01。完成首次 autoresearch:研究主题"大模型微调",归档 9 个新页面。

## 关键近期事实
- 微调通过改参数让模型"永久"掌握能力,区别于 RAG/Agent 工作流
- 高效微调(PEFT,尤其 LoRA/QLoRA)是工业界主流,省资源且缓解灾难性遗忘
- 灾难性遗忘缓解:优先 PEFT + 10-20% 通用数据混合 + 低学习率(1e-5~5e-5)
- SFT 数据集质量优于数量,Alpaca 格式最常用

## 最近变更
- 创建:[[Research: 大模型微调]](综合)、[[01 大模型微调概述|大模型微调概述]]、[[02 全量微调与高效微调|全量微调与高效微调]]、[[03 LoRA 与 QLoRA|LoRA 与 QLoRA]]、[[04 SFT 与指令微调|SFT 与指令微调]]、[[05 灾难性遗忘|灾难性遗忘]]
- 来源:4 篇(含 [[LoRA原始论文]])

## 活跃线索
- 微调研究的开放问题:全量 vs LoRA 效果实测、DPO/RLHF 对齐阶段未覆盖
- 用户通过 B 站视频截图触发了此次研究
