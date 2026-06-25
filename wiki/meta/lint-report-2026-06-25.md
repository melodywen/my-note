---
type: meta
title: "Lint Report 2026-06-25"
created: 2026-06-25
updated: 2026-06-25
tags: [meta, lint]
status: developing
---

# Lint Report: 2026-06-25

> 传输层：filesystem（无 `.vault-meta/`）。DragonScale **未启用**（无 `scripts/`），故第 9 项「地址校验」与第 10 项「语义去重」**跳过**（不适用）。

## Summary
- 扫描页面：40
- 真实问题：**7**（1 个中等 + 6 个轻微/信息）
- 误报已排除：12（转义管道符 `\|` 表格内链接 + 我的 Obsidian 指南里的语法示例）
- **已自动修复：5**（frontmatter×2 + 死链改链×2 + 模板遗留链删除×1）
- 待人工判断：2（`[[Qwen]]` 是否建实体页 + 孤儿页是否补内链）

> [!done] 2026-06-25 已执行安全自动修复
> 1. 补 frontmatter：`Oh-My-OpenAgent-实战搭配使用指南.md`、`oh-my-openagent.json-小白配置详解.md`（并互加 related 内链）
> 2. 改死链：`[[模型评测]]`→`[[01 EvalScope|模型评测]]`、`[[微调数据集构建]]`→`[[07 微调数据集的创建原理|微调数据集构建]]`
> 3. 删模板遗留：`overview.md` 里的 `## Canvases` + `[[swift-knowledge]]` 桩链
> 复查结果：**frontmatter 缺失 0、真实死链仅剩 `[[Qwen]]`**。

---

## 🟡 中等：缺失 frontmatter（2 页完全没有 YAML 头）

这两页是手写导入的，**完全没有 frontmatter**，Dataview/Bases 查询会漏掉它们：

- `wiki/learning/opencode/oh-my-openagent/Oh-My-OpenAgent-实战搭配使用指南.md`
- `wiki/learning/opencode/oh-my-openagent/oh-my-openagent.json-小白配置详解.md`

**建议**：补上标准头（`type/status/created/updated/tags`）。可自动修复。

---

## 🔵 轻微：孤儿页面（无任何入链，4 页）

这些页面存在但没有任何其它页面链向它们（注意：本库导航主要靠 `index.md` 列表 + 序号文件名，孤儿不一定是问题）：

- `08 分布式训练 DDP 与 DeepSpeed 深度对比.md` — 建议从 [[06 微调所需软硬件环境]] 或框架页链入
- `09 Function Calling 与 MCP 原理详解.md` — 建议从 [[04 SFT 与指令微调]] 链入
- `02 Qwen3 4B-8B 微调数据量经验.md` — 建议从 `Qwen3 微调经验总结/_index` 或 01 篇链入
- `oh-my-openagent.json-小白配置详解.md` — 建议与同目录 [[Oh-My-OpenAgent-实战搭配使用指南]] 互链

**建议**：补内链即可消除。可自动修复（加 wikilink）。

---

## 🔵 信息：真实死链（4 处，需建桩或改链）

排除误报后，确实指向不存在页面的链接：

| 死链 | 出现在 | 处理建议 |
|---|---|---|
| `[[Qwen]]` | `03 ms-SWIFT 测试运行示例.md` | 建一个 `entities/Qwen.md` 实体桩页，或改为纯文本 |
| `[[模型评测]]` | `01 Qwen3 混合推理模型微调数据集准备.md` | 实际页是 [[01 EvalScope]]，建议改链或建分区桩 |
| `[[微调数据集构建]]` | `SFT数据集构建完全指南.md` | 实际页是 [[07 微调数据集的创建原理]]，建议改链 |
| `[[swift-knowledge]]` | `overview.md` | overview 模板遗留的示例链接，建议删除 |

> 另：`overview.md` 第 23 行的 `[[wikilink]]` 是**说明文字里的语法示例**（讲"用 wikilink 双链"），不是真链接，**无需处理**。

---

## ✅ 已排除的误报（无需处理）

- `[[01 EvalScope\|…]]`、`[[03 LoRA 与 QLoRA\|…]]` 等：表格单元格里管道符被转义成 `\|`，**是有效链接**，仅扫描器误判。
- `[[笔记名]]`、`[[笔记名\|显示文字]]`、`[[文件]]`、`[[页面]]`：均在 [[Obsidian 命令与技能完全指南]] 的**语法教学示例**中，是故意的占位符，非真实链接。

---

## 命名与重复
- 重复同名页面：**无**（40 页文件名唯一，wikilink 不会歧义）。✅
- 文件名规范：本库用「序号 + 中文标题」风格（如 `03 LoRA 与 QLoRA.md`），全库一致。✅

---

## 结论

知识库整体**健康**。没有 BLOCKER/HIGH 级问题。

> [!done] 2026-06-25 第二轮：清零处理（用户选 B）
> - **建实体桩页** [[Qwen]] → `[[Qwen]]` 死链消除。
> - **孤儿页补内链**：08 分布式训练 ← 06 软硬件环境；09 Function Calling ← 04 SFT；02 Qwen3 数据量 ← 01 数据集准备 + [[Qwen]]；opencode 配置 ← 姊妹页 related。
> - **index 登记** 新增 🧩 实体分区。
> - **最终复查**：frontmatter 缺失 **0**、真实死链 **0**、孤儿页 **0**。✅ 全清。
