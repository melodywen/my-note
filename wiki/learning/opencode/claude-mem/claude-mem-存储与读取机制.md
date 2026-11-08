---
type: concept
status: developing
area: growth
title: "claude-mem 存储与读取机制"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - claude-mem
  - 存储
  - 检索
related:
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-跨端共享]]"
  - "[[claude-mem-深入调研]]"
---

# claude-mem 存储与读取机制

> 一句话:**一条记忆先完整存进一个 SQLite 数据库(这是"真相"),再拆成几段文字复制一份到向量库 Chroma 里(这是"按意思找"的索引);搜索时先按意思找,按意思找不到的类别再用关键词补查。中文两层都偏弱:按意思那层默认模型是英文的,关键词那层不会切汉字,只能退化成子串匹配。**
>
> 本篇读的是 `/tmp/claude-mem` 源码(main 分支,`package.json` 版本 15.12.0,commit `3ab6e1a21`)。**没有实测**,也没有在本机跑过 worker。凡是标"未证实"或"推断"的,不要当结论用。

---

## 一、先认几个词

| 术语 | 大白话 |
|---|---|
| 观察(observation) | claude-mem 里"一条记忆"的单位。由 LLM 看完你的一轮操作后总结出来,有标题、副标题、叙述、若干事实、概念标签、涉及的文件(SessionStore.ts 的 `observations` 表,见第四节) |
| SQLite | 一个单文件数据库。claude-mem 把所有数据放在 `claude-mem.db` 里(paths.ts 约 57-68 行,默认目录 `~/.claude-mem`,约 26 行) |
| FTS5 | SQLite 自带的"全文检索"功能。把文字切成词建索引,按词查,能按相关度排序(SessionSearch.ts 的 `observations_fts`,约 256 行) |
| 向量 / 嵌入(embedding) | 用模型把一段文字变成一串数字(这里是 384 个数,models.ts 的 `dims`)。意思相近的文字,数字串也相近,所以能"按意思找" |
| Chroma | 一个专门存向量、按相似度查向量的数据库。claude-mem 本地默认通过 `chroma-mcp` 子进程调用它(ChromaMcpManager.ts,数据在 `paths.chroma()`,即 `~/.claude-mem/chroma`,paths.ts 约 150 行) |
| LIKE 子串匹配 | SQL 里的 `column LIKE '%某串%'`:只要某列的文字里原样包含这串字就算命中。不分词、不算相关度 |

---

## 二、一张图:一条记忆怎么写进去、怎么读出来

### 写入(一条观察诞生之后)

```
LLM 总结出一条 observation
        |
        v
[1] 写 SQLite  observations 表(完整的一行,权威数据)
        |   同时由触发器自动写进 observations_fts(FTS5 关键词索引)
        v
[2] 异步同步到 Chroma(失败不影响 [1],失败的行记为"待补"以后重试)
        |   拆成多个"向量文档":narrative / text / 每条 fact 各一个;
        |   三者都没有时才退而用 title+subtitle 一个
        v
    Chroma 用自己的嵌入模型把每段文字变成向量并存起来
```

### 读出(你搜一个词)

```
搜索请求(带 query 文字)
        |
        v
没有 query、只有过滤条件?  --是-->  直接查 SQLite,结束
        |否
        v
Chroma 开着(默认开)?  --否-->  只走 SQLite:
        |是                      含汉字 -> 多列 LIKE 子串匹配
        v                        不含汉字 -> FTS5 关键词(再不行逐级放宽)
[1] Chroma 按意思取一批最近的向量文档
[2] 丢掉早于"最近 N 天"的(默认 90 天;你给了日期范围就以日期范围为准)
[3] 按 sqlite_id 回 SQLite 取完整行,按 观察/摘要/用户提问 三类分组
        |
        v
[4] 某一类是空的?
      三类全空  -> 整个改走 SQLite 搜(不限天数)
      部分空    -> 只给空的那几类用 SQLite 补(不限天数),其余保留 Chroma 结果
      都有结果  -> 直接返回
```

### 各环节对照表

| 环节      | 谁负责                                | 能不能搜中文    | 源码位置                                            |
| ------- | ---------------------------------- | --------- | ----------------------------------------------- |
| 存完整内容   | SQLite `observations` 表            | 不涉及搜索     | SessionStore.ts 约 1299、1876 行                   |
| 关键词索引   | FTS5 `observations_fts`            | 不能(不切汉字)  | SessionSearch.ts 约 256、416 行                    |
| 汉字关键词补救 | 多列 LIKE 子串匹配                       | 能,但不按相关度排 | SessionSearch.ts `buildSubstringClause` 约 444 行 |
| 按意思找    | Chroma + 默认英文模型                    | 弱(见第六节)   | models.ts 头部注释;ChromaSync.ts 约 1985 行           |
| 结果拼装与补查 | SearchOrchestrator / SearchManager | 取决于上面各层   | SearchOrchestrator.ts 约 107-226 行               |

---

## 三、写入细节:一条观察变成几个向量文档

一条观察在 Chroma 里不是一个文档,而是**若干个**,每个文档的 id 形如 `obs_<id>_<字段>`(ChromaSync.ts `formatObservationDocs`,约 655-734 行):

| 向量文档 | id 形式 | 内容来源 | 什么时候生成 |
|---|---|---|---|
| narrative | `obs_<id>_narrative` | 观察的叙述 | `narrative` 非空(约 694 行) |
| text | `obs_<id>_text` | 观察的 `text` 字段 | `text` 非空(约 702 行) |
| fact | `obs_<id>_fact_<序号>` | `facts` 里的每一条事实,各一个文档 | 每条事实一个(约 710 行) |
| title | `obs_<id>_title` | 标题 + 副标题合并 | 仅当上面三类一个都没有时(约 722 行) |

这就是为什么同一条观察可能在 Chroma 里命中多次;查询结果会按 (文档类型, SQLite id) 去重(ChromaSync.ts `deduplicateQueryResults`,约 2241 行)。

每个文档都带同一组元数据 `metadata`(约 667-692 行):

| 字段 | 含义 |
|---|---|
| `sqlite_id` | 回 SQLite 取完整行用的 id |
| `doc_type` | `observation` / `session_summary` / `user_prompt`,用来分三类 |
| `memory_session_id`、`project`、`merged_into_project`、`platform_source` | 属于哪个会话、哪个项目、哪个来源端 |
| `created_at_epoch` | 创建时间(毫秒),**90 天窗口就是用它过滤的** |
| `type`、`title`、`subtitle` | 观察类型(缺省 `discovery`)、标题(缺省 `Untitled`)、副标题 |
| `concepts`、`files_read`、`files_modified` | 有才写,逗号拼接 |
| `field_type`(`fact` 还多一个 `fact_index`) | 这个文档是从哪个字段来的 |

另外两类也进 Chroma:会话摘要拆成 request / investigated / learned / completed / next_steps / notes 各一个文档(`formatSummaryDocs`,约 736-796 行);用户提问一个文档(`formatUserPromptDoc`,约 1203 行)。

写入顺序:先 `storeObservations` 写 SQLite(ResponseProcessor.ts 约 1002 行调用,SessionStore.ts 约 4271 行定义),再调 `getChromaSync()?.syncObservation(...)`(ResponseProcessor.ts 约 1408 行)。`?.` 的意思是 Chroma 关了(`getChromaSync()` 返回 null)就直接跳过。同步成功才推进"已同步"水位,部分写失败就标"待补",下次启动补(ChromaSync.ts 约 1103-1137 行)。

Chroma 只有**一个集合** `cm__claude-mem`,项目只是元数据字段:`new ChromaSync('claude-mem')`(DatabaseManager.ts 约 95 行),集合名拼接见 ChromaSync.ts 约 460-466 行。

---

## 四、SQLite 的 observations 表

表经过很多次迁移,现在的列要把"建表语句 + 后续 ALTER"合起来看(SessionStore.ts)。下面是我读到的:

| 来源 | 列 |
|---|---|
| 最初建表(约 1299-1308 行) | `id`、`memory_session_id`、`project`、`text`、`type`、`created_at`、`created_at_epoch` |
| 重建表(约 1876-1894 行) | 以上再加 `title`、`subtitle`、`facts`、`narrative`、`concepts`、`files_read`、`files_modified`、`prompt_number`、`discovery_tokens`;`text` 变成可空 |
| 之后 ALTER 追加(我只列了 grep 到的) | `occurrence_count`、`title_norm_key`(约 458-464)、`content_hash`(约 2002)、`generated_by_model`、`relevance_count`(约 2062-2065)、`reinforcement_dates`、`last_reinforced`(约 2417-2420)、`merged_into_project`(约 2483)、`agent_type`、`agent_id`(约 2722-2725)、`metadata`(约 2865) |

要点:`facts`、`concepts`、`files_*` 在表里是**文本**(存 JSON 数组字符串,`syncObservation` 里用 `JSON.stringify`,ChromaSync.ts 约 1094-1098 行)。

FTS5 索引 `observations_fts` 是"外部内容表"(`content='observations'`),只索引 6 列:`title, subtitle, narrative, text, facts, concepts`,靠 `observations_ai/ad/au` 三个触发器跟主表同步(SessionSearch.ts 约 56-75、256-266 行)。会话摘要有自己的 `session_summaries_fts`(约 279 行)。

---

## 五、读取细节:检索流程

### 5.1 主流程(SearchOrchestrator.ts `executeWithFallback`,约 107-153 行)

| 情况 | 走哪里 | 位置 |
|---|---|---|
| 没有 query、只有过滤条件 | 直接 SQLite | 约 114-117 行 |
| 有 query 且 Chroma 可用 | Chroma 取候选,再 `supplementEmptyCategories` 补空类别 | 约 119-145 行 |
| 有 query 但 Chroma 关了(`CLAUDE_MEM_CHROMA_ENABLED=false`) | 只走 SQLite/FTS5 | 约 147-152 行;开关在 DatabaseManager.ts 约 93 行 |

另一个入口 `SearchManager.search`(SearchManager.ts 约 455 行)逻辑相同,并且多了一条:**Chroma 查询抛错时会降级到 FTS5 关键词搜索**(约 555-562 行,日志写"falling back to FTS5 keyword search")。Orchestrator 那条路径遇到 Chroma 错误是直接抛 `ChromaUnavailableError`(约 129-135 行),不降级。哪个入口服务你平时用的 MCP 搜索工具,我没追到(未证实)。

### 5.2 Chroma 候选怎么取

`ChromaSearchStrategy.executeChromaSearch`(ChromaSearchStrategy.ts 约 84-166 行)向 Chroma 发 `chroma_query_documents`,`query_texts: [你的查询文字]`(ChromaSync.ts 约 1998-2001 行),先要 100 条候选,不够就翻倍,最多 1600(约 107-111、149-153 行)。查询文字由 Chroma 一侧用集合创建时选定的嵌入函数转成向量(推断:源码只传文字不传向量,嵌入发生在 chroma-mcp 内部,我没读 chroma-mcp 本身)。

### 5.3 90 天窗口(CLAUDE_MEM_SEARCH_RECENCY_DAYS)实际生效的位置

| 步骤 | 位置 |
|---|---|
| 默认值 `'90'` | SettingsDefaultsManager.ts 约 696 行;常量 `RECENCY_WINDOW_MS = 90天` 在 worker/search/types.ts 约 7 行 |
| 解析:空值=90 天,`0`=关闭窗口,正整数=天数,非法值告警并回到 90 天 | types.ts `parseSearchRecencyWindowMs` 约 24-37 行;worker-service.ts 约 1004-1008 行 |
| 传给 SearchManager → SearchOrchestrator → ChromaSearchStrategy | worker-service.ts 约 1016 行;SearchOrchestrator.ts 约 84-89 行 |
| 真正过滤 | ChromaSearchStrategy.ts `filterByRecency` 约 214-240 行:没给 `dateRange` 且窗口大于 0 时,丢掉 `created_at_epoch` 早于"现在减 N 天"的 Chroma 命中 |
| 同样的过滤(另一个入口) | SearchManager.ts 约 142-145 行 |

注意它的**作用范围比"90 天外搜不到"窄**:

- 只作用于**没给日期范围的、走 Chroma 的**搜索;给了 `dateStart/dateEnd` 就以日期为准(types.ts 注释约 21 行)。
- Chroma 对某一类返回空时,SQLite 补查**不加窗口**,源码注释写明"早于 90 天的精确关键词命中正是这套回退要找出来的行"(SearchOrchestrator.ts 约 162-163 行、199-201 行)。
- 但某一类 Chroma 已经有结果时,更老的关键词命中**不会**被补进来(除非达到候选预算上限,此时补查仍保留窗口,约 176-178、199-201 行)。
- 关掉 Chroma 的纯 SQLite 路径也不加窗口(约 147-152 行)。

所以:想让老记忆稳定被按意思找到,把它设成 `0`,改完要重启 worker(SettingsDefaultsManager.ts 约 696 行注释)。

### 5.4 SQLite 补查:FTS5 与汉字降级(SessionSearch.ts `searchObservations`,约 742-811 行)

| 查询长什么样 | 走哪条 | 位置 |
|---|---|---|
| 不含汉字/假名/谚文/泰文等"切不开"的文字 | FTS5 `MATCH`,各词用 AND 连,按 FTS5 的 `rank` 排序 | 约 772-786 行;`buildFTSMatchQuery` 约 472 行 |
| 含汉字等"切不开"的文字 | **不进 FTS5**,直接多列 LIKE 子串匹配 | 约 768-770 行;判断正则 `UNSEGMENTED_SCRIPT` 约 416 行 |
| FTS5 一个都没命中(例如汉字和英文粘在一起:`payload优先使用LLM`) | 再试子串匹配 | 约 799-805 行 |
| 子串也没命中,且查询有 3 个以上词 | 放宽成"任一词命中"(OR),按 bm25 排 | 约 806-807 行;`buildFTSAnyTermQuery` 约 507 行,3 词门槛约 462 行 |

为什么要降级:FTS5 的 `unicode61` 分词器靠空白和标点切词,汉字之间没有这两样,一整串汉字被当成一个词,查其中一部分查不到。源码里有实测对照:`项目` 在 `修改了项目配置` 里命中 0 行(SessionSearch.ts 约 396-415 行注释,#3801)。

LIKE 子串匹配怎么工作(`buildSubstringClause`,约 444-459 行):

1. 先把查询按"汉字连续段"和"非汉字连续段"切成若干项(正则 `UNSEGMENTED_RUN`,约 424 行)。例如 `claude 队列` 切成 `claude`、`队列` 两项。
2. 每一项必须在**至少一列**里出现(观察表查 `title/subtitle/narrative/text/facts/concepts` 六列,约 694-696 行;摘要表查 request/investigated/learned/completed/next_steps/notes 六列,约 719-721 行)。
3. 各项之间是 AND:每一项都要出现,但不要求相邻。
4. 项数上限 500(约 436 行)。
5. 排序:传入的 `hasFTS=false`,`relevance` 排序实际变成按创建时间倒序(`buildOrderClause` 约 674-677 行)。所以是"不按相关度、按新旧排",不是随机。

两个直接后果(从上面推出来,属于推断但依据明确):一整句中文是一个连续段,必须在某一列里**原样连续出现**才命中,所以长句几乎搜不到;2-4 个字的短关键词最稳。

用户提问(prompts)这一类一直是 LIKE 子串,不用 FTS5(SessionSearch.ts `searchUserPrompts` 约 1142 行,LIKE 约 1200-1202 行)。

### 5.5 空类别补查(SearchOrchestrator.ts `supplementEmptyCategories`,约 167-226 行)

Chroma 用一次"全类型取前 N"的查询,所以某一类可能被别的类挤成空——源码注释举的例子正是"中日韩查询时,用户提问把观察挤掉"(约 157-158 行)。处理规则:

| Chroma 结果 | 做法 | 位置 |
|---|---|---|
| 所有被请求的类别都空 | 整个改走 SQLite | 约 184-187 行 |
| 部分类别空 | 只给空的类别用 SQLite 补,其余保留 Chroma 结果,返回策略标记为 `hybrid` | 约 189-225 行 |
| 都不空 | 原样返回 | 约 180-182 行 |

---

## 六、中文为什么搜不准、有哪些补救办法

### 6.1 原因(每条标明证据类型)

| 短板                   | 说明                                                                                                                 | 证据类型                                                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| 向量层默认模型是英文的          | 默认嵌入模型 `all-MiniLM-L6-v2` 是"仅英文"的,它约 3 万词的词表会把中日韩文字切成单字或 `[UNK]`(未知符号),这是源码里提到的"中日韩召回缺口"的来源(#3422、#3982)           | 源码注释:models.ts 约 1-13 行                                                                           |
| 本地 Chroma 默认用的就是这个模型 | `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` 默认 `'default'`,注释写"是本地的 all-MiniLM-L6-v2(偏英文)";models.ts 也写"它是 Chroma 原来用的" | 源码注释:SettingsDefaultsManager.ts 约 669-675 行;models.ts 约 5 行。未实测 chroma-mcp 的 default 到底加载了什么(未证实) |
| 关键词层不切汉字             | FTS5 `unicode61` 把连续汉字当一个词,所以含汉字查询干脆不走 FTS5                                                                        | 源码:SessionSearch.ts 约 396-416、768 行,含源码内的实测数字                                                     |
| 降级后不排序且要求连续          | 子串匹配只看"含不含",按时间倒序,长句要原样连续出现                                                                                        | 源码:SessionSearch.ts 约 444-459、674-677 行                                                           |
| "汉字查询被用户提问挤掉观察"      | 源码自己承认存在,并用空类别补查缓解                                                                                                 | 源码注释:SearchOrchestrator.ts 约 157-158 行                                                            |

### 6.2 补救办法

| 办法                    | 怎么做                                                                                                                                                                                        | 依据                                                                                                                      | 效果                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 搜中文时用短关键词             | 2-4 个字的词,多个词用空格隔开;不要整句                                                                                                                                                                     | 源码行为(5.4 节 `buildSubstringClause`)                                                                                      | 逻辑上成立,未实测                                                                                    |
| 取消 90 天窗口             | `CLAUDE_MEM_SEARCH_RECENCY_DAYS` 设为 `0`,重启 worker                                                                                                                                          | 源码:types.ts 约 24-37 行                                                                                                   | 只解决"老记忆被过滤",不解决中文向量质量                                                                        |
| 搜索时直接给日期范围            | 传 `dateStart/dateEnd`,窗口不再生效                                                                                                                                                               | 源码:ChromaSearchStrategy.ts 约 221-230 行                                                                                  | 同上                                                                                           |
| 完全关掉 Chroma,只用 SQLite | `CLAUDE_MEM_CHROMA_ENABLED=false`                                                                                                                                                          | 源码:DatabaseManager.ts 约 93 行;SearchOrchestrator.ts 约 147-152 行                                                          | 中文变成纯子串匹配(稳定、按时间排),但英文也失去"按意思找"。哪个更适合你,没测过(未证实)                                              |
| 换 Chroma 的嵌入函数        | `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` 可选 `openai/cohere/jina/voyageai/roboflow`,只对新集合生效、要重建索引,记忆文字会发给厂商、需要 API key                                                                        | 源码注释:SettingsDefaultsManager.ts 约 669-675 行                                                                             | 这些模型对中文是否更好:推断(云端通用模型通常多语言),**未证实**;而且有隐私成本                                                  |
| 换成多语言嵌入模型             | 仅服务器模式可用:`CLAUDE_MEM_EMBEDDING_MODEL` 可选 `paraphrase-multilingual-MiniLM-L12-v2`、`multilingual-e5-small`、`granite-embedding-97m-multilingual-r2`(models.ts 约 37-80 行白名单,未知名字会报错,约 85-93 行) | 源码                                                                                                                      | 本机默认路径**用不上**(见第七节)。源码称这三个多语言候选在外部项目 `rich-murphey/claude-mem-search-eval` 里测过,我没读,结论**未证实** |
| 让观察里带英文关键词            | 例如在 CLAUDE.md 或提示里要求观察的标题/事实保留英文术语                                                                                                                                                         | 推断:英文模型对英文词更敏感;`plugin/modes/` 里有 `code--zh.json` 等语言模式,`CLAUDE_MEM_MODE` 默认 `code`(SettingsDefaultsManager.ts 约 607 行) | 推断。我没读 `code--zh.json` 的内容,不知道它是否让观察用中文写(未证实)                                                |

---

## 七、你本机默认配置下实际会走哪条路径

前提:全部按源码默认值推出来的,**本机没有 `~/.claude-mem` 目录(我 `ls` 过,不存在),所以没有任何实测数据,也没确认你的 worker 是否启动过**。如果你的数据目录被环境变量改过,路径会不同(我没查 `DATA_DIR` 的覆盖逻辑,未证实)。

| 默认值 | 取值 | 位置 |
|---|---|---|
| `CLAUDE_MEM_CHROMA_ENABLED` | `true` | SettingsDefaultsManager.ts 约 658 行 |
| `CLAUDE_MEM_CHROMA_MODE` | `local`(用 `uvx` 起 `chroma-mcp` 子进程) | 约 659 行;ChromaMcpManager.ts 约 657-661 行 |
| `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` | `default`(英文 all-MiniLM-L6-v2,注释) | 约 675 行 |
| `CLAUDE_MEM_SEARCH_RECENCY_DAYS` | `90` | 约 696 行 |
| `CLAUDE_MEM_EMBEDDING_MODEL` | `all-MiniLM-L6-v2`,但见下 | 约 694 行 |

**`CLAUDE_MEM_EMBEDDING_MODEL` 在本机路径上不生效。** 这个设置只在 `ObservationEmbeddingService.ts` 约 32 行被读(服务器模式的向量服务,依赖 Postgres 的 pgvector,见 schema.ts 约 160-207 行),我在 `src` 里搜过,其他地方没有读它(grep 结果:除 SettingsDefaultsManager、models.ts、LocalEmbedder.ts、该服务外无引用)。本机 worker 的 Chroma 路径读的是 `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION`(ChromaSync.ts 约 496-511 行)。

所以你一条中文搜索(有 query、没传日期)大致这样走:

| 步骤 | 发生什么 | 对中文的影响 |
|---|---|---|
| 1 | 请求进 SearchManager / Orchestrator,`CHROMA_ENABLED` 为真,走 Chroma | |
| 2 | Chroma 用默认英文模型把中文查询转向量,取候选 | 召回质量偏弱(原因见 6.1,效果未实测) |
| 3 | 丢掉 90 天前的命中 | 老记忆被过滤 |
| 4 | 某类为空(中文查询时很常见,推断)则用 SQLite 补查,不限天数 | 走多列 LIKE 子串匹配,能命中原样出现的关键词 |
| 5 | 若 Chroma 子进程起不来,`SearchManager.search` 降级成 FTS5/子串关键词搜索 | 同第 4 步 |

也就是说,**本机上中文能不能搜到,多半靠第 4 步的子串补查,而不是向量**。这是推断:依据是源码路径,没有任何一次真实搜索的日志。

---

## 八、未证实 / 没读到的清单

| 项 | 状态 |
|---|---|
| 以上所有行为的实测 | 没实测,没跑过 worker,本机也没有 `~/.claude-mem` |
| 行号 | 来自工具读取时的行号,"约"表示可能随版本偏移几行 |
| chroma-mcp 自身(Python 端)`default` 嵌入函数具体加载什么、怎样切中文 | 没读;"all-MiniLM-L6-v2"来自本仓库注释 |
| 其它嵌入函数(openai/cohere/jina/voyageai/roboflow)对中文的效果 | 没读没测 |
| `SQLiteSearchStrategy`、`HybridSearchStrategy` 的实现 | 没读;我假定 SQLite 策略最终调用 `SessionSearch`(推断) |
| MCP 搜索工具实际走 `SearchManager.search` 还是 `SearchOrchestrator.search` | 没追 |
| `SessionStore.storeObservations` 内部的 INSERT 语句与去重、合并逻辑 | 只读了签名;表结构来自建表和 ALTER 语句的拼合,可能漏列 |
| 服务器模式(Postgres + pgvector)的完整检索流程 | 只读到向量服务和 schema 的几处注释,没读 `storage/postgres` 的查询细节 |
| 多语言模型的实际中文召回提升 | 外部评测仓库 `rich-murphey/claude-mem-search-eval` 没读,不可当结论 |
| `plugin/modes/code--zh.json` 的内容 | 只看到文件存在,没读 |
| `DATA_DIR` 的环境变量覆盖逻辑 | 没读 |
| 向量文档数量对 Chroma 候选预算(100→1600)的实际影响 | 没测 |
