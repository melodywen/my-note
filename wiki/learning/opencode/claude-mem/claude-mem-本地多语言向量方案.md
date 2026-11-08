---
type: concept
status: developing
area: growth
title: "claude-mem 本地多语言向量方案(Ollama + bge-m3)"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - claude-mem
  - 向量
  - 中文检索
  - ollama
related:
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-配置详解]]"
---

# claude-mem 本地多语言向量方案(Ollama + bge-m3)

> 一句话:**claude-mem 默认的向量模型是英文的,中文搜不准。配置里没有"本地多语言模型"这个选项,但可以绕一圈:在本机用 Ollama 跑 `bge-m3`,伪装成 OpenAI 的嵌入接口,让 claude-mem 借用的 chroma-mcp 去连它。不改 claude-mem 源码,数据不出本机。**
>
> 状态:**只在 `/tmp` 的隔离副本里实测通过,真实环境还没上线。** 下文凡是没实测的都标了"未证实"。

---

## 一、先搞懂几个词

| 词 | 大白话 |
|---|---|
| 向量(嵌入) | 把一段文字变成一串数字。意思相近的文字,数字也相近,所以能"按意思找" |
| 嵌入模型 | 干"文字变数字"这件事的模型。不生成文字,不回答问题 |
| 分词器 | 嵌入模型内部的第一步:把句子切成词元,再去词表查编号。英文模型词表里没有汉字,中文会被切成单字或"未知符号",信息丢掉一大块 |
| Chroma | claude-mem 用的向量库,存放所有记忆的向量 |
| chroma-mcp | Chroma 官方出的一个 Python 程序。**claude-mem 自己不实现向量库,而是启动它来读写 Chroma** |
| Ollama | 本机跑大模型/嵌入模型的工具,你已经装了 |
| bge-m3 | 一个多语言嵌入模型,中文很强,1.2 GB,向量 1024 维 |

## 二、问题:为什么现在中文搜不准

- 默认嵌入模型 `all-MiniLM-L6-v2` 只有约 3 万词的英文词表(`models.ts` 源码注释),中日韩文字被切成单字或 `[UNK]`。
- 实测(旧库 29 条观察、12 条查询):中文问中文名次 1、3、12(不稳),中文问英文记忆名次 29、20、22(基本垫底)。详见 [[claude-mem-存储与读取机制]] 6.3 节。
- 搜索不是"关键词 + 向量融合":向量为主,只有某一类结果为空时,才用 SQLite 子串匹配补位。所以向量差,关键词救不回来。

## 三、为什么不能直接改配置换模型

| 配置键 | 实测结果 |
|---|---|
| `CLAUDE_MEM_EMBEDDING_MODEL` | 改成 `multilingual-e5-small` 或不存在的名字,都不报错、也不生效。它只被"服务器模式"(Postgres)读取 |
| `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` | 本机路径真正读的键,但白名单只有 `default / openai / cohere / jina / voyageai / roboflow`。改成白名单外的值,**运行中不报错,重启 worker 后才报错**,所有项目回填失败 |

白名单里除 `default` 外全是云端接口。其中 `openai` 这一个,可以指向本机服务,这就是本方案的突破口。

## 四、原理:chroma-mcp 怎么启动,为什么能接上 Ollama

你机器上的进程树(实测):

```
launchd
 └─ bun worker-service.cjs --daemon      ← claude-mem 的 worker
     └─ uv tool uvx … chroma-mcp --client-type persistent --data-dir ~/.claude-mem/chroma
         └─ Python chroma-mcp            ← 真正算向量、读写向量库
```

关键事实(读 chroma-mcp 0.2.6 与 chromadb 源码,并在隔离环境实测):

1. 创建集合时,chroma-mcp 用**无参**方式构造嵌入函数:`embedding_function()`。所以不能在配置里传模型名或地址。
2. `OpenAIEmbeddingFunction` 无参时,模型名默认 `text-embedding-ada-002`,地址交给底层 openai 库,**会读环境变量 `OPENAI_BASE_URL`**。
3. chroma-mcp 启动时自己会读一个叫 `.chroma_env` 的文件(`--dotenv-path` 默认值),相对它的工作目录。
4. claude-mem 启动它时把工作目录设为家目录(`ChromaMcpManager.ts` 里 `cwd: os.homedir()`),所以实际读的是 **`~/.chroma_env`**。
5. 这个文件被读成环境变量后,openai 库就会去 `OPENAI_BASE_URL` 指的地方请求嵌入。Ollama 的 `/v1/embeddings` 兼容 OpenAI 格式,所以能接上。
6. Ollama 里没有叫 `text-embedding-ada-002` 的模型,请求会 404;用 `ollama cp bge-m3 text-embedding-ada-002` 起个别名解决。

### 为什么不能写进 claude-mem 自己的 `.env`

| | claude-mem 的 `.env` | chroma-mcp 的 `.chroma_env` |
|---|---|---|
| 谁读 | claude-mem worker | chroma-mcp 子进程 |
| 读哪些键 | 只放行 11 个凭据键(`ANTHROPIC_*`、`GEMINI_*`、`OPENROUTER_*`、`OPENAI_COMPAT_*`、`CLAUDE_CODE_OAUTH_TOKEN`),其余丢弃 | 全部读成环境变量 |
| 能放 `OPENAI_BASE_URL` 吗 | 不能 | 能 |

另外 claude-mem 启动 chroma-mcp 时没有传 `--dotenv-path`,所以只能用默认文件名。

## 五、实测结果(全部在 `/tmp` 隔离副本,真实环境未动)

### 5.1 链路

| 环节 | 结果 |
|---|---|
| Ollama `/v1/embeddings` | 通。`nomic-embed-text` 返回 768 维,`bge-m3` 返回 1024 维 |
| 只设 `OPENAI_BASE_URL`(不起别名) | 请求确实打到 Ollama,但 404:`model 'text-embedding-ada-002' not found` |
| 起别名 `text-embedding-ada-002` | 通,1024 维 |
| 通过 `.chroma_env` 传变量 | 通。**worker 进程环境里 `OPENAI_*` 为 0 个**,照样成功 |
| 整库重建 | 284 条观察 + 44 条总结 + 72 条提问,约 70 到 90 秒,`writeFailures=false`,向量 2211 条,维度 1024 |
| 不带变量重开集合 | 失败:`Could not build embedding function openai`。集合存了函数名但**不存地址**,以后每次启动都必须带着变量 |

### 5.2 效果(只能当方向)

用真实库的副本,6 条中文查询,看"我人工指定的相关观察"是否出现在前 6 名:

| 嵌入模型 | 命中 |
|---|---|
| 默认英文 MiniLM(现状) | 1/6 |
| bge-m3(Ollama) | 5/6,两次独立重建结果一致 |

**这个数字不可信到百分之百,原因:**
- 只有 6 条查询;标准答案是我凭观察标题人工挑的,不是独立评判。
- 判定宽松:前 6 名出现任一条就算命中。
- 没命中的那一条("多语言模型提升了多少",我指定 #249)核查后发现:bge-m3 返回的前 6 条里,#207(明说"外部评测数据未证实")、#244、#245、#250 同样高度相关,**是我的标准答案划窄了**,不是模型错。但含具体数字 12%→34.5% 的 #249 确实没进前 6。
- 英文查询、中英混排、长句、库变大后的表现,都**没测**。

补充的 4 文档小样本(纯向量):bge-m3 第 1 名命中 4/4,默认 MiniLM 1/4。

## 六、落地步骤(未上线,按此执行)

1. Ollama 保持运行,拉取模型并起别名:
   ```bash
   ollama pull bge-m3
   ollama cp bge-m3 text-embedding-ada-002
   ```
2. 在配置仓库 `~/.config/opencode/claude-mem/` 放真文件 `chroma_env`,软链到家目录,与 `settings.json`、`.env` 的做法一致:
   ```bash
   ln -s ~/.config/opencode/claude-mem/chroma_env ~/.chroma_env
   ```
   文件内容两行(`OPENAI_API_KEY` 是占位,不是真 key):
   ```
   OPENAI_API_KEY=ollama
   OPENAI_BASE_URL=http://127.0.0.1:11434/v1
   ```
3. `settings.json` 改 `"CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION": "openai"`,并同步 `settings.example.jsonc`。
4. 备份 `~/.claude-mem/chroma`,清掉旧向量(旧的是 384 维,不能与 1024 维混用),重启 worker 触发整库重建。
5. 核对:日志无 `ERROR`、Chroma 集合维度为 1024、搜索正常。

回退:把 `CHROMA_EMBEDDING_FUNCTION` 改回 `default`,恢复备份的 `chroma` 目录或再次整库重建,重启 worker。

## 七、风险与限制

| 风险 | 说明 |
|---|---|
| 依赖第三方内部行为 | `.chroma_env` 是 chroma-mcp 0.2.6 自带的行为,不是 claude-mem 官方支持的配置。claude-mem 升级后若换了 chroma-mcp 版本或启动方式,可能失效(失效时向量写入失败,SQLite 记忆不丢,日志有报错) |
| Ollama 变成常驻依赖 | 没开时新记忆写不进向量库;恢复后回填会补上(推断,回填机制本次已见到,断 Ollama 场景未专门测) |
| 重建期间搜索不可用 | 约 1 到 2 分钟 |
| 换机器容易漏 | 需要同时有 Ollama、`bge-m3` 与别名、`~/.chroma_env` 软链 |
| 别名占用名字 | 以后若想用 Ollama 里真正的 `text-embedding-ada-002` 会冲突 |
| 软链形式的 `~/.chroma_env` | 已实测:真文件在 `~/.config/opencode/claude-mem/chroma_env`,软链到家目录后,`load_dotenv` 能读到,无参 `OpenAIEmbeddingFunction` 返回 1024 维(单独脚本测,未经 worker) |
| 内存与长期稳定性 | 未测 |
| 官方是否有人在 issue 里提过这条路 | 没查到,未证实 |

## 八、社区与官方做法(对照)

| 项 | 内容 | 依据 |
|---|---|---|
| #3422(已合入) | 把 Chroma 嵌入函数暴露为设置项。作者用韩文语料实测 R@1:默认 12.0%/10.0%,`paraphrase-multilingual-MiniLM-L12-v2` 为 34.5%/32.5%(均 384 维)。但它原本想推荐的 `multilingual` 值 chroma-mcp 0.2.6 不认识,同一 PR 第二个提交又收窄成六个值 | 读到提交原文 `e94f74760` |
| #4148、#3173、#3361(已合入) | 关键词层:中英混排按词拆分子串匹配;向量某类为空时 SQLite 补查 | 读到提交说明 |
| #5001、#5002、#5003(已合入) | 服务器模式(Postgres):pgvector 向量搜索、4 个本地多语言模型、BM25 与向量 RRF 融合 | 读到提交说明;本机 worker 路径用不上 |
| #1789、PR #2492(RRF 融合) | 本地 worker 路径未合入 | 提交历史里查不到,**没读到 issue 原文** |
| #3982 的具体状态与评测数据 | 未取得 | 未证实 |

## 九、中文检索的三层现状(汇总)

| 层 | 对中文 | 备注 |
|---|---|---|
| 关键词(SQLite) | 勉强够用:含汉字走 LIKE 子串匹配,能搜到,但不排序、不懂同义 | FTS5 的 `unicode61` 不切汉字,#3801 |
| 向量(默认模型) | 弱 | 本方案要解决这层 |
| 两层怎么合 | 向量为主,仅某类为空时补位 | 无融合排序 |

---

## 十、待办与未证实清单

1. 用 15 到 20 条你真实会问的问题(中英文都要),列出每条前 6 名标题,由你判断相关性,再算命中。
2. 英文查询、中英混排、短关键词下 bge-m3 的表现。
3. Ollama 停止/被换出内存时,claude-mem 的行为与恢复。
4. `bge-m3` 的内存占用与重建耗时在更大库上的表现。
5. claude-mem 升级后这条路是否仍然有效。
