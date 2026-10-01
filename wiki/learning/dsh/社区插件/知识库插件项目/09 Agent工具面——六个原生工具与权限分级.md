---
type: project
status: discussing
area: dsh-plugin-dev
tags: [project, dsh, 知识库插件, tools, 有出处]
created: 2026-09-27
updated: 2026-09-27
---

# 09 Agent 工具面——六个原生工具与权限分级

> [!info] 文档状态
> - 状态：**v1**（2026-09-27，三项分叉已拍板：① run_task 要 ② browse 单拆 ③ adopt 面板专属）
> - 前置：[[03 运行时机制——skill载体、job执行与Git集成]]、[[08 检索与索引——FTS5基座与注入纪律]]

## 一、架构裁定：原生工具，非 MCP（2026-09-27 确认）

**`ctx.tools.register` 原生注册**，不做 MCP server。理由：

1. **同进程**：消费者是 dsh 会话自己，工具调用 = 函数调用；MCP 是跨应用协议，独立进程 + 序列化开销，为不存在的跨客户端需求付费
2. **依赖 cordis 服务**：实现要调 `ctx.jobs`（起 job）、`ctx.skills`（读模板）、storage subsystem（索引）、会话事件（2b 观察）——MCP server 进程摸不到这些
3. **UI 同源**：工具、面板、job 共享同一份 Host 服务状态，天然一致；MCP 会把工具（外部进程）和面板（dsh 插件）劈成两半
4. **安全面**：原生工具走 dsh 三层防线（沙箱→权限预设→审批）；MCP 要自己重造

**未来可选**：知识库要被 dsh 之外客户端用（如 Claude Code 查库）时，再包一个 MCP server 壳复用 `knowledge_base_*` 工具面——记下不阻塞。

## 二、工具清单（6 个，全部 `ctx.tools.register`；命名裁定：**全称 knowledge_base_ 前缀，不用 kb 缩写**，2026-09-27）

| 工具 | 模型可见 | 面板 | 职责 |
|---|---|---|---|
| `knowledge_base_search(scope, query, limit?)` | ✅ | ✅（搜索框） | 跨库检索，返回摘要行（标题+路径+snippet）；查询先过术语表扩展再进 FTS5 |
| `knowledge_base_read(path)` | ✅ | ✅（点击即读） | 读全文（两级火箭第二级）；受单次注入上限约束 |
| `knowledge_base_browse(what, target)` | ✅ | ✅ | 浏览结构：能力域清单 / 进度游标 / 术语表 / 库清单——**与 search 心智分离**（看结构 vs 找内容） |
| `knowledge_base_submit(库, 类型, 内容)` | ✅ | ✅（手动添加） | **统一显式提交入口**：好代码片段/方法论/API 案例/编码习惯主动声明、旁证存储——参数区分类型，直接写归档路径 |
| `knowledge_base_run_task(任务类型, 目标)` | ✅ | ✅（主入口） | 会话侧起 job：追史/归纳习惯（面板按钮为主、对话指令为辅——03 遗留项就此落定） |
| `knowledge_base_adopt(草稿id, 修订?)` | ❌ **面板专属** | ✅ | 审阅归档（批准/打回）——**人的主权动作**，模型不可代批 |

**非工具的钩子**：2b 编码习惯的会话观察走**事件监听**（Host 侧监听提交事件，非模型工具调用）；生成侧 skill 隐藏（03 篇已定）。

## 三、权限分级逻辑

```
模型可调（4+1）           人专属（面板）
├─ knowledge_base_search  只读        └─ knowledge_base_adopt  写正式区的主权动作
├─ knowledge_base_read    只读
├─ knowledge_base_browse  只读        理由：审阅闭环的最后一道闸必须是人亲手点——
├─ knowledge_base_submit  写归档路径      「批准」若模型可调，等于模型能自我批准，
└─ knowledge_base_run_task 起 job       human-in-the-loop 就在最后一厘米失守
```

**Go 类比**：工具分级 = RPC 权限面——查询接口开放服务层，approve 类管理接口只留 admin 面板。

## 四、与其他篇的咬合

| 篇 | 咬合点 |
|---|---|
| 03 | `knowledge_base_run_task` → `ctx.jobs.start`（kind: kb-history / kb-habit）；生成 skill 隐藏 |
| 08 | `knowledge_base_search`/`knowledge_base_read` = 两级火箭；习惯库全量注入例外 |
| 02/04 | `knowledge_base_submit` → 写归档路径 → 审阅 → `knowledge_base_adopt` 确认归档（面板）→ 索引刷新 |
| 06 | 2b 观察钩子 = 事件监听（非工具） |
| 01 | 面板侧同款能力（搜索框/手动添加/审阅按钮）共享 Host 服务 |

## 五、待议清单

1. `knowledge_base_read` 的注入上限具体值（08 篇遗留，联动）
2. `knowledge_base_submit` 的类型参数 schema 细化（各库 frontmatter 校验）
3. 面板审阅界面的修订编辑能力（打回时可附意见？）
