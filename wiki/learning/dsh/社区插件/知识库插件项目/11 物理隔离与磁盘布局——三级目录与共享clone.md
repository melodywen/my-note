---
type: project
status: discussing
area: dsh-plugin-dev
tags: [project, dsh, 知识库插件, storage, layout, 有出处]
created: 2026-09-27
updated: 2026-09-27
---

# 11 物理隔离与磁盘布局——三级目录与共享 clone

> [!info] 文档状态
> - 状态：**v1**（2026-09-27；目录全称 `knowledge-base`、共享 clone 待最终确认）
> - 前置：[[08 检索与索引——FTS5基座与注入纪律]]、[[10 安全与权限——Scope硬边界与只读Git]]

## 一、待落位资产清单（前篇收拢）

| 资产 | 来自 | 约束 |
|---|---|---|
| vault（markdown 树） | 00/R4 | 库间物理隔离；Obsidian 可直接打开 |
| git clone | 03/10 | bare（--no-checkout）；多库可绑同仓库 |
| 索引 .db | 08 | 不进 vault；可重建；每库一份 |
| 绑定登记 | 02 | 持久化、原子写、可重建 |

## 二、目录布局（命名裁定：**全称，不用 kb 缩写**，2026-09-27）

```text
~/.dsh/knowledge-base/                   ← 插件数据根
│
├── vaults/                              ← ① 源：每库一目录（物理隔离的基本单位）
│   ├── 我的项目库/
│   │   ├── 00-总表/…
│   │   ├── 10-史实/…
│   │   └── …
│   ├── 我的方法论与架构/
│   ├── 我的编码习惯/
│   └── API 调用案例/
│
├── repos/                              ← ② clone 缓存：按仓库指纹寻址，跨库共享（待确认）
│   └── <repo 指纹>/                    ← URL 规范化后 hash
│       └── repo.git/                   ← bare clone（只有 .git 对象，无工作区）
│
├── index/                              ← ③ 索引：派生物，可删可重建
│   ├── 我的项目库.db
│   ├── 我的方法论与架构.db
│   └── …
│
└── registry.json                       ← ④ 绑定登记：库清单 + 绑定元组
```

## 三、关键设计决策

### 0. vault 自身 git 化（2026-09-27 洞1 裁定）

- **每个 vault 自身是一个 git 仓库**，建库时绑定**它自己的 Git 远端地址**（vault 的远端，非被追史仓库的）
- **写完即同步**：归档/快照更新/术语表变更后 commit + push 到该远端
- **同步策略**：自动 commit（本地）+ push 可配置（手动/自动）——vault 是自己的仓库，与 10 篇「绝不 push 被追史仓库」不冲突
- 多机 = 各自 clone/pull/push 同一 vault 远端；磁盘损坏远端有备份——**源资产有了备份层**
- registry/repos/index 仍是本机缓存（可重建），不需要同步

### 1. vaults/：一库一目录，隔离即目录

- R4「物理隔离」的落地：一个库 = 一个目录树，无跨库文件
- Obsidian 可直接打开 `vaults/我的项目库/`（纯 markdown 树，无需导出导入）
- 库 rename 走 registry 同步

### 2. repos/：跨库共享 clone（AI 强烈倾向，待确认）

| | a. 共享（倾向） | b. 每库私有 |
|---|---|---|
| 磁盘 | 一仓库一份（30 库项目只存 1 份对象） | 30 份 |
| fetch | A 库拉过，B 库受益 | 各拉各的 |
| 隔离 | clone 是**只读缓存**（10 篇白名单），共享不破坏隔离——真正的隔离边界在 vault | 绝对隔离但无必要 |

**Go 类比**：共享 clone ≈ `$GOPATH/pkg/mod` 的 module cache——按内容寻址、全项目共享、只读，业界共识设计。

### 3. index/：库名即文件名，一一对应

- 一个库一个 .db；「删除库」= 删 vault + 删 db + registry 移除，干净
- `rebuild(库名)`：扫 vaults/库名 → 重建 index/库名.db

### 4. registry.json：唯一全局元数据

- 库清单（id/名称/类型：史官/方法论/习惯/API案例）+ 史官库的绑定元组 `(repo URL, subpath, branch, 主域)`
- 原子写（temp-then-rename）；损坏可从 vaults/ 扫描重建（目录即真源，registry 也是缓存）

## 四、R4「物理隔离」的最终语义

| 维度 | 隔离方式 |
|---|---|
| 内容 | vault 目录隔离——库 A 的操作碰不到库 B 的文件 |
| 检索 | 每库独立 .db；search 默认 scope=选中库，跨库是显式动作（10 篇） |
| git 访问 | 登记簿元组约束（10 篇 scope 硬边界） |
| 共享物 | 仅 repos/ 只读 clone 缓存（无隔离必要）与插件进程本身 |

## 五、与 dsh storage subsystem 的关系（⚠️ 实现期验证）

dsh 有 storage 子系统（hub/backend/domain/table，json/sqlite backend——能力扩展 03 篇）。**倾向自管目录**：vault（文件树）和 clone（bare git 仓库）本就是 storage backend 表达不了的形态，索引跟着 vault 走比塞进统一 backend 更一致。`.dsh/knowledge-base/` 就是插件的天然 domain。

## 六、待议清单

1. repos/ 共享 clone 的最终确认（a/b）
2. 插件根 `~/.dsh/knowledge-base/`：跟 dsh home 走可以吗？还是想放 `~/knowledge-base/`（家目录，方便直接逛）
3. registry.json 的 schema 细化（实现期）
