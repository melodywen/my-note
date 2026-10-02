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
│   │       │   ├── _库.json
│   │       │   └── 仓库登记簿.md
│   │       ├── 10-史实/
│   │       │   └── @interact_ecology_agent_llm_server/   ← 第一级：仓库
│   │       │       ├── _追踪.md                           ← 追史游标
│   │       │       ├── 主进程启动/                        ← 第二级：主领域（代码层级）
│   │       │       │   └── 服务初始化与时序图.md
│   │       │       ├── 控制器层/                          ← 第二级：主领域
│   │       │       │   ├── HelloWorld 接口.md             ← 不需要子领域，直接放
│   │       │       │   └── OSD SSE 控制器/               ← 第三级：子领域（具体模块）
│   │       │       │       └── SSE 流式接口搭建.md
│   │       │       ├── 数据校验层/                        ← 第二级：主领域
│   │       │       │   └── 请求结构体定义与校验.md
│   │       │       ├── 服务层/                            ← 第二级：主领域
│   │       │       │   ├── 意图管理/                      ← 第三级：子领域
│   │       │       │   │   └── 意图识别与分发.md
│   │       │       │   └── 路由规划/                      ← 第三级：子领域
│   │       │       │       └── 新增荣耀意图路由.md
│   │       │       ├── 抽象层/                            ← 第二级：主领域
│   │       │       │   └── OSD 执行引擎.md
│   │       │       ├── 组件层/                            ← 第二级：主领域
│   │       │       │   └── tRPC Filter 体系.md
│   │       │       ├── 数据层/                            ← 第二级：主领域
│   │       │       │   └── 三级会话存储.md
│   │       │       ├── 数据定义层/                        ← 第二级：主领域
│   │       │       │   └── 核心模型与表结构.md
│   │       │       ├── 数据转换层/                        ← 第二级：主领域
│   │       │       │   └── 响应结构与 Translator.md
│   │       │       └── 配置层/                            ← 第二级：主领域
│   │       │           └── 生产环境配置补全.md
│   │       └── 20-快照/
│   │           └── @interact_ecology_agent_llm_server/
│   │               └── 当前能力.md
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

### 10-史实/ 的目录层级

史实目录从仓库到文件共三级，有内容才建目录，没内容不建空目录：

| 层级 | 格式 | 含义 | 举例 |
|------|------|------|------|
| 第一级 | `@<仓库名>/` | 仓库——一个仓库一个目录，`@` 前缀标记 | `@interact_ecology_agent_llm_server/` |
| 第二级 | `<主领域>/` | 主领域——按代码层级分，不是按功能或场景分 | `控制器层/`、`服务层/`、`数据层/` |
| 第三级 | `<子领域>/` | 子领域——具体模块名，只有内容多到需要拆时才建 | `意图管理/`、`路由规划/` |
| 文件 | `<场景文档>.md` | 场景文档或独立功能文档 | `HelloWorld 接口.md` |

主领域（代码层级）枚举：

| 主领域 | 对应代码什么部分 | 举例 |
|--------|------------------|------|
| 主进程启动 | 进程入口、初始化、注册、配置加载 | `main.go`、`start.sh` |
| 控制器层 | 路由注册、请求校验、控制器分发 | `controller/`、`interfaces/` |
| 数据校验层 | Request 类型定义、字段校验逻辑 | `request/`、`entity/request/` |
| 服务层 | 业务逻辑、领域服务 | `service/`、`logic/` |
| 抽象层 | 公共抽象、接口定义、设计模式 | `framework/`、`interfaces/` |
| 组件层 | 中间件、filter、钩子、插件 | `components/`、`middleware/` |
| 数据层 | 数据访问、持久化、缓存 | `repo/`、`store/` |
| 数据定义层 | 数据结构定义、模型实体、表结构映射 | `entity/`、`model/`、`domain/` |
| 数据转换层 | Response 类型定义、内部模型→外部响应转换（Translator） | `response/`、`translator/`、`entity/response/` |
| 工具层 | 工具函数、辅助方法 | `utils/`、`helpers/` |
| 配置层 | 配置结构、配置加载 | `conf/`、`entity/appstruct/` |
| 错误码 | 错误定义 | `entity/errcode/` |

组织规则：

1. 第一级是仓库——一个仓库一个目录，用 `@` 前缀标记
2. 第二级是主领域——按代码层级分，不是按功能分、不是按场景分
3. 第三级是子领域——具体模块名，只有当一个主领域下内容多到需要拆时才建
4. 不需要拆的直接放文件——一个主领域下只有一篇文档时，不建子目录
5. 抽取规则——一个功能独立且复杂才抽成独立文件，放到对应层级；简单的不抽，写进场景文档里

### 20-快照/ 的目录层级

快照目录结构与 `10-史实/` 平行，每个仓库一个目录，下面放当前能力概览：

```
20-快照/
└── @<仓库名>/
    └── 当前能力.md
```

### 层次说明

| 层级 | 目录 | 含义 |
|------|------|------|
| 第一层 | `<指纹>/` | 远端指纹（URL FNV-1a hash），一个远端一个目录 |
| 第二层 | `knowledge-base/` | 知识库自身的远端 working clone（git init + remote add） |
| 第二层 | `workspace/` | agent 工作区，与知识库克隆同级 |
| 第三层 | `knowledge-base/<vaultPath>/` | 库内容（00-总表/10-史实/20-快照），多个库各写各的子路径 |
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
