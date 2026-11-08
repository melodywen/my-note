---
type: meta
title: "Log"
updated: 2026-11-08
---

# 操作日志 (Log)

仅追加。新条目放在最上方。永不修改历史条目。

---

## [2026-11-08] create | claude-mem 存储与读取机制、跨端共享,并订正 host 提供方

新增 [[claude-mem-存储与读取机制]]、[[claude-mem-跨端共享]]。跨端调研(lib-2)有三处与源码不符,已按源码改正:DSH 有官方集成(`--ide dsh`,`@claude-mem/dsh`,靠 worker 监听 `~/.dsh/sessions` 写入),`INCLUDE_ALL_SOURCES` 存在且 OpenCode 插件也读,OpenCode 注入走系统提示词钩子而非 `AGENTS.md`。订正 `--provider host`:它要求本机已有兼容服务、安装器不会起,是为 Grok Bot/Cursor 设计,对 OpenCode/DSH 大概率不可用;安装部署、调教清单、配置详解里"首次先用 host"的建议改为先用 `claude` 再改 codebuddy。均未实测。

## [2026-11-08] remove | 卸载 opencode-mem

摘除插件配置,删除全局配置、数据目录 `~/.opencode-mem`、npm 缓存和旧 markdown 库;未备份记忆数据。相关两篇笔记已加卸载说明。

## [2026-11-08] create | claude-mem 学习文档(配置详解、安装部署、调教清单)

- 新增 `learning/opencode/claude-mem/` 三篇:[[claude-mem-配置详解]](238 键分 20 组,逐键注释,来自源码 DEFAULTS)、[[claude-mem-安装部署]]、[[claude-mem-调教清单]](分 8 轮调教)。
- 修正旧结论:键数 238 而非 119;接 codebuddy 优先用 `openai-compatible`;`EMBEDDING_MODEL` 仅服务器模式生效,本机中文向量召回短板仍在;`SEARCH_RECENCY_DAYS` 默认 90 天会让旧记忆搜不到。
- 存储与读取机制、跨端共享两篇尚未写,调研进行中。均未实测。

---

## [2026-11-08] create | OpenCode 与 DSH 共享记忆选型调研(两篇)
- 新增 [[OpenCode与DSH共享记忆-选型调研]](候选总表、推荐排序、淘汰理由、证据质量说明、未验证项)与 [[claude-mem-深入调研]](优势、部署、数据外发三条路径、云本地差异、检索架构与中文)。位于 `learning/opencode/记忆方案选型/`。
- 结论:claude-mem 领先;memsearch 架构最贴合但仅 2.8k 星。全部基于读源码与文档,未做实测。

## [2026-11-05] update | opencode-mem 固定摘要语言并清理
- 实测 `glm-5.2` 在 `autoCaptureLanguage: "auto"` 下把中文对话的摘要写成瑞典语、罗马尼亚语、克罗地亚语、索马里语、法语。本机固定为 `"zh"`,更新 [[opencode-mem-值得调整的配置]](第 11 节、"看情况"表、JSON 示例)。
- 清理:删掉 37 条缺 `promptId` 的自动捕获记忆(软删除,可从回收站恢复),网页 20 页逐页翻通过,无 `each_key_duplicate`;另删 2 条过时摘要(索马里语、法语)、本地 `opencode-mem-vault` 目录、旧 nomic 嵌入模型缓存(约 523MB)。
- 未验证:服务重启后"关 markdown"与"摘要固定中文"是否生效、新记忆是否保留 `promptId`。

## [2026-11-05] update | opencode-mem 关闭 markdown 后端
- 根因:markdown 后端每次启动全量扫描 md,按 md 重写数据库;md 文件头无 `promptId`,重写时把它抹掉,网页配不上记忆与提问,报 `each_key_duplicate` 崩溃。实测 37 条缺 `promptId` 的记忆全带 `markdownContentHash`,2 条最新的有 `promptId` 且全无该标记。
- 决定:去掉 `memoryBackend`/`markdownPath`,回到默认 `database`;不再使用 `opencode-mem-vault` 仓库。更新 [[opencode-mem-值得调整的配置]](第 12 节、"看情况"表、JSON 示例)、[[opencode-mem-调研与上手指南]]。
- 未验证:关闭后已丢 `promptId` 的老记忆不会恢复,需删除或等上游修复;重启后效果待核对。

## [2026-11-05] update | opencode-mem 嵌入模型改为 bge-m3
- 发现默认 nomic-embed-text-v1 官方页未写多语言支持,外部来源称主要为英文;README 的"多语言"说法存疑。
- 决定用 `Xenova/bge-m3`(1024 维),去掉 `embeddingUseTaskPrefixes`。更新 [[opencode-mem-值得调整的配置]]、[[opencode-mem-调研与上手指南]]。
- 未验证:中文召回的实际效果、模型首次下载。


## 2026-11-05 — learning | opencode-mem 值得调整的配置

- 新建 `learning/opencode/opencode-mem/opencode-mem-值得调整的配置.md`
- 依据 v2.41.0 的 example.jsonc、config.ts 默认值、README;按"必须改/建议改/看情况/不用管"分级,附推荐起步配置与验证方法
- 未验证:codebuddy 自定义 provider 能否做后台捕获、中文场景下相似度门槛取值

---

## 2026-11-05 — learning | opencode-mem 调研与上手指南

- 新建 `learning/opencode/opencode-mem/opencode-mem-调研与上手指南.md`
- 内容:OpenCode 记忆插件分类与星标、opencode-mem 对比 supermemory、检索与混合排序(0.5/0.3/0.2)、知识冲突与迭代(去重/保存时更新/dreaming/清理/画像)、安装部署、学习路线
- 依据 v2.41.0 源码与 README 整理;`flag` 矛盾标记的可见性、codebuddy provider 的适用性标为未确认
- 更新 index.md 学习区

---

## 2026-09-14 — dsh | 概念篇旧稿全量核查、修订与归档

- 对照官方文档（architecture / cordis-primer / agent-presets README / profile-boot.ts 等源码注释）逐篇核查 00–06
- 确凿错误已修：02 事件分发四种→五种（补 bail）；01 Bundle 三个→六个（补 sdk-app/acp-app/sdk-minimal）+ 配置叠加补 home 级层；04 preset 切换规则（仅新建会话可选、三来源表、code→ptc）；05 fail-closed 引文更正为官方测试用例名；00 stars 223k+、tui 示例、路线表
- 03/05 主体与官方时序图逐项吻合，无改动（仅 05 引文更正）
- 判定：随意写时期旧稿，不符合当前进度规范 → 整组移入 `learning/dsh/旧稿-仅供参考/`，正式路线以 dsh-learn 仓库 AGENTS.md 为准
- 4 张课程截图重命名为语义化文件名并挂接（arch-overview / car-metaphor → 00；four-objects / agent-assembly → 01），look_at 评估均为 dsh 特定或高价值通用概念图
- index.md dsh 段落改为状态说明；已提交 my-note@feature/dev `218a4cf`（未推送）
- 遗留：dsh-learn 仓库 7dafdfc 夹带 README 改动，已在 AGENTS.md 补记教训（暂存前必须逐文件核对 git status）；dark.txt / light.txt 为无关临时文件保持未跟踪

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
