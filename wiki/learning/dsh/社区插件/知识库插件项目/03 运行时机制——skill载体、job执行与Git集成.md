---
type: project
status: discussing
area: dsh-plugin-dev
tags: [project, dsh, 知识库插件, runtime, skill, job, 有出处]
created: 2026-09-27
updated: 2026-09-27
---

# 03 运行时机制——skill 载体、job 执行与 Git 集成

> [!info] 文档状态
> - 状态：**讨论稿 v1**（2026-09-27）
> - 前置：[[02 内容模型——史官、快照、旁证与审阅闭环]]
> - 源码锚点：`~/ai-work/dsh/deepseek-harness/`（master `0d1f50007f`）

## 一、稳定提示词的机制落点（2026-09-27 核实后定稿）

### 三层组合

| 层 | 实体 | 职责 |
|---|---|---|
| **载体** | **skill**（bundled，随插件包分发） | 提示词模板 + few-shot 范文资源，版本化随插件发布——「稳定提示词」的物理宿主 |
| **执行者** | **Host 后台 job** | 管批次/游标/断点；读 skill 正文，装配上下文，发起生成 |
| **容器**（可选） | subagent 或直接 LLM 调用 | 单篇生成的一次性沙箱，跑完回收，**不持有人格** |

### skill：隐藏技能，版本化资产

**出处**：`docs/subsystems/skills.zh.md`（master `0d1f50007f`）

- skill 的定义：*"skill 是**可选的指令**而非会话事件"*
- 调用策略三元组 `SkillInvocationPolicy`：`{modelInvocable: false, userInvocable: false}` 时——*"这个 skill 只能由受信的 `ctx.skills.get()` 调用方获取"*——**模型看不见、用户看不见、不会乱触发**
- 本插件的 skill 配置即此：模型目录不出现、用户命令面板不出现，只有插件代码（job）能读
- **bundled 分发**：`dsh-skill-badge` 通过 `resourceBase` 公开随包资产目录的先例（skills.zh.md「本地发现优先级」节）；本插件的 skill 资产（SKILL.md + 范文）随 npm 包分发，走 bundled 根目录或插件内嵌提供方

### 为什么不是另外两个

| 候选 | 为什么不选 |
|---|---|
| Agent Preset（独立 Agent） | Preset 是**用户可切换、可对话的形态**，人格会被会话上下文污染；追史工人不该被对话，用户也不该「跟史官聊天」把它带偏 |
| 裸 subagent | subagent 委派时 prompt 由委派方**现拼**，没有模板锚就没有稳定性；subagent 至多作为单篇生成的执行容器 |

### 语义边界：代码驱动，非模型驱动

普通 skill（`modelInvocable: true`）触发权在**模型**——它看目录、自己决定何时加载。本插件反转为**代码驱动**：

- **生成时机**由 job 的游标/批次逻辑决定（确定性逻辑：增量检测）
- 模型在普通会话里**看不见**此 skill，永远不会乱触发
- 「什么时候写史」是确定性逻辑，不是模型自主决策——**系统行为可预测**的机制根源

> **Go 类比**：skill ≈ `embed` 进二进制的迁移模板（版本化只读资产）；job ≈ worker pool 的 orchestrator；subagent ≈ 一次性 goroutine；Preset ≈ 常驻服务进程——要前三个，不要第四个。

## 二、Host 后台 job 的编排职责

job 是整个用法一的 orchestrator，职责清单：

1. **读游标**：从 `00-总表/进度总表.md` + 各仓库主域的 `_追踪.md` 取追平状态
2. **Git 增量检测**：`git fetch` → 算增量 commits（快路径：master hash；兜底：patch-id 内容指纹，见 02 洞 F 决议）
3. **E3 批次计划生成**：产「本批 5 篇的标题 + commits + 变更性质」清单 → 通知人确认（第一道门）
4. **单篇生成**：逐篇装配上下文（该事件 diff + 该域近期史实 + 术语表 + skill 正文）→ 发起生成 → schema 校验 → 写归档路径 10-史实/
5. **节奏控制**：满 5 篇即停 → 徽章提醒（第二道门）
6. **归档执行**：人批准后草稿 → `10-史实`，更新 `_追踪.md` + 进度总表（同一原子动作）
7. **追平判定与快照触发**：全仓库追平 → 触发快照更新 job（同样走审阅）

**job 的持久化红利**（出处：`docs/subsystems/jobs.zh.md`，master `0d1f50007f`）：*"Registrations outlive producer and controller fibers"*——注册的生命周期比会话长，Web UI 关闭后 job 继续跑；徽章状态在下次打开面板时仍可读。符合「不慌、慢慢追」的产品节奏。

### ctx.jobs 的机制证据（2026-09-27 核验）

- **API**：`ctx.jobs` 即 `JobRegistry`（abstract seam）；`start(spec: JobStart): JobId` 返回 `<kind>-N` 品牌化 id；`list/get/read/stop` 管观察与取消
- **真实调用方**（源码逐字核验）：
  - `packages/shell/tool-bash/src/index.ts:364`——`jobs.start({ kind: 'bash', label, owner, run })`（本插件照抄此结构）
  - `packages/subagent/tool-subagent/src/index.ts:544`——后台 subagent 也走 jobs
  - 另有 `tool-pwsh:380`、`tool-terminal:255`
- **体验入口**：任何 dsh 会话里 `run_in_background` 跑长命令返回的 `bash-N` id 就是 `ctx.jobs` 体系

### owner 语义裁定（2026-09-27）

**追史 job 不设 owner（unowned job）**。理由：`tool-bash` 的 job 绑 `owner: exec.agent`——哪个会话点的归谁，agent 销毁即取消；但追史 job 是**知识库的资产**，不该随某个会话的生死而生死。文档原文：*"Omitting the owner creates an unowned job, open to any caller until service disposal"*——无主 job 开放给任何调用方，知识库面板是它的事实主人（启动、观察、取消都从面板走）。

```ts
// 插件内伪代码（结构照抄 tool-bash:364 真实调用）
const id = ctx.jobs.start({
  kind: 'knowledge-base-history',                    // 自定义 kind（JobKindMap 可合并扩展）
  label: `追史：repoA ${fromCommit}..HEAD`,
  // 注意：不传 owner —— unowned job，生命周期跟知识库走
  run: () => runHistoryBatch(vault, repo)
})
```

## 三、上下文装箱纪律（防爆炸的机制保证）

**按「单篇」装箱，不按「整库」装箱**：

```
单篇生成上下文 =
  skill 正文（提示词模板 + few-shot 范文）
+ 该事件的 commit diff（一个或多个 commit）
+ 该域最近若干篇已归档史实（近期上下文锚）
+ 术语表（全局共享，小文件）
+ 域 taxonomy（全局共享，小文件）
```

- **跨批上下文靠已归档文章传递**（「越归档越快」飞轮的技术本质：归档文章是跨批的上下文介质，而非对话记忆）
- 主会话不被污染；几千 commit 也不爆炸
- **schema 校验前置**：格式不合格的草稿进不了待审列表，自动打回重生成（省人的审阅带宽）

## 四、触发与可见性（2026-09-27 核验后新增）

### 定时触发：V1 不做（schedule 子系统的语义错配）

**核验结论**（出处：`docs/subsystems/schedule.zh.md`，master `0d1f50007f`）：schedule 子系统存在且支持 `after_seconds` / `at` / `every_seconds`（最小间隔 5 分钟）三种，**但标题即《仅限 Session 内的 Schedule》**——提醒「作为普通的后续对话轮次返回原 live Session」，作用域是 Session，不是知识库。

| 特性 | schedule 子系统 | 追史需要的 |
|---|---|---|
| 作用域 | Session 内（会话亡则提醒亡） | 知识库级（跨会话） |
| 触发后 | 往会话里发一条对话轮次 | 起 job、更新面板徽章 |

**裁定**：V1 **不做定时**。理由：①「满 5 篇停下等人审」本身就是天然节拍器——**审阅即触发**；②「检测远端新提交」更像 webhook/手动 fetch 模型，不是 cron 模型。后续如需「自动检测新提交提醒追史」，由插件 Host 侧自建间隔轮询（走 jobs + 面板徽章），不依赖 schedule 子系统的 session 语义。

### job 可见性：知识库面板为主观察面

**现成 UI**（出处：`packages/client/ui-jobs/README.zh.md`）：会话头部动作按钮 → 弹层列出本会话可见任务（每行显示 kind、label、状态、已耗时；角标计数运行中）。但它展示的是「本会话可见」视角（`jobsBySession` 镜像，别的会话的任务不出现）。

**裁定**：追史 job 的**主观察面是知识库面板自身**（unowned job 的事实主人）：显示 `knowledge-base-history-3 (running)`、批次进度、待审篇数徽章。会话头部的 jobs 弹层是顺路可见的次要观察面（unowned job 对非 agent 调用方可见，文档：*"a non-agent caller sees only unowned jobs"*；具体呈现实现期验证 ⚠️）。

## 四之二、失败降级（2026-09-27 洞3 裁定）

| 故障 | 处理 |
|---|---|
| job 跑一半挂（API 断/进程退） | **重跑**——从游标断点继续；归档过的文章不会重写（游标幂等，02-F 决议天然支撑） |
| 单 commit diff 超大爆 token | **不砍内容，拆多篇**：一个 commit id 允许多篇文章共享（「一篇一事」细化到 diff 分片）；Agent 分段读、分段写、边读边写，无需一口气读完再综合 |
| 5 篇全被审阅打回 | 回到批次计划（E3）重排，不算故障路径 |

## 五、Git 集成（建库与增量）

### 建库校验（R4/R5/R6）

- 绑定元组 = (URL, subpath, branch, 主域)，登记于 `00-总表/仓库登记簿.md`
- **建库冲突检测**：目标路径已存在 vault → 报错拒绝（防重复绑定）
- 知识库 ↔ 仓库**多对多**：多库可绑同一仓库（URL+subpath 区分）；一库可绑 N 个仓库（polyrepo）

### clone 策略（待讨论细化）

- ⚠️ 未验证待定项：浅克隆（`--depth`）是否够用——追史需要历史，但可以按需深化（`git fetch --deepen` 或 `--shallow-since`）
- clone 存放位置与共享策略（多库绑同仓库是否共享 clone）→ 归 [[04 物理隔离与磁盘布局]] 讨论

## 六、待拍板项（从 02 迁入 + 新增）

1. 激活入口：面板按钮为主 + 对话指令为辅？（AI 倾向：两者都要）
2. 生成模型：主会话同款，还是插件内可单独配置（便宜模型初稿/贵模型快照）？
3. E3 批次计划确认与 5 篇终审**两道门**都走面板徽章？（AI 倾向：是）
4. skill 资产的具体分发形态：bundled 根目录 vs 插件内嵌提供方（实现期验证）
5. 定时触发 → 已裁定 V1 不做（见第四节）；后续如需「自动检测新提交」，插件 Host 侧自建轮询 + jobs + 面板徽章

## 七、下一步

- 拍板第六节 → 用法一机制封版
- [[04 物理隔离与磁盘布局]]（clone 存放、多库共享、storage domain 设计）
- [[05 检索与索引]]（学习者预留的单独讨论）
