---
type: meta
title: "Log"
updated: 2026-06-01
---

# 操作日志 (Log)

仅追加。新条目放在最上方。永不修改历史条目。

---

## 2026-06-25 — wiki-retrieve | 启用本地混合检索

- 从官方仓库 AgriciDaniel/claude-obsidian 稀疏检出 4 个脚本 + setup-retrieve.sh，装入 my-note/scripts/ 与 bin/
- 纯标准库，无 pip 依赖；ollama 拉取 nomic-embed-text 供 cosine 重排
- 以 --no-llm（tier-3 synthetic 前缀，纯本地零外发）provision：42 页 → 112 chunks，BM25 vocab 9835
- 实测查询「Qwen 训练 微调命令 swift sft」→ top1 命中 [[03 ms-SWIFT 测试运行示例]]，strategy=bm25+rerank:cosine:nomic-embed-text ✅
- .vault-meta/ 索引(2.4MB)与 __pycache__ 已 gitignore；脚本入库
- 重建命令：`bash bin/setup-retrieve.sh --no-llm`

---

## 2026-06-25 — wiki-lint | 全库体检 + 安全自动修复

- 扫描：40 页（filesystem 传输 / DragonScale 关，地址校验+语义去重跳过）
- 报告：[[lint-report-2026-06-25]]
- 真实问题 7，误报排除 12
- 已自动修复 5：补 frontmatter×2（opencode 两页）、改死链×2（模型评测→EvalScope、微调数据集构建→07篇）、删 overview 模板遗留链（swift-knowledge）
- 复查：frontmatter 缺失 0、真实死链仅剩 [[Qwen]]（待定是否建实体页）
- 孤儿页 4（08/09/Qwen3数据量/opencode配置）：本库靠 index 导航，非必须处理
- 第二轮（用户选 B，清零）：建实体页 [[Qwen]]、4 孤儿页补内链、index 加实体分区
- 最终复查：frontmatter 缺失 0 / 真实死链 0 / 孤儿页 0 ✅ 全清

---

## 2026-06-25 — wiki-query + autoresearch | Obsidian 命令与技能

- 触发：用户要求写一篇介绍 Obsidian 所有命令与技能的文章
- 来源：本地 claude-obsidian 14 个 SKILL.md 逐个核对 + GitHub 一手核对（仓库/作者/版本/与 kepano 关系）
- 创建页面：[[Obsidian 命令与技能完全指南]]（归档至 learning/Obsidian/）
- 关键内容：Obsidian 自身命令（Cmd+P 命令面板 / 核心快捷键 / Canvas / Bases）+ claude-obsidian 14 技能（wiki-query/save/ingest/autoresearch/canvas/defuddle/lint/retrieve/fold/wiki/cli/mode/markdown/bases）+ think 元技能
- 备注：初放 questions/，按用户意见移至 learning/Obsidian/（工具学习类）

---

## 2026-06-01 — autoresearch | 大模型微调

- 轮次:2
- 搜索:6 次,抓取来源 3 篇 + 论文 1 篇
- 创建页面:[[01 大模型微调概述|大模型微调概述]]、[[02 全量微调与高效微调|全量微调与高效微调]]、[[03 LoRA 与 QLoRA|LoRA 与 QLoRA]]、[[04 SFT 与指令微调|SFT 与指令微调]]、[[05 灾难性遗忘|灾难性遗忘]]
- 来源页:[[大模型微调技术入门全攻略]]、[[大模型微调灾难性遗忘解析]]、[[SFT数据集构建完全指南]]、[[LoRA原始论文]]
- 综合:[[Research: 大模型微调]]
- 关键发现:高效微调(PEFT/LoRA)是工业界主流,既省资源又能缓解灾难性遗忘

---

## 2026-06-01 — 知识库初始化

- 清空旧笔记,按 Mode D(个人第二大脑)重新搭建结构
- 创建目录:goals / learning / people / areas / resources / sources / questions / meta
- 创建核心文件:index / overview / hot / log
- 创建 `_templates/` 笔记模板
- 配置 `.obsidian/snippets/vault-colors.css` 视觉样式
