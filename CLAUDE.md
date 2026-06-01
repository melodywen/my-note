# my-note: 个人知识库 (LLM Wiki)

Mode: Mode D（个人第二大脑 / Second Brain）
Purpose: 积累并跟踪个人目标、学习、人脉、生活领域与资源的结构化知识库
Owner: melodycchen
Created: 2026-06-01

## Structure

```
vault/
├── .raw/              # 原始素材：日记、文章、播客笔记、语音转录
├── wiki/
│   ├── index.md       # 主目录
│   ├── log.md         # 操作日志（仅追加）
│   ├── hot.md         # 热缓存（~500 字最近上下文）
│   ├── overview.md    # 知识库总览
│   ├── goals/         # 个人与职业目标，含进度跟踪
│   ├── learning/      # 正在掌握的概念、技能成长
│   ├── people/        # 关系、共享背景、待跟进
│   ├── areas/         # 生活领域：健康、财务、职业、创作
│   ├── resources/     # 值得参考的书、课程、工具
│   ├── sources/       # 每个原始素材的摘要页
│   ├── questions/     # 已归档的问题解答
│   └── meta/          # 仪表盘、体检报告、约定
├── _templates/        # 各类型笔记模板
└── CLAUDE.md
```

## Conventions

- 所有笔记使用 YAML frontmatter：type, status, created, updated, tags（最少）
- 双向链接用 [[Note Name]] 格式：文件名唯一，无需路径
- .raw/ 存放原始素材：永不修改
- wiki/index.md 是主目录：每次摄入时更新
- wiki/log.md 仅追加：永不编辑历史条目，新条目放最上方
- 交互语言：中文

## Operations

- 摄入(Ingest)：把素材放入 .raw/，说 "ingest [文件名]"
- 查询(Query)：直接提问，先读 index 再深入
- 体检(Lint)：说 "lint the wiki" 运行健康检查
- 归档(Archive)：把冷素材移到 .archive/ 保持 .raw/ 整洁
