---
type: project
status: decided
area: dsh-plugin-dev
tags: [project, dsh, 知识库插件, storage, layout, 有出处]
created: 2026-09-27
updated: 2026-09-30
---

# 11 物理隔离与磁盘布局——三级目录与共享 clone

> [!info] 文档状态
> - 前置：[[08 检索与索引——FTS5基座与注入纪律]]、[[10 安全与权限——Scope硬边界与只读Git]]

## 一、待落位资产清单（前篇收拢）

| 资产 | 来自 | 约束 |
|---|---|---|
| vault（markdown 树） | 00/R4 | 库间物理隔离；Obsidian 可直接打开 |
| git clone | 03/10 | working clone（agent 可 checkout 读代码）；多库可绑同仓库 |
| 索引 .db | 08 | 不进 vault；可重建；每库一份 |
| 绑定登记 | 02 | 持久化、原子写、可重建 |

## 二、目录布局

```text
~/.dsh/knowledge-base/
├── f5118295/                             ← 远端指纹（URL 规范化后 hash）
│   ├── knowledge-base/                   ← 知识库克隆（远端 working clone）
│   │   ├── .git/                         ← git init + remote add origin
│   │   └── ecology_agent/                ← 库内容（vaultPath，多库共享同一远端各写各的子路径）
│   │       ├── 00-总表/
│   │       ├── 10-史实/
│   │       └── 50-草稿区/
│   └── workspace/                        ← 工作区（agent 追史时的 cwd）
│       ├── knowledge-base -> ~/.dsh/knowledge-base/f5118295/knowledge-base/ecology_agent/   ← 软链指向知识库内容
│       └── repos/                        ← 跟踪的仓库
│           ├── interact_ecology_agent_llm_server/   ← 仓库名（真实 git working clone）
│           ├── repo_B_name/              ← 仓库名（真实 git working clone）
│           └── repo_C_name/              ← 仓库名（真实 git working clone，跟几个放几个）
│
├── index/                                ← 索引：派生物，可删可重建
│   └── ecology-agent.db                 ← 每库一份 FTS5 索引
│
└── registry.json                         ← 库清单 + 绑定元组（唯一全局元数据）
```

### 层次说明

| 层级 | 目录 | 含义 |
|------|------|------|
| 第一层 | `<指纹>/` | 远端指纹（URL FNV-1a hash），一个远端一个目录 |
| 第二层 | `knowledge-base/` | 知识库自身的远端 working clone（git init + remote add） |
| 第二层 | `workspace/` | agent 工作区，与知识库克隆同级 |
| 第三层 | `knowledge-base/<vaultPath>/` | 库内容（00-总表/10-史实/50-草稿区），多个库各写各的子路径 |
| 第三层 | `workspace/repos/<仓库名>/` | 被跟踪仓库的真实 git working clone，跟几个就有几个 |
| 软链 | `workspace/knowledge-base` | 指向 `<指纹>/knowledge-base/<vaultPath>/`，agent 通过它读写草稿 |

### 关键路径说明

| 路径 | 作用 | 创建时机 |
|---|---|---|
| `<指纹>/knowledge-base/` | 知识库远端 working clone，多个库写同一远端各写各的子路径 | 建库时 |
| `<指纹>/knowledge-base/<vaultPath>/` | 库内容（markdown 树） | 建库时 |
| `<指纹>/workspace/` | agent session 工作区入口 | 追史时 |
| `<指纹>/workspace/knowledge-base` | 软链 → 库内容，agent 通过它读写草稿 | 追史时 |
| `<指纹>/workspace/repos/<仓库名>/` | 被跟踪仓库的真实 git working clone，agent 读代码 + 追史引擎读提交历史共用 | 追史时 |
| `index/<库id>.db` | FTS5 搜索索引 | 建库/重建时 |
| `registry.json` | 库清单（id、名称、类型、远端、vaultPath、repos 绑定、模型配置） | 建库时 |

## 三、关键设计决策

### 0. vault 自身 git 化

- **每个 vault 自身是一个 git 仓库**，建库时绑定**它自己的 Git 远端地址**（vault 的远端，非被追史仓库的）
- **写完即同步**：归档/快照更新/术语表变更后 commit + push 到该远端
- **同步策略**：自动 commit（本地）+ push 可配置（手动/自动）——vault 是自己的仓库，与 10 篇「绝不 push 被追史仓库」不冲突
- 多机 = 各自 clone/pull/push 同一 vault 远端；磁盘损坏远端有备份——**源资产有了备份层**
- registry/index 仍是本机缓存（可重建），不需要同步

### 1. knowledge-base/：库内容隔离

- R4「物理隔离」的落地：一个库 = 一个 vaultPath 子目录树，无跨库文件
- Obsidian 可直接打开 `<指纹>/knowledge-base/<vaultPath>/`（纯 markdown 树，无需导出导入）
- 库 rename 走 registry 同步

### 2. workspace/repos/：被跟踪仓库的 working clone

- 按仓库名称分子目录，跟几个仓库就有几个完整 git working clone
- agent 追史时 `git checkout <hash>` 读代码，追史引擎也在这里执行 `git log`/`git show` 读提交历史
- working clone 的 `.git` 已包含全部对象数据，无需单独维护 bare clone 缓存

### 3. index/：库名即文件名，一一对应

- 一个库一个 .db；「删除库」= 删库内容 + 删 db + registry 移除，干净
- `rebuild(库名)`：扫 `<指纹>/knowledge-base/<vaultPath>/` → 重建 index/<库id>.db

### 4. registry.json：唯一全局元数据

- 库清单（id/名称/类型：史官/方法论/习惯/API案例）+ 史官库的绑定元组 `(repo URL, subpath, branch, 主域)`
- 原子写（temp-then-rename）；损坏可从 knowledge-base/ 扫描重建（目录即真源，registry 也是缓存）

## 四、R4「物理隔离」的最终语义

| 维度 | 隔离方式 |
|---|---|
| 内容 | vaultPath 目录隔离——库 A 的操作碰不到库 B 的文件 |
| 检索 | 每库独立 .db；search 默认 scope=选中库，跨库是显式动作（10 篇） |
| git 访问 | 登记簿元组约束（10 篇 scope 硬边界） |
| 共享物 | 仅 workspace/repos/ 的 working clone（agent 读代码 + 追史引擎读历史共用）与插件进程本身 |

## 五、与 dsh storage subsystem 的关系

dsh 有 storage 子系统（hub/backend/domain/table，json/sqlite backend——能力扩展 03 篇）。**倾向自管目录**：vault（文件树）和 clone（working git 仓库）本就是 storage backend 表达不了的形态，索引跟着 vault 走比塞进统一 backend 更一致。`.dsh/knowledge-base/` 就是插件的天然 domain。

## 六、待议清单

1. registry.json 的 schema 细化（实现期）
