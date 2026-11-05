---
type: concept
status: developing
area: growth
title: "opencode-mem 调研与上手指南"
created: 2026-11-05
updated: 2026-11-05
tags:
  - learning
  - opencode
  - opencode-mem
  - 记忆插件
  - 向量检索
related:
  - "[[oh-my-openagent.json-小白配置详解]]"
  - "[[Oh-My-OpenAgent-实战搭配使用指南]]"
---

# opencode-mem 调研与上手指南

> 一句话:**opencode-mem 是给 OpenCode 装的"长期记忆"插件。你正常干活,它在后台把值得记的东西存到本机,下次聊天时把相关的几条自动塞回上下文。**
>
> 本文基于 v2.41.0 的源码(仓库 `tickernelz/opencode-mem`)和 README 整理。凡是"读过源码确认"的会写明,没确认的也会写明。

---

## 一、先搞清楚:OpenCode 有哪些记忆插件

按"记什么、怎么记"粗分四类:

| 类型 | 做什么 | 例子 |
|---|---|---|
| 精选记忆 | 把重要结论存下来,以后按需找回 | opencode-mem、opencode-supermemory、agent-memory、true-mem、simple-memory |
| 活动日志 | 记录你做过的每一步,事后能翻 | codemem、open-mem、opencode-lcm |
| 情景回忆 | 把过去的会话整段存起来,以后检索 | episodic-memory |
| MCP 形式 | 不是插件,是外挂服务 | mem0、agentmemory、memsearch 等通用项目 |

### GitHub 星标(调研当天实测)

| 项目 | 星标 | 备注 |
|---|---|---|
| tickernelz/opencode-mem | 1.8k | OpenCode 专用插件里最高 |
| supermemoryai/opencode-supermemory | 1.7k | 数据存云端 |
| agent-memory | 357 | |
| true-mem | 214 | |
| simple-memory | 148 | |
| codemem | 80 | |
| claude-memory | 78 | |
| opencode-lcm | 76 | |
| open-mem | 29 | |
| 其余几个 | 个位数 | |

通用项目 mem0(68k)、agentmemory(30k)、memsearch(2.8k)不是专为 OpenCode 做的,**星标不能直接和上面比**。

---

## 二、opencode-mem 和 opencode-supermemory 怎么选

| | opencode-mem | opencode-supermemory |
|---|---|---|
| 数据存哪 | **你的电脑本地** | **云端**(Supermemory 服务) |
| 费用 | 免费;但自动提取要消耗你配置的模型的 token | 插件免费,服务按积分计费 |
| 账号 | 不需要 | 需要账号和 API Key |
| 怎么提取记忆 | 会话空闲后,后台用你配的模型总结 | 把对话**原文**发到云端,由服务端提取 |
| 额外功能 | 网页管理界面、用户画像、去重、整理 | 项目知识库、代码库索引 |
| 平台限制 | **不支持 Intel Mac**、Alpine | 无明显限制 |

### 各自的已知问题

**opencode-mem**
- 曾经磁盘膨胀:画像学习把自己的分析提示词又当成用户输入存起来,越滚越大(issue #176)。**源码里已有过滤**(`src/index.ts:55` 过滤 `# User Profile Analysis`),这条已修。
- 向量搜索曾经很慢(按项目过滤要 8 秒),PR #259 修到约 29ms,已合并。
- OpenCode 1.3.x 时期曾"静默加载失败",现在已有 v1/v2 双入口。
- 自动提取需要额外配一个能返回结构化输出的模型,Claude Pro/Max 的 OAuth 不能直接复用。

**opencode-supermemory**
- 隐私:对话原文默认上传云端。
- 压缩时机不对:查不到模型上限时回退到 200K,大上下文模型会过早压缩(#85、#88)。
- 写入超时后会重发,产生重复记忆(#106)。
- 多项目下只有最后加载的位置保留工具(#104)。

### 我的结论

**倾向 opencode-mem**:数据不出机器,这对用公司内网工具的人是硬条件。supermemory 会把含源码片段、内部路径的对话原文发到第三方云端,**不建议用在公司代码上**。

> [!warning] 两者共同的风险
> 都依赖 OpenCode 的插件接口。OpenCode 升级后都出现过"悄悄失效",升级后要确认记忆还在写入。

---

## 三、它是怎么"找记忆"的(检索)

### 大白话版

主要靠**按"意思"找**。你问"之前登录是怎么处理的",记忆里不必出现"登录"这两个字,意思相近的也能找到。在此基础上有两个补充:

1. **关键词加分**:你输入的词刚好出现在记忆里,排名往前。
2. **按时间取最近几条**:不管相关不相关,直接拿最近存的。是备用方案。

### 具体流程(读源码确认,`src/services/turso/vector-search.ts`)

1. 把你的问题用本地模型转成一串数字(向量)。
2. 数据库里**逐条精确计算**相似度(`vector_distance_cos`),不是近似算法。
3. 每条候选记忆打三个分:

| 分数 | 含义 |
|---|---|
| 内容语义分 | 记忆正文和问题"意思有多接近" |
| 标签分 | 每条记忆有几个主题标签。取"标签的意思接近度"和"你的词命中标签的比例"里**较大的** |
| 关键词分 | 你的每个词在正文或标签里出现一次加 1/词数 |

4. 合成:

```
最终分 = 内容语义分 × 0.5 + 标签分 × 0.3 + 关键词分 × 0.2
```

没有可用关键词时:内容 × 0.6 + 标签 × 0.4。

5. 超过相似度门槛(默认 0.6)的,按分数从高到低取前 N 条。

### 用的是什么技术

| 部分 | 实现 |
|---|---|
| 语义匹配 | 数据库 Turso 自带的 `vector_distance_cos`,逐条精确算 |
| 关键词匹配 | SQL 的 `LIKE '%词%'`,**只是"包含这个词"**,没有 BM25,没有全文索引(因为所用数据库没有 FTS5) |
| 向量模型 | 默认本地 `Xenova/nomic-embed-text-v1`,768 维。README 称"多语言",但 Hugging Face 官方页未写,多个外部来源称其主要为英文;**中文用户建议换 `Xenova/bge-m3`(1024 维)**,见 [[opencode-mem-值得调整的配置]] |
| 分词 | 只按空格、逗号、点、下划线、斜杠、连字符切;最多 16 个词,单字被丢弃 |

### 这对你意味着什么

- **语义占大头**(内容 + 标签共 80%),关键词只占 20%。
- **中文提问时,关键词这一项基本拿不到分**:一整句中文没有空格,会被当成一个超长的词,必须整串原样出现才算命中。所以中文主要靠语义。
- **标签占 30%**,存记忆时标签生成得好不好,会明显影响排序。
- 精确匹配函数名、错误码这类场景,不如纯关键词方案。

### 检索什么时候发生

| 设置 `chatMessage.recall` | 行为 |
|---|---|
| `relevant`(默认) | 每次发消息,按意思找相关记忆 |
| `recent` | 直接注入最近 N 条 |
| `both` | 先注入相关的,不够再用最近的补满 |

- 自动注入默认最多 3 条(`chatMessage.maxMemories`)。
- 手动检索:让 agent 调 `memory({mode: "search", query: "..."})`。
- 范围:默认只查当前项目;可设成查所有项目。项目靠所在 git 仓库识别,可用根目录的 `.opencode-mem-project` 文件覆盖。

---

## 四、知识冲突怎么处理、怎么迭代

> [!important] 先说结论
> **默认配置下,它基本不处理冲突。** 新旧矛盾的两条记忆会同时留着。想让它处理,要自己打开两个开关,而且这两个都要消耗模型 token。

以下全部来自源码。

### 4.1 默认状态到底发生了什么

自动捕获时,`updateOnCaptureEnabled` 默认是 `false`,代码只做一件事:**直接新增一条**(`persistAutoCaptureMemory` 里走 `addMemory`)。它不会先看看库里有没有相似或矛盾的旧记忆。

所以,你上周记了"用 Redis 做缓存",这周改成"用本地内存缓存",两条会并存。检索时两条都可能被召回。

### 4.2 能打开的三层机制

| 层 | 开关(默认) | 什么时候跑 | 做什么 |
|---|---|---|---|
| 去重 | `deduplicationEnabled`(开) | **只在网页管理界面手动触发** | 删完全相同的;相似的只出报告 |
| 保存时更新 | `updateOnCaptureEnabled`(**关**) | 每次自动保存新记忆时 | 让模型判断:新增、改写旧的、还是取代旧的 |
| 定期整理(dreaming) | `dreaming.enabled`(**关**) | 每 24 小时 | 找相似的一组记忆,让模型合并、取代,或标记矛盾 |

#### 去重(最基础)

- 内容**完全一样**的:只留最新一条,其余**直接硬删**。
- 相似度 ≥ 0.9 但不完全一样的:归为"近似重复组",**只返回报告,不自动删**,留给你判断。
- 注意:这个不是后台自动跑的,要在网页界面(`http://127.0.0.1:4747`)里触发(接口 `POST /api/deduplicate`)。

#### 保存时更新(update-on-capture)

流程:
1. 拿新记忆去搜相似的旧记忆(相似度门槛 `updateOnCaptureSimilarityThreshold` 默认 0.75,候选最多 `updateOnCaptureMaxCandidates` 默认 5 条)。
2. **置顶的记忆先被排除**,不参与。
3. 让模型三选一:
   - `add`:新增,旧的不动
   - `update`:原地改写旧记忆
   - `supersede`:存一条新的,把旧的**软删除**,并在元数据里记 `supersededBy`
4. 提示词的原则是**拿不准就 add**。

安全兜底:目标 id 无效、目标已置顶、模型判断失败,全部回退成 `add`;`supersede` 里软删旧记忆失败,会把刚存的新记忆回滚。

#### 定期整理(dreaming)

默认关闭。打开后:

| 参数 | 默认 | 含义 |
|---|---|---|
| `intervalHours` | 24 | 多久跑一次 |
| `maxGroupsPerRun` | 5 | 每次最多处理几组 |
| `relatedThreshold` | 0.75 | 多相似才分到一组 |
| 每组上限 | 5 条 | `DREAMING_MAX_GROUP_SIZE` |
| `crossProject` | false | 不跨项目;用户级记忆永不和项目级混合 |
| `trashRetentionDays` | 30 | 被淘汰的记忆在回收站放多久 |

对每一组,模型从五个动作里选:

| 动作 | 效果 |
|---|---|
| `merge` | 合并成一条,保留的那条记 `mergedFrom` |
| `update` | 改写保留的那条 |
| `supersede` | 用新的取代旧的,旧的记 `supersededBy` |
| `keep` | 都留着 |
| **`flag`** | **无法判断谁对谁错的矛盾**:不改内容,只在两条记忆的元数据里写 `contradictionWith`、`contradictionReason`、`contradictionFlaggedAt` |

要点:
- 被淘汰的记忆是**软删进回收站**,30 天后才真删,有后悔期。
- **置顶的记忆永远不动。**
- 整轮全部失败时,不会推进"上次运行时间",下次会重试。
- 要求已配好 `opencodeProvider` 和 `opencodeModel`。

> [!warning] 我没确认的一点
> `flag` 写入的矛盾标记,我在源码里只搜到"写入"的地方(`dreaming-service.ts:465-467`),没搜到任何读取或展示它的代码。也就是说,**标记了矛盾,但可能没有任何界面会提醒你**。是否能在网页界面里看到,我没有实际验证。

### 4.3 "迭代":旧知识怎么更新、怎么过期

迭代靠以下几条路径,不是一个统一机制:

1. **改写**:`update` 动作原地改旧记忆,并刷新 `updated_at`。
2. **取代**:`supersede` 软删旧的、存新的。
3. **自动清理**(`autoCleanupEnabled` 默认**开**):`updated_at` 早于保留期(`autoCleanupRetentionDays` 默认 30 天)且**没置顶**的记忆,会被**硬删**。每天最多跑一次。
   - 这是**默认状态下旧知识"过期"的主要途径**。
   - 被改写过的记忆会刷新 `updated_at`。**被搜索命中或被注入到对话里不算更新**(源码里没有"最近使用"字段),所以天天用但从没改过的记忆,到期也会被删,只有置顶能避免。
4. **手动**:`memory` 工具有 `forget` 模式;网页界面可以删除,也可以**置顶**(`POST /api/memories/:id/pin`)。置顶后既不被自动改写,也不被清理。

> [!tip] 对你的启发
> 默认 30 天不更新就删,意味着"长期有效"的重要结论(例如项目架构约定)要**手动置顶**,否则 30 天后会消失。反过来,过时的错误结论如果一直被召回,又不会被自动发现。

### 4.4 用户画像:冲突是"降权",不是"删除"

用户画像(你的偏好、习惯)是另一套逻辑。每累计一定数量的提问(`userProfileAnalysisInterval` 默认 10)会触发一次。至少有 5 条偏好时,会让模型检查旧条目是否还符合最近的行为,结论五选一:

| 结论 | 对置信度的影响 |
|---|---|
| `confirmed`(得到证实) | α + 0.5 |
| `contradicted`(被推翻) | α × 0.75,β + α × 0.25 |
| `inaccurate`(不准确) | α × 0.6,β + α × 0.4 |
| `oversimplified`(过于简化) | α × 0.85,β + α × 0.15;证据 ≥ 3 条时重写描述 |
| `no_evidence`(没证据) | 不变 |

(用 Beta 分布的 α 和 β 记录"对"和"错"的证据,置信度由此算出。)

大白话:**画像里的某条偏好被新行为推翻,不会立刻被删,而是信心值逐步降低。** 偏好变了,会慢慢淡出。

### 4.5 小结表

| 场景 | 默认会怎样 | 要想解决怎么办 |
|---|---|---|
| 新旧结论矛盾 | 两条并存 | 打开 `updateOnCaptureEnabled` |
| 完全重复 | 不自动处理 | 在网页界面手动跑去重 |
| 近似重复 | 不自动处理 | 看去重报告后手动删 |
| 长期没更新 | 30 天后硬删 | 重要的要置顶 |
| 无法判断的矛盾 | 不处理 | 打开 dreaming,会标记,但标记是否可见未确认 |
| 画像条目过时 | 信心值逐步下降 | 无需操作 |

---

## 五、怎么安装部署

### 5.1 先看你的环境(2026-11-05 实测)

| 项目 | 状态 |
|---|---|
| 芯片 | arm64(Apple Silicon),**满足要求** |
| OpenCode | v2.2.5 |
| bun / node | 1.3.14 / v24.14.0 |
| 配置文件 | `~/.config/opencode/opencode.jsonc`,已有 `plugins` 数组 |
| `~/.opencode-mem` | 还不存在(没装过) |

> [!warning] 不要在 Intel Mac 上装
> README 明确写了 `darwin/x64` 不支持(数据库和 onnxruntime 都没有 x64 原生模块)。

### 5.2 安装步骤

**第 1 步:在 `opencode.jsonc` 的插件数组里加一项**

OpenCode v2 里字段名是 `plugins`(v1 是 `plugin`)。你现有的是:

```jsonc
"plugins": [
  "superpowers@git+https://github.com/obra/superpowers.git",
  "oh-my-opencode-slim"
],
```

改成:

```jsonc
"plugins": [
  "superpowers@git+https://github.com/obra/superpowers.git",
  "oh-my-opencode-slim",
  "opencode-mem@latest"
],
```

**第 2 步:重启 OpenCode。**
首次启动会:
- 自动生成配置文件 `~/.config/opencode/opencode-mem.jsonc`(带注释的模板)
- 下载本地向量模型(默认存在 `~/.opencode-mem/data/.cache`,体积几百 MB 到 1–2 GB,运行时占内存约 0.5–2GB)
- 需要联网

**第 3 步:配置"自动捕获"用的模型(最关键)**

自动捕获要在后台调用一个模型来总结。没配好会空转重试、白烧 token。编辑 `~/.config/opencode/opencode-mem.jsonc`:

```jsonc
// 推荐写法:用 opencode 里已登录的 provider
"opencodeProvider": "你的provider名",
"opencodeModel": "你的模型名",

// 或者直接沿用当前会话的模型
// "opencodeModel": "inherit",
```

注意:
- `opencodeProvider` 必须是 `opencode providers list` 里有的名字(我在你机器上没拿到列表输出,请自己运行确认)。
- 模型必须支持**结构化 JSON 输出 / 工具调用**。
- 官方的免费/Zen 模型(provider id 为 `opencode`,如 `big-pickle`)通常不能用于自动捕获。
- 你的 `opencode.jsonc` 里有自定义 provider `codebuddy`(包含 claude-haiku-5.5 等模型)。**能不能用于自动捕获,我没验证**,要试。建议选便宜、快的小模型,因为是后台高频调用。
- 可选 `"opencodeVariant"` 指定推理强度。

**第 4 步:验证**

1. 重启 OpenCode,正常干一会儿活,然后让会话空闲。
2. 打开 `http://127.0.0.1:4747`(网页管理界面),看有没有新记忆。
3. 看 `~/.opencode-mem/` 目录是否生成了数据。
4. 在对话里让 agent 调 `memory` 工具试一次 add 和 search。

### 5.3 几个值得考虑的可选项

| 想做什么 | 配置 |
|---|---|
| 处理新旧冲突 | `updateOnCaptureEnabled: true`(见第四节) |
| 定期整理 | `dreaming.enabled: true`,同时要配好 provider |
| 加强隐私 | `databaseEncryptionEnabled`(数据库加密) |
| 给网页界面加密码 | HTTP Basic Auth |
| 让记忆变成可读文件 | `memoryBackend` 选 markdown vault(**v2.41.0 本机实测会让网页崩溃,不建议开**,详见《值得调整的配置》第 12 节) |
| 多个仓库共享一份项目记忆 | 在仓库根放 `.opencode-mem-project` |
| 减少注入量 | 调小 `chatMessage.maxMemories` |
| 调整召回松紧 | 调 `chatMessage.similarityThreshold`(默认 0.6,中英混用时需要观察) |

### 5.4 想还原时

- 把 `plugins` 里的 `opencode-mem@latest` 删掉,重启。
- 数据在 `~/.opencode-mem/`,不需要时可以删除。

---

## 六、我该怎么学习和配置(建议路线)

按"先跑起来、再调好、最后深挖"的顺序:

### 第 1 阶段:跑起来(约半天)
1. 按第五节安装,只配 provider,**其他全保持默认**。
2. 正常使用 2–3 天。
3. 每天看一次网页界面:它存了什么?存得对不对?标签好不好?

### 第 2 阶段:看效果、调参数(约一周)
重点观察三件事:

| 问题 | 看什么 | 调什么 |
|---|---|---|
| 注入的记忆没用 | 注入了哪几条,相关吗 | `similarityThreshold`、`maxMemories` |
| 存了太多废话 | 网页里的记忆质量 | 提示词相关配置、换更强的 provider 模型 |
| 重要结论消失 | 30 天后是否还在 | 手动置顶,或调保留天数 |

### 第 3 阶段:处理冲突和迭代
- 发现新旧矛盾后,先试 `updateOnCaptureEnabled: true`,观察一周。
- 觉得库里太乱,再试 `dreaming`。
- **每次只改一个开关**,否则不知道是谁起的作用。

### 第 4 阶段:深挖(可选)
想理解原理,按这个顺序读源码:

| 想了解 | 看哪个文件 |
|---|---|
| 检索与混合排序 | `src/services/turso/vector-search.ts`(104–254 行) |
| 分词 | `src/services/turso/vector-utils.ts`(73–90 行) |
| 自动捕获 | `src/services/auto-capture.ts` |
| 保存时更新 | `src/services/update-on-capture.ts` |
| 定期整理 | `src/services/dreaming-service.ts` |
| 去重 | `src/services/deduplication-service.ts` |
| 自动清理 | `src/services/cleanup-service.ts` |
| 用户画像 | `src/services/user-memory-learning.ts` |
| 全部配置项和默认值 | `src/config.ts`、`opencode-mem.example.jsonc` |

仓库地址:https://github.com/tickernelz/opencode-mem
(同名的 `kunickiaj/opencode-mem` 是另一个项目,已改名 codemem,别搞混。)

---

## 七、还没弄清的问题

- `flag` 标记的矛盾在哪里能看到(网页界面是否展示)。
- `codebuddy` 这个自定义 provider 能否胜任自动捕获。
- 中文场景下的实际召回质量(关键词项基本失效,全靠语义,需要实测)。
- 本地模型下载的实际体积和内存占用,以你机器上的实测为准。
- 本文的源码结论基于 v2.41.0,升级后默认值可能变化。

## 相关页面

- [[oh-my-openagent.json-小白配置详解]]
- [[Oh-My-OpenAgent-实战搭配使用指南]]
- [[opencode-mem-值得调整的配置]]
