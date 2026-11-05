---
type: concept
status: developing
area: growth
title: "opencode-mem 值得调整的配置"
created: 2026-11-05
updated: 2026-11-05
tags:
  - learning
  - opencode
  - opencode-mem
  - 配置
related:
  - "[[opencode-mem-调研与上手指南]]"
---

# opencode-mem 值得调整的配置

> 配置项有上百个,**绝大多数不用碰**。本文只挑真正影响效果、成本、隐私的那些,按"必须改 → 建议改 → 看情况 → 不用管"排序。
>
> 依据:v2.41.0 的 `opencode-mem.example.jsonc`、`src/config.ts` 默认值和 README。安装步骤见 [[opencode-mem-调研与上手指南]]。

## 配置文件在哪里

| 位置 | 作用 |
|---|---|
| `~/.config/opencode/opencode-mem.jsonc` | 全局配置。首次启动自动生成带注释的模板 |
| `<项目>/.opencode/opencode-mem.jsonc` | 项目级覆盖,只对这个项目生效 |

注意:项目级覆盖里**不能覆盖** `autoCleanupEnabled` 和 `autoCleanupRetentionDays`(源码 `config.ts` 会把这两项从项目配置里删掉),清理策略只能在全局改。

---

## 一、必须改(不改基本用不起来)

### 1. 自动捕获用哪个模型

**这是最重要的一项。** 不配,自动捕获不会工作(README 写明:捕获只在配好 provider 后才运行);配错了,会反复失败重试、白烧 token。

```jsonc
"opencodeProvider": "你的provider名",   // 必须是 `opencode providers list` 里有的名字
"opencodeModel": "模型名",              // 或写 "inherit",跟随当前会话用的模型
```

| 要点 | 说明 |
|---|---|
| 模型要求 | 必须能返回**结构化 JSON / 工具调用**输出 |
| 官方免费/Zen 模型 | provider 为 `opencode`(如 `big-pickle`),README 说通常**不能用**于后台捕获 |
| 选哪种 | 便宜、快的小模型(这是后台高频调用,不需要最强的) |
| `inherit` | 沿用你当前会话的模型。省事,但如果当前用的是大模型,后台捕获也会用它,成本更高。**用 `inherit` 时 `opencodeProvider` 仍然必填** |
| `opencodeVariant` | 可单独给后台调用指定推理强度,不影响你的主会话 |
| `opencodeTimeoutMs` | 单次后台调用超时,默认 90000 毫秒,范围会被限制在 10000–600000 |

> [!warning] 我没验证的
> 你的 `opencode.jsonc` 里有自定义 provider `codebuddy`(`@ai-sdk/openai-compatible`),它能不能通过 OpenCode 的会话接口返回结构化输出,我没试过。需要自己试一次:配好后让会话空闲,看网页界面有没有新记忆,以及日志里有无报错。

**备选方案**:不走 OpenCode 的 provider,而是直接配一个 OpenAI 兼容接口:

```jsonc
"memoryProvider": "openai-chat",
"memoryModel": "模型名",
"memoryApiUrl": "https://.../v1",
"memoryApiKey": "env://环境变量名"
```

两种都配时,默认先试 OpenCode 的(`autoCaptureProviderOrder: "opencode-first"`)。如果发现主会话忙时 OpenCode 这条路很慢,可改成 `"external-first"`。

> [!tip] 密钥不要写明文
> 所有密钥字段都支持 `env://变量名` 或 `file:///路径` 写法。

### 2. 先确认一件事:你的数据会发到哪

后台捕获会把"用户文本、助手文本、工具输入、工具结果证据"发给你配置的那个模型。**这个模型在哪,这些内容就发到哪。**

- 选 OpenCode 里已有的公司内可用的模型:内容流向与你日常对话一致。
- 选第三方外部接口(`memoryApiUrl` 指向公网):内容会发到那家服务。对公司代码要谨慎。

---

## 二、建议改(有明显收益)

### 3. 重要的记忆必须置顶,保留天数只是推迟

| 项 | 默认 | 说明 |
|---|---|---|
| `autoCleanupEnabled` | `true` | 每天最多跑一次 |
| `autoCleanupRetentionDays` | `30` | **超过这么多天没"更新"、且没置顶的记忆会被硬删** |

**"更新"指记忆数据被写过**(新建、改写内容、改元数据、软删/恢复)。源码里**被搜索命中、被自动注入到对话,都不算更新**;置顶本身也不刷新更新时间。也没有"最近使用"之类的字段。

所以:**一条你天天用、但从没被改过的记忆,到期照样被删。**

| 做法 | 效果 |
|---|---|
| **置顶**(在网页界面操作) | 永不清理、永不被自动改写。常用的重要记忆就该这样处理 |
| 调大天数(如 90、365) | 只是推迟,到期仍会删 |
| `autoCleanupEnabled: false` | 不自动删,代价是库一直变大,要自己定期整理 |

置顶的代价:它不会被自动改写,新旧矛盾时不会被取代,要你自己手动更新。

> [!warning] 更正
> 本文早先把 `autoCleanupRetentionDays: 90` 注释成"防止重要记忆被清理",这是错的。调大天数不能保护任何记忆,只有置顶能。

### 4. 召回的松紧:`similarityThreshold` 和注入条数

| 项 | 默认 | 含义 |
|---|---|---|
| `similarityThreshold` | `0.6` | 相似度低于它的不返回。**越高越严,越低越宽** |
| `maxMemories` | `10` | 手动搜索最多返回几条 |
| `chatMessage.maxMemories` | `3` | **每次自动注入几条**(影响每轮对话多占多少上下文) |
| `chatMessage.similarityThreshold` | 沿用顶层 | 可以只给自动注入单独设一个门槛 |
| `chatMessage.maxAgeDays` | 不限 | 只注入最近 N 天内的记忆 |

怎么调:
- 注入的记忆经常无关 → 把门槛从 0.6 调到 0.65–0.7,或减少 `chatMessage.maxMemories`。
- 明明存过却找不到 → 把门槛降一点(比如 0.5)。
- 把 `chatMessage.maxMemories` 设为 `0`,可以**关掉项目记忆注入**,但仍保留用户画像注入。

**怎么判断调得对:**先不改,用几天后在网页界面看哪些被注入了,再动。

> [!note] 中文使用者要留意
> 关键词那一项对中文基本不起作用(详见 [[opencode-mem-调研与上手指南]] 第三节),召回全靠语义。所以语义模型的质量和门槛设置,对你比对英文用户更重要。

### 5. 打开"保存时更新",解决新旧矛盾

```jsonc
"updateOnCaptureEnabled": true,
"updateOnCaptureSimilarityThreshold": 0.75,
"updateOnCaptureMaxCandidates": 5
```

- 默认关闭,默认只新增,新旧结论会并存。
- 打开后,每次保存会多一次模型调用(判断新增/改写/取代),**成本会增加**。
- 保守设计:拿不准就新增,所以不会乱删。
- 建议:用了 1–2 周、发现矛盾记忆确实在困扰你,再打开。

### 6. 控制成本:谁在偷偷花 token

后台调用有三处会花 token:

| 来源 | 触发 | 怎么控制 |
|---|---|---|
| 自动捕获 | 会话空闲后 | 选便宜模型;`autoCaptureMaxRetries`(默认 3)控制失败重试次数 |
| 用户画像分析 | 每累计 10 条提问(`userProfileAnalysisInterval`) | 已决定保持默认 10。注意 `injectProfile: false` 在源码里只控制"是否把画像注入对话",没找到它会停止分析的代码,不能当作省调用的办法 |
| 画像自动清理 | 每 100 条(`userProfileAutoCleanupInterval`) | 默认开(`userProfileAutoCleanupEnabled: true`) |

另外两个可选功能(保存时更新、dreaming)默认关闭;你已决定都开,见第五节。

`autoCaptureMaxContextBytes`(默认 131072 字节)限制每次发给总结模型的上下文大小。如果你的捕获模型上下文窗口较小,出现 HTTP 400 报错,把它调小。

### 7. 嵌入模型:一开始就选定,别中途换

| 项 | 默认 | 说明 |
|---|---|---|
| `embeddingModel` | `Xenova/nomic-embed-text-v1` | 768 维,本地 CPU 运行。README 称"多语言",但官方页未写、外部来源称主要为英文。**中文建议换 `Xenova/bge-m3`** |
| `embeddingIdleTimeoutMs` | `0` | 默认模型**常驻内存**(约 0.5–2GB)。设成 `600000`(10 分钟)可在闲置后释放,下次用时约一秒重新加载 |
| `embeddingUseTaskPrefixes` | `false` | nomic 专用的前缀开关。**换成 bge-m3 就不要开** |

> [!note] 先弄清 `embeddingModel` 是什么
> 它是"把文字翻成一串数字"的模型(翻译官)。意思相近的话,翻出来的数字也相近,检索就是比较这些数字。它只管**找记忆准不准**,跟"记什么"无关(那是 `opencodeModel` 管的)。默认在你自己电脑的 CPU 上运行,只有首次要联网下载模型文件。

> [!warning] 不要装好用了一阵再换嵌入模型
> 不同模型翻出的数字互不通用。换 `embeddingModel`、池化方式、前缀后,**已有记忆都要重新翻译一遍**,否则新旧向量对不上,检索变差。所以要在存入第一批记忆之前决定好。
>
> **`embeddingUseTaskPrefixes` 和换模型是二选一**:它是 nomic 专用的提示格式;换成 bge-m3 时不要开(bge-m3 有自己的预设,自动用 CLS 池化)。

**已决定:用 `Xenova/bge-m3`。** 理由:nomic-embed-text-v1 对非英文疑似不佳(AutoRAG issue 里韩语实测:无关句子相似度挤在 0.65–0.82,默认门槛 0.6 会让无关记忆被注入;换 bge-m3 后恢复。对中文是类推,非直接实测)。bge-m3 支持 100+ 语言,1024 维,MIRACL 多语言检索 69.2(mE5 Large 66.5、Nomic v2 65.8)。

| 候选 | 维度 | 压缩版体积 | 备注 |
|---|---|---|---|
| **`Xenova/bge-m3`**(选用) | 1024 | 约 570MB | 分数最高,插件有预设 |
| `Xenova/multilingual-e5-large` | 1024 | 约 562MB | 备选;注意写 `Xenova/` 版,`intfloat/` 版的 ONNX 只有 Intel 服务器优化版,Apple 芯片未必能用 |
| `onnx-community/Qwen3-Embedding-0.6B-ONNX` | 1024 | 约 307MB+ | 备选,未找到基准分 |
| `Xenova/jina-embeddings-v2-base-zh` | 768 | 约 161MB | 最小,只覆盖中英 |
| `nomic-embed-text-v2-moe` | 768 | - | 插件维度表里没有,未确认可用,不推荐 |

体积为 2026-11-05 查 Hugging Face 所得。机器(M4 Pro、48GB)内存足够,磁盘剩 59GB 够用。Hugging Face 可从本机访问(API 请求成功),但**未实际下载过模型**;bge-m3 在本插件里的中文召回质量**未实测**。
---

## 三、看情况改

### 8. 跨项目共享记忆

| 想做什么 | 做法 |
|---|---|
| 只在当前项目找(默认) | `memory.defaultScope: "project"` |
| 在所有项目里找 | `memory.defaultScope: "all-projects"`;也可只改自动注入范围:`chatMessage.recallScope` |
| 多个仓库属于同一个大项目 | 在工作区根目录放一个空文件 `.opencode-mem-project`,下面所有子仓库共享一份记忆 |

默认按所在 git 仓库区分项目,所以 monorepo 之外的多仓库工作区,不放这个文件会各存各的。

### 9. 子代理(subagent)的提示词要不要记

`chatMessage.captureChildSessions` 默认 `false`。

你装了 oh-my-opencode-slim,它会派很多子代理。子代理会话里的"用户消息"其实是主代理写的,不是你说的。默认不记是对的,**除非你明确想记,否则别开**。

同理 `chatMessage.filterInjectedPrompts: true`(默认)会过滤掉其他插件注入的系统提醒,避免被当成你说的话存下来。你装了 superpowers 和 oh-my-opencode-slim,**这项应该保持开启**。

### 10. 隐私与安全

| 项 | 默认 | 建议 |
|---|---|---|
| `webServerHost` | `127.0.0.1` | **保持**,只本机能访问。改成 `0.0.0.0` 局域网就能访问你的记忆 |
| `webServerAuthPassword` | 空 | 若必须暴露到局域网,**必须设**;非回环地址还要设 `webServerApiToken` |
| `webServerEnabled` | `true` | 不想要网页界面可设 `false` |
| `databaseEncryptionEnabled` | `false` | 想加密落盘数据就开(AES-256-GCM);会在 `~/.config/opencode/` 生成密钥文件 |
| `<private>...</private>` | — | 对话里用它包住的内容不会被记 |

自动脱敏(默认就有,不用配):捕获前会尽量去掉常见的 API Key、GitHub token、AWS key、Bearer 凭证、PEM 私钥。**但这是尽力而为**:
- 任意密码、自定义或编码过的 token、跨消息拆开的凭证可能识别不出来。
- 已存在的旧记忆不会被回扫。
- 只保护"插件存下来的那份",不保护 OpenCode 原始对话和主模型的请求。

### 11. 语言

`autoCaptureLanguage` 默认 `"auto"` 自动检测。**本机实测 `glm-5.2` 在 auto 下会乱跳语言**:同一场中文对话的摘要被写成瑞典语、罗马尼亚语、克罗地亚语、索马里语、法语。语言一乱,不仅难读,中文提问也更难召回它们。所以本机固定为 `"zh"`。

### 12. 想把记忆当文档管理(v2.41.0 实测有 bug,本机已关)

```jsonc
"memoryBackend": "markdown",
"markdownPath": "~/某个目录"
```

记忆变成一个个 `.md` 文件,数据库只当可重建的搜索索引。方便用 Obsidian 查看和编辑。

> [!bug] 本机实测:开了会让网页崩溃,已关闭
> - 每次服务启动,插件把 md 文件全量扫描一遍,凡是和数据库对不上的记忆,按 md 重写。
> - md 文件头只有 8 项(`id/type/tags/containerTag/createdAt/updatedAt/source/title`),**没有 `promptId`**(`document.ts` 的 `packMemoryMarkdown`)。重写时元数据只用 md 里有的拼(`reconcile.ts:143`),`promptId`、`sessionID`、`captureTimestamp` 就被抹掉。
> - 网页靠 `promptId` 把记忆和提问配对。配不上会产生重复 key,报 `each_key_duplicate`,页面卡在 "Initializing…",翻到相关那页就崩。
> - 实测:37 条缺 `promptId` 的记忆全都带 `markdownContentHash`(被重写过),2 条有 `promptId` 的最新记忆全都没有,没有例外。
> - 记忆内容、检索、注入不受影响,坏的只是网页显示。
> - 结论:**v2.41.0 不要开 markdown 后端**,除非不用网页。

> [!warning] 切换会丢数据
> 切到 markdown 时,数据库里没有对应文件的行会被丢弃。切之前先用 `memory export` 导出。
> 另外,用户直接编辑文件、画像、dreaming 等路径**不在**脱敏保证的覆盖范围内。

### 13. 定期整理(dreaming)

```jsonc
"dreaming": { "enabled": true, "intervalHours": 24, "maxGroupsPerRun": 5, "relatedThreshold": 0.75 }
```

库里条目多、重复多了再开。被淘汰的记忆进回收站(30 天),可在网页界面恢复。要求 `opencodeProvider`/`opencodeModel` 已配好。

### 14. 提示通知太吵

`showAutoCaptureToasts`、`showUserProfileToasts`、`showErrorToasts` 默认全开。前两个觉得烦可以关,**保留 `showErrorToasts`**,出问题才看得到。

### 15. 自动更新

`autoUpdate` 默认 `true`:装的是 `opencode-mem@latest` 时,有新版本会自动更新。想稳定可以:
- 固定版本(例如 `opencode-mem@2.41.0`,固定版本不会被自动更新),或
- 保持 `latest`,但每次 OpenCode 升级后检查一下记忆是否仍在写入。

---

## 四、基本不用管(默认就好)

| 项 | 说明 |
|---|---|
| `storagePath` | 数据目录,默认 `~/.opencode-mem/data`。想换盘再改 |
| `maxVectorsPerShard` | 每个分片最多 5 万向量,自动分片 |
| `deduplicationSimilarityThreshold` | 去重相似度 0.9 |
| `aiSessionRetentionDays` | 后台 AI 会话历史保留 7 天 |
| `autoCaptureMaxIterations` / `autoCaptureIterationTimeout` | 多轮分析次数(5)与单轮超时(30 秒) |
| `memoryTemperature` | 默认 0.3;**只有换用不支持 temperature 参数的推理模型(如 o1、o3、gpt-5)时才需要改成 `false`** |
| `forceToolChoice` | 默认 `true`;如果模型拒绝强制工具调用,才改 `false` |
| `userProfile*` 一堆阈值 | 画像的衰减、去重、展示数量。除非专门研究画像,别动 |
| `tursoAutoHeal` / `tursoMultiprocessWal` | 数据库恢复与多进程写入,出问题再看 |

关于 `tursoMultiprocessWal`:默认 `true`,允许多个 OpenCode 进程同时写。设为 `false` 是"单进程模式",第二个进程会直接报 `database is locked`,而不是写出不一致的数据。

---

## 五、值得改的配置汇总(一张清单)

没列出的项全部用默认值,不用写。配置文件首次启动会自动生成:`~/.config/opencode/opencode-mem.jsonc`。

### 必配

| 配置项 | 建议值 | 原因 |
|---|---|---|
| `opencodeProvider` | `"codebuddy"` | 不配就没有自动捕获。名字取自你的 `opencode.jsonc`,**能否做后台捕获未验证** |
| `opencodeModel` | `"glm-5.2-ioa"` | 取自你的 `opencode.jsonc`。**能否返回结构化输出(后台捕获的硬性要求)未验证**,需实测;另有 `glm-5.2-internal-ioa`(自部署版)可备选 |

### 存第一批记忆之前就要定(之后改要重新生成向量)

| 配置项                        | 建议值                             | 原因                                 |
| -------------------------- | ------------------------------- | ---------------------------------- |
| `embeddingModel` | `"Xenova/bge-m3"` | "把文字翻成数字"的模型,决定找记忆准不准,在本机 CPU 运行。默认 nomic 对中文疑似不佳,所以换。首次启动需联网从 Hugging Face 下载(约 570MB) |
| `embeddingUseTaskPrefixes` | **不要写** | nomic 专用前缀,和 bge-m3 二选一 |
|                            |                                 |                                    |

### 成本和资源

| 配置项 | 建议值 | 原因 |
|---|---|---|
| `embeddingIdleTimeoutMs` | `600000` | 默认模型常驻内存约 0.5–2GB;改后闲置 10 分钟就释放 |
| `autoCaptureMaxContextBytes` | 调小 | 只有捕获模型上下文窗口小、报 HTTP 400 时才改 |

### 记忆保留

| 配置项 | 建议值 | 原因 |
|---|---|---|
| 置顶 | 网页界面操作 | **真正的保护**。被搜索、被注入都不会刷新更新时间,常用但没改过的记忆到期照样删 |
| `autoCleanupRetentionDays` | `365` | 超过 365 天没被"写过"且未置顶的记忆才会被自动删。只是推迟,不能保护"常用"的记忆;重要的仍要置顶 |
| `autoCleanupEnabled` | `false`(可选) | 完全不自动删,代价是库一直变大 |

### 召回质量

| 配置项 | 建议值 | 原因 |
|---|---|---|
| `similarityThreshold` | 先不改,用几天后调 | 默认 0.6。注入的无关就升到 0.65–0.7,找不到就降到 0.5 |
| `chatMessage.maxMemories` | 默认 3,按需调 | 每轮自动注入几条,直接影响占用的上下文 |
| `chatMessage.maxAgeDays` | `365`(与清理天数对齐) | 只注入**创建时间**在最近 N 天内的记忆。看的是创建时间不是更新时间,所以更早创建的重要记忆(含置顶)也不会被自动注入,只能靠搜索工具找到 |

### 冲突与整理(已决定都开)

| 配置项 | 建议值 | 原因 |
|---|---|---|
| `updateOnCaptureEnabled` | `true` | 存新记忆前先找相似旧记忆,让模型选"新增 / 更新 / 取代"。置顶的不会被动。每存一条多一次模型调用 |
| `dreaming.enabled` | `true` | 每 24 小时后台整理一次相近记忆(每次最多 5 组)。被取代的进回收站保留 30 天,可在网页界面恢复。置顶的不会被动 |

> [!warning] 风险
> 这两项会让模型**直接改写或删除**你的记忆。模型(glm-5.2)判断错了会把有用的记忆改坏。"取代"进回收站可恢复;"更新"是直接改写旧内容,我没看到备份。建议开了之后定期到网页界面看回收站和被改过的条目。

### 看情况

| 配置项 | 建议值 | 原因 |
|---|---|---|
| `autoUpdate` | 用默认 `true`,不写 | 想稳定再写 `false` 或固定版本号 |
| `showUserProfileToasts` | 用默认 `true`,不写 | 保持弹出,方便知道画像何时更新 |
| `databaseEncryptionEnabled` | 用默认 `false`,不写 | 想加密落盘数据再开 |
| `memoryBackend` + `markdownPath` | **不写,用默认 `"database"`** | v2.41.0 的 markdown 后端会在重启时抹掉 `promptId`,导致网页崩溃(见第 12 节) |
| `memory.defaultScope` | `"all-projects"` | 想跨项目查记忆才改 |

### 不要改(默认已经正确)

`webServerHost` 保持 `127.0.0.1`、`chatMessage.filterInjectedPrompts` 保持开、`chatMessage.captureChildSessions` 保持关。你装了 superpowers 和 oh-my-opencode-slim,这三项关系到别的插件的提示词会不会被当成你说的话存下来。

### 对应的 JSON 写法

可选项用注释标出,按需取消注释。文件是 JSONC,注释可以保留。

```jsonc
{
  // ===== 必配 =====
  "opencodeProvider": "codebuddy",        // 能否做后台捕获未验证
  "opencodeModel": "glm-5.2-ioa",         // 另有 glm-5.2-internal-ioa(自部署版)可备选

  // ===== 存第一批记忆之前就要定 =====
  "embeddingModel": "Xenova/bge-m3",      // 1024 维,多语言;不要同时写 embeddingUseTaskPrefixes

  // ===== 想在界面里看到记忆 =====
  "webServerEnabled": true,               // 网页界面,默认已开;访问 http://127.0.0.1:4747
  // 不要写 memoryBackend: "markdown"。v2.41.0 里重启会抹掉 promptId,网页会崩(见第 12 节)

  // ===== 成本和资源 =====
  "embeddingIdleTimeoutMs": 600000,

  // ===== 摘要语言 =====
  "autoCaptureLanguage": "zh",            // glm-5.2 在 auto 下会把摘要写成瑞典语/索马里语/法语等,固定为中文

  // ===== 记忆保留(重要记忆请在网页界面置顶)=====
  "autoCleanupRetentionDays": 365,        // 365 天没被"写过"且没置顶才会删;被搜索/注入不算。重要的请置顶
  // 自动清理开关。默认 true(开着):每天最多清理一次,删掉超过上面天数没被"写过"且没置顶的记忆。
  // 想一条都不自动删,就取消下一行注释(设 false);代价是库会越来越大。关掉后上面的天数只在网页界面手动清理时才用。
  // "autoCleanupEnabled": false,

  // ===== 召回质量(用几天后再调)=====
  // 相似度门槛(0~1,默认 0.6):一条记忆和你的提问"意思有多像",低于这个分数就不算相关、不会被注入。
  // 调高(0.65~0.7)= 更严格,少注入但更准;调低(0.5)= 更宽松,多注入但可能带进无关内容。
  // 它是全局的,搜索工具和自动注入都用;只想改自动注入,把它写进下面 chatMessage 里同名项。
  // "similarityThreshold": 0.65,
  "chatMessage": {   // 每次你发消息时,自动把相关记忆塞进对话的那套设置
    // 只注入"创建时间"在最近 N 天内的记忆(默认不限制)。注意看的是创建时间,不是最后更新时间:
    // 超过 365 天前创建的记忆,即使很重要、已置顶,也不会再被自动注入(仍然能被搜索工具搜到)。
    // 与上面 autoCleanupRetentionDays 保持一致,都是 365。
    "maxAgeDays": 365
    // 每次最多注入几条记忆(默认 3)。调大 = 一次带进对话的相关记忆更多,信息更全。
    // "maxMemories": 3
  },

  // ===== 冲突与整理(新旧记忆打架、重复时怎么处理)=====
  // 存的时候处理:存新记忆前先找相似的旧记忆(相似度 0.75 以上,最多看 5 条),让模型选 新增 / 更新 / 取代。
  // 取代 = 存新的、旧的进回收站。置顶的记忆不会被动。默认 false。
  "updateOnCaptureEnabled": true,
  // 事后整理("做梦"):每 24 小时扫一遍库里意思相近的记忆,让模型合并/更新/取代,每次最多 5 组。
  // 被取代的进回收站保留 30 天,可在网页界面恢复。置顶的记忆不会被动。默认 false。
  "dreaming": { "enabled": true }
}
```

说明:`chatMessage` 里只写了 `maxAgeDays`,没写的子项(如 `filterInjectedPrompts`、`captureChildSessions`)会各自回落到默认值,不会被整体覆盖(源码 `config.ts` 对每个子项单独用 `?? DEFAULTS` 取值)。

## 六、改完怎么验证

| 检查 | 方法 |
|---|---|
| 配置文件语法是否正确 | 重启 OpenCode,看是否有报错 toast(`showErrorToasts` 要保持开) |
| 捕获是否在工作 | 让会话空闲一会儿,网页界面看有无新记忆 |
| 嵌入是否正常 | 手动让 agent 调 `memory` 搜索一次 |
| 数据是否膨胀 | 定期看 `~/.opencode-mem/` 的体积 |
| OpenCode 升级后 | 再做一遍"捕获是否在工作"的检查 |

## 七、没弄清的问题

- `codebuddy` 自定义 provider 是否可用于后台捕获(需实测)。
- 中文场景下,`similarityThreshold` 的合适取值(需要实测,没有现成数据)。
- 本文的默认值来自 v2.41.0,升级后可能变化,以你本机生成的 `opencode-mem.jsonc` 注释为准。

## 相关页面

- [[opencode-mem-调研与上手指南]]
