---
type: project
status: researching
area: dsh-plugin-dev
tags: [project, dsh, 知识库插件, vector, embedding, sqlite-vec, 调研, 有出处]
created: 2026-09-28
updated: 2026-09-28
---

# 14 向量检索调研——sqlite-vec + 本地模型选型

> [!info] 文档状态
> - 状态：**调研稿 v1**（2026-09-28）
> - 前置：[[08 检索与索引——FTS5基座与注入纪律]]（V1 FTS5 基座已定，本文是 V2 向量层的选型调研）
> - 学习者诉求（2026-09-28）：① 要上向量检索（不等 V2 痛点，直接做）；② 纯进程内，不拉独立服务；③ **精度优先，越大越准越好，不要快**

---

## 一、调研结论（先给结果）

**推荐方案：`sqlite-vec`（向量存储 + KNN 查询）+ `@xenova/transformers`（本地 ONNX 模型推理）+ `BGE-M3`（embedding 模型）**

三者全部进程内运行，零外部服务，无 Python / 无 llama.cpp / 无 Ollama。

| 组件 | 选型 | 角色 | 出处 |
|---|---|---|---|
| 向量存储 | **sqlite-vec** v0.1.9 | `vec0` 虚拟表存向量，KNN 近邻查询 | [sqlite-vec GitHub](https://github.com/asg017/sqlite-vec) |
| 推理运行时 | **@xenova/transformers**（Transformers.js） | Node.js 进程内 ONNX Runtime，下载即用 | [Transformers.js 文档](https://huggingface.co/docs/transformers.js) |
| Embedding 模型 | **Xenova/bge-m3**（BGE-M3，1024 维） | 精度最优的多语言 embedding 模型 | [Xenova/bge-m3 HF](https://huggingface.co/Xenova/bge-m3) |
| 融合策略 | **RRF**（Reciprocal Rank Fusion） | FTS5 BM25 + 向量 KNN 两路排名融合 | 08 篇已规划，社区标配 |

---

## 二、为什么是这三个（逐个论证）

### 2.1 sqlite-vec：唯一的「进程内向量存储」

**是什么**：SQLite 的一个 C 扩展模块（单个 `.so`/`.dylib`/`.dll` 文件），给 SQLite 加了一个 `vec0` 虚拟表类型，专门存浮点向量、做 KNN 近邻查询。由 Alex Garcia 开发，是已归档的 `sqlite-vss` 的官方继任者。Mozilla Builders 赞助项目，MIT/Apache-2.0 双许可。

> **出处**：[sqlite-vec GitHub](https://github.com/asg017/sqlite-vec)；[Alex Garcia 博客](https://alexgarcia.xyz/sqlite-vec/)

**核心 API**：

```sql
-- 1. 建向量表（1024 维，cosine 距离）
CREATE VIRTUAL TABLE vec_docs USING vec0(
  embedding FLOAT[1024] distance_metric=cosine
);

-- 2. 插入向量（Float32 BLOB 或 JSON 数组）
INSERT INTO vec_docs(rowid, embedding) VALUES (1, :vector_blob);

-- 3. KNN 查询：找最相似的 K 条
SELECT rowid, distance
FROM vec_docs
WHERE embedding MATCH :query_vector
ORDER BY distance
LIMIT 10;
```

**关键特性**：
- **零外部依赖**：纯 C，不依赖 FAISS（前任 sqlite-vss 的致命伤）、不依赖 Python
- **进程内嵌入**：`npm install sqlite-vec`，`sqliteVec.load(db)` 一行加载，跟 `better-sqlite3` 在同一个 DB 连接里
- **SIMD 加速**：x86 AVX2/AVX-512、ARM NEON、Apple Silicon 全支持，暴力扫描也很快
- **支持量化**：`float32` / `float16` / `int8` / `bit`（二值），可压缩存储和加速
- **与 FTS5 同库**：向量表和 FTS5 表在同一个 `.db` 文件里，同一个 `better-sqlite3` 连接操作

> **出处**：sqlite-vec 官方 README；[npm: sqlite-vec](https://www.npmjs.com/package/sqlite-vec)

**局限性（诚实声明）**：
- 当前只做**暴力精确搜索**（exact brute-force），没有 ANN 近似索引。查询复杂度 O(N)。但 SIMD 使其在 10 万级向量下仍然是毫秒级。ANN（DiskANN / IVF）在 v0.1.10-alpha 中开发中，v1.0 路线图包含 HNSW
- 继承 SQLite 单写者并发模型——对知识库场景完全够用（写入只在归档时发生）
- 没有「原生混合搜索」：FTS5 + vec0 的融合需要手动 SQL JOIN 或 CTE，但社区已有成熟的 RRF 模式

> **出处**：sqlite-vec README "Limitations" 段；v0.1.10-alpha.4 release notes（2026-05-18）

**当前版本**：v0.1.9（2026-03-31），pre-v1，API 未冻结但已广泛使用（npm 月下载百万级）。社区项目大量在用（见第五节）。

### 2.2 @xenova/transformers（Transformers.js）：唯一的「进程内模型推理」

**是什么**：Hugging Face `transformers` 的 JavaScript 移植版，底层用 ONNX Runtime（WebAssembly / WebGPU），在 Node.js 进程内直接跑模型推理。不调 API、不拉服务、不装 Python。

> **出处**：[Transformers.js 文档](https://huggingface.co/docs/transformers.js)；[GitHub: xenova/transformers.js](https://github.com/xenova/transformers.js)

**用法（生成 embedding）**：

```typescript
import { pipeline } from '@xenova/transformers';

// 单例懒加载（首次调用下载模型，后续热查询 10-30ms）
const extractor = await pipeline('feature-extraction', 'Xenova/bge-m3', {
  quantized: true,  // 8-bit 量化，体积小速度快
});

// 生成 embedding（cls pooling + normalize）
const output = await extractor(text, { pooling: 'cls', normalize: true });
const vector = Array.from(output.data);  // Float32Array → number[]，1024 维
```

**关键特性**：
- **纯 Node.js 进程内**：`npm install @xenova/transformers`，无 Docker、无 Python、无独立进程
- **模型自动下载缓存**：首次运行从 Hugging Face Hub 拉模型到本地缓存（`~/.cache/huggingface/hub`），之后离线可用
- **量化模型**：8-bit 量化版体积大幅缩小（BGE-M3 量化版 ~587MB），推理速度提升，精度损失极小
- **v3 迁移**：库正在被 Hugging Face 官方收编为 `@huggingface/transformers`，API 兼容

> **出处**：[Transformers.js v3 迁移指南](https://huggingface.co/blog/transformers-js-v3)

**冷启动 vs 热查询**：
- 首次加载（冷启动）：下载模型 + 加载到内存，几秒到十几秒
- 后续查询（热查询）：单条文本 10-30ms（小模型），大模型（BGE-M3）几百毫秒——**你说了不要快要准，这个代价可接受**

### 2.3 BGE-M3：精度优先的 embedding 模型

**是什么**：BAAI（北京智源人工智能研究院）开源的 embedding 模型，全称 BGE-M3。M3 = Multi-linguality（多语言）、Multi-granularity（多粒度）、Multi-Functionality（多功能）。

> **出处**：[BAAI/bge-m3 HF](https://huggingface.co/BAAI/bge-m3)；[BGE-M3 论文](https://arxiv.org/abs/2402.03216)

**为什么选它（精度优先）**：

| 维度 | BGE-M3 | all-MiniLM-L6-v2（对比） |
|---|---|---|
| **维度** | 1024 | 384 |
| **参数量** | 568M | 22M |
| **最大序列长度** | 8192 tokens | 512 tokens |
| **语言** | 100+ 语言（含中文，原生支持） | 主要英文 |
| **MTEB 多语言排名** | **榜首**（超越 OpenAI text-embedding-3） | 一般 |
| **NDCG@10 精度** | 65.8%（基准测试） | ~55% |
| **量化后大小** | ~587MB（8-bit ONNX） | ~23MB |
| **Transformers.js 支持** | ✅ `Xenova/bge-m3` | ✅ `Xenova/all-MiniLM-L6-v2` |

> **出处**：[BGE-M3 基准测试](https://huggingface.co/BAAI/bge-m3)（MIRACL / MKQA / MLDR 多语言榜单）；[本地模型 vs OpenAI 对比测试](https://inferenceai.tech/article/migrating-away-from-openai-embeddings-high-performance-local-vector-encoding)（BGE-M3 NDCG@10 = 65.8%，超越 OpenAI text-embedding-3-small 的 62.5%）

**对你的场景特别契合的点**：
1. **中文原生支持**：你的知识库内容大量中文（史实、方法论、编码习惯），BGE-M3 在中文检索任务上表现最优
2. **长文本（8192 tokens）**：你的文章是 Obsidian wiki 页面，可能较长。512 tokens 的模型会截断，BGE-M3 不会
3. **多语言**：代码注释、API 文档、术语可能有英文混排，BGE-M3 天然处理
4. **精度最高**：你明确说「越大越好越准越好，不要快」——568M 参数的 BGE-M3 是 Transformers.js 能跑的最大的 embedding 模型之一

**Transformers.js 里实际跑的版本**：`Xenova/bge-m3`，是 BAAI 原始模型转成 ONNX 格式的版本，由 Xenova 维护。

> **出处**：[Xenova/bge-m3 HuggingFace](https://huggingface.co/Xenova/bge-m3)；[Transformers.js issue #553](https://github.com/huggingface/transformers.js/issues/553)（BGE-M3 转换讨论，量化版可用，FP32 超 4GB WASM 堆限制不可用）

**备选模型（如果 BGE-M3 太重）**：

| 模型 | 维度 | 量化大小 | 特点 | 何时用 |
|---|---|---|---|---|
| `Xenova/bge-large-en-v1.5` | 1024 | ~340MB | 英文精度高，512 序列 | 纯英文场景 |
| `Xenova/bge-small-zh-v1.5` | 512 | ~100MB | 中文专用小模型 | 要快一点但保持中文 |
| `Xenova/nomic-embed-text-v1.5` | 768 | ~137MB | 长上下文 8192，支持维度截断 | 折中选 |

> **出处**：[MTEB 排行榜](https://huggingface.co/spaces/mteb/leaderboard)；各模型 HF 页面

---

## 三、架构设计（V2 向量层如何叠加到 V1 FTS5 上）

### 3.1 整体架构

```
用户查询
  │
  ├── 术语表扩展（V1 已有）
  │     ↓
  ├── FTS5 路径（V1 已有）
  │     → BM25 排序 → 排名列表 A
  │
  └── 向量路径（V2 新增）
        ├── 本地模型生成 query embedding（BGE-M3, 1024 维）
        ├── sqlite-vec KNN 查询 → 距离列表
        └── 距离 → 排名列表 B
  │
  └── RRF 融合 A + B → 最终排序
```

### 3.2 索引 schema（V2，叠加到 V1 的同一个 .db）

```sql
-- V1 已有：FTS5 全文索引
CREATE VIRTUAL TABLE knowledge_base_docs USING fts5(
  title, path, frontmatter, body,
  tokenize='trigram'
);

-- V2 新增：向量索引（与 FTS5 同库同连接）
CREATE VIRTUAL TABLE knowledge_base_vec USING vec0(
  rowid INTEGER PRIMARY KEY,   -- 与 FTS5 rowid 对齐
  embedding FLOAT[1024] distance_metric=cosine
);
```

**关键设计**：`vec0` 表和 FTS5 表共享同一 `rowid` 空间——插入时先写 FTS5 行拿到 `rowid`，再用同一 `rowid` 写向量。查询时 JOIN 两表即可拿到 path/title + 距离。

> **出处**：社区标配模式，见 [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom) 的 `sqlite_vector.py`（最干净的 reference implementation）；[openclaw/openclaw](https://github.com/openclaw/openclaw) memory-core 的 `vec0` 表设计

### 3.3 查询流水线

```typescript
// 1. 术语表扩展（V1 已有）
const expandedQuery = expandWithGlossary(rawQuery);

// 2. FTS5 路径（V1 已有）
const ftsResults = db.prepare(`
  SELECT rowid, bm25(knowledge_base_docs) as score
  FROM knowledge_base_docs
  WHERE knowledge_base_docs MATCH ?
  ORDER BY score LIMIT ?
`).all(expandedQuery, k);

// 3. 向量路径（V2 新增）
const queryEmbedding = await embed(expandedQuery);  // BGE-M3, 1024 维
const vecResults = db.prepare(`
  SELECT rowid, distance
  FROM knowledge_base_vec
  WHERE embedding MATCH ?
  ORDER BY distance LIMIT ?
`).all(float32ToBlob(queryEmbedding), k);

// 4. RRF 融合
const fused = rrfFusion(ftsResults, vecResults, k);
```

### 3.4 RRF 融合公式

```
RRF_score(doc) = Σ  1 / (rrf_k + rank_i(doc))
```

- `rrf_k` 通常取 60（社区默认值）
- 不需要两路分数对齐（BM25 分数和 cosine 距离量纲不同），只看排名——简单有效

> **出处**：[Reciprocal Rank Fusion 论文](https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf)；社区 RAG 项目几乎全用此模式

### 3.5 索引同步时机

与 V1 完全一致：**审阅闭环的归档动作 = 索引刷新点**。

归档一篇文章时：
1. 写入 FTS5 行（V1 已有）→ 拿到 `rowid`
2. 用 BGE-M3 生成文章全文（或标题+frontmatter+摘要）的 embedding
3. 用同一 `rowid` 插入 `vec0` 表

删除文章时：同步删除 FTS5 行和 vec0 行。

**索引可全量重建**：删 `.db` → 遍历 vault markdown → 逐篇生成 embedding → 重建两个索引。源无损。

### 3.6 chunk 策略（待议）

BGE-M3 支持最长 8192 tokens，你的 wiki 文章大多在数千字以内（几百到几千 token），**V1 可以不做 chunk，整篇一个向量**。

如果后续遇到长文章（超过 8192 tokens）：
- **方案 A**：按标题层级分段，每段一个向量，`rowid` 用 `rowid * 100 + chunk_idx` 编码
- **方案 B**：滑动窗口分块，重叠 20%
- 当前不处理，等真遇到再说

---

## 四、Float32 序列化（JS ↔ sqlite-vec 的数据桥）

sqlite-vec 的 `MATCH` 参数和 `INSERT` 的向量列接受两种格式：
1. **JSON 数组字符串**：`'[0.1, 0.2, ...]'`——简单但体积大、解析慢
2. **Float32 BLOB**：`Float32Array` → 小端字节 → `Buffer`——紧凑高效，生产推荐

```typescript
// 编码：number[] → Float32Array → Buffer（写入 sqlite-vec）
function encodeVector(vec: number[]): Buffer {
  return Buffer.from(new Float32Array(vec).buffer);
}

// 解码（从 sqlite-vec 读出后转回 number[]）
function decodeVector(buf: Buffer): number[] {
  return Array.from(new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4));
}
```

> **出处**：[CherryHQ/cherry-studio](https://github.com/CherryHQ/cherry-studio) `encodeVectorBlob` 实现；[headroomlabs/headroom](https://github.com/headroomlabs-ai/headroom) `struct.pack(f"{n}f", ...)` 的 JS 等价

---

## 五、社区实践印证（大量项目已在这么做）

### 5.1 TypeScript/Node.js 项目（与你的技术栈一致）

| 项目 | 技术栈 | 做法 | 出处 |
|---|---|---|---|
| **openclaw/openclaw** | TS + better-sqlite3 + sqlite-vec | FTS5 + vec0 混合检索，per-platform 二进制加载 | [GitHub](https://github.com/openclaw/openclaw) `extensions/memory-core/` |
| **CherryHQ/cherry-studio** | TS + better-sqlite3 | `vec_distance_cosine` 标量函数模式 + BGE embedding | [GitHub](https://github.com/CherryHQ/cherry-studio) |
| **laurent22/joplin** | TS + sqlite-vec | `note_embeddings_vec` 表，懒加载建表，BGE embedding | [GitHub](https://github.com/laurent22/joplin) `NoteEmbedding.ts` |
| **nanbingxyz/5ire** | TS + Transformers.js | `Xenova/bge-m3` 做 document embedding，ONNX 量化版 | [GitHub](https://github.com/nanbingxyz/5ire) `constants.ts` |
| **AnnaSuSu/TechSpar** | TS + Transformers.js | `Xenova/bge-m3` 默认 embedding 模型，batch=10 | [GitHub](https://github.com/AnnaSuSu/TechSpar) `model.ts` |
| **Lapis0x0/obsidian-yolo** | TS + Transformers.js | Obsidian RAG 插件，BGE-M3 1024 维，多语言 | [GitHub](https://github.com/Lapis0x0/obsidian-yolo) `catalog.ts` |

### 5.2 dsh 社区插件（同生态，直接参考）

| 插件 | 做法 | 出处 |
|---|---|---|
| **xiaoshi7915/dsh-kb-manager** | sqlite-vec 向量 + BM25 混合 + bge-reranker-base 重排，22 个工具 + Web 面板 | Obsidian 笔记 `社区插件/01 社区插件完整清单` |
| **Asher-2000/dsh-memory-connect** | SQLite FTS5 + 本地 bge-small-zh embedding + cosine + RRF 融合，纯本地无云 | 同上 |
| **kenz1117/dsh-engram** | FTS5 + 本地向量检索 + RRF 融合 + 衰减遗忘 | 同上 |
| **Breeze136/dsh-kb-rag** | BM25 + 向量 + reranker，全本地 bge embedding | 同上 |

### 5.3 Python 项目（架构模式可借鉴）

| 项目 | 做法 | 出处 |
|---|---|---|
| **blakeblackshear/frigate** | 本地 ONNX CLIP 模型 + sqlite-vec，生产级 NVR 语义搜索 | [GitHub](https://github.com/blakeblackshear/frigate) `frigate/embeddings/` |
| **headroomlabs-ai/headroom** | 最干净的 sqlite-vec CRUD + KNN reference implementation | [GitHub](https://github.com/headroomlabs-ai/headroom) |
| **suanrongqieqiezi/bigeye** | ONNX BGE-small + sqlite-vec，最小可用示例 | [GitHub](https://github.com/suanrongqieqiezi/bigeye) |

### 5.4 社区模式总结

从以上项目中提炼出的**标准配方**：

1. **两表共用 rowid**：FTS5 表 + vec0 表，插入时先写元数据拿到 rowid，再用同一 rowid 写向量
2. **Float32 BLOB 序列化**：生产代码不用 JSON，用 `Float32Array` → 字节流
3. **KNN 查询固定模式**：`WHERE embedding MATCH ? AND k = ? ORDER BY distance`
4. **RRF 融合**：BM25 排名 + cosine 排名取倒数加权求和
5. **平台二进制分发**：sqlite-vec 按平台/架构分发包（`sqlite-vec-darwin-arm64` / `sqlite-vec-linux-x64` / `sqlite-vec-windows-x64`），加载时选对应包
6. **降级策略**：sqlite-vec 加载失败 → 退化为纯 FTS5（向量是增强层，不是必需层）

---

## 六、平台与安装

### 6.1 npm 依赖

```bash
# 向量存储（sqlite-vec 按平台分包）
npm install sqlite-vec

# 模型推理（Transformers.js）
npm install @xenova/transformers
# 或 v3: npm install @huggingface/transformers
```

### 6.2 sqlite-vec 平台支持

| 平台 | 架构 | npm 包 | 状态 |
|---|---|---|---|
| macOS | arm64 (Apple Silicon) | `sqlite-vec-darwin-arm64` | ✅ 原生 |
| macOS | x64 (Intel) | `sqlite-vec-darwin-x64` | ✅ |
| Linux | x64 | `sqlite-vec-linux-x64` | ✅ |
| Windows | x64 | `sqlite-vec-windows-x64` | ✅ |
| Windows | arm64 | — | ⚠️ 无官方构建（社区 fork `@aiany/sqlite-vec-*`） |

> **出处**：[sqlite-vec releases](https://github.com/asg017/sqlite-vec/releases)；社区处理见 [openclaw/openclaw](https://github.com/openclaw/openclaw) `PLATFORM_VARIANTS` 和 [janhq/jan](https://github.com/janhq/jan) 的降级逻辑

你当前环境是 macOS Apple Silicon（M 系列），原生支持，无问题。

### 6.3 模型缓存

BGE-M3 量化版首次下载 ~587MB，缓存到 `~/.cache/huggingface/hub/`。后续离线可用。可配置 `env.cacheDir` 改缓存位置。

离线部署场景：手动下载 `.onnx` + `tokenizer.json` + `config.json` 放到本地目录，设 `env.allowRemoteModels = false` + `env.localModelPath = '/path/to/models/'`。

> **出处**：Transformers.js 文档 "Offline usage"

---

## 七、精度 vs 性能的诚实权衡

你说「不要快要准」，BGE-M3 是对的。但要如实记录代价：

| 指标 | BGE-M3 (1024维, 568M) | all-MiniLM-L6-v2 (384维, 22M) |
|---|---|---|
| 首次下载 | ~587MB | ~23MB |
| 内存占用 | ~1-2GB | ~100MB |
| 单条 embedding 生成（CPU 热查询） | ~200-500ms | ~10-30ms |
| 批量 embedding（100 篇文章初始索引） | ~20-50秒 | ~1-3秒 |
| KNN 查询（sqlite-vec, 1万向量） | ~5-15ms | ~2-5ms（维度低更快） |
| 中文检索精度 | **最优** | 一般 |
| 长文本支持 | **8192 tokens** | 512 tokens（截断） |

**结论**：对于知识库插件（不是实时聊天，索引是异步的，查询是低频的），BGE-M3 的代价完全可接受。初始索引 100 篇文章花 30 秒，后续每篇归档时增量生成一个 embedding 花不到 1 秒——用户无感。

> **出处**：[nimbalyst/nimbalyst](https://github.com/nimbalyst/nimbalyst) `localModels.ts` 记录了 BGE-M3 `downloadBytes: 586_761_000`，`chunksPerSec: 8`；[Transformers.js issue #553](https://github.com/huggingface/transformers.js/issues/553) 记录量化版推理 ~1352ms（含冷启动），FP16 + WebGPU ~52ms

---

## 八、与 08 篇的关系（V1 → V2 的演进）

08 篇规划的三个层次：

| 层 | 08 篇原文 | 本文状态 |
|---|---|---|
| V1 基座 | FTS5 + trigram + BM25 | ✅ 已确认，已实现（见 12 篇实现记录） |
| V2 可选 | "叠加本地 embedding（sqlite-vec / 本地模型）+ RRF 融合" | **本文将 V2 从'可选'升级为'要直接做'** |
| 永不丢的底 | 源与索引分离，索引可全量重建 | ✅ 本文继承，向量索引同样是可重建的派生物 |

08 篇第五节「能力边界」里标的 ❌ 语义缺口（"怎么让项目变快"→命中"性能优化"），就是 V2 向量层要解决的问题。BGE-M3 的语义理解能力可以直接把"项目变快"映射到"性能优化"附近的向量空间。

---

## 九、待议清单

1. **embedding 输入文本**：整篇 markdown 全文？还是标题 + frontmatter + 摘要？全文更准但生成慢；摘要够用但可能丢信息。倾向：标题 + frontmatter + 正文（BGE-M3 支持 8192 tokens，大部分文章放得下）
2. **chunk 策略**：V1 不做 chunk（整篇一个向量）。超过 8192 tokens 的文章怎么处理？暂不处理，等遇到再说
3. **模型版本锁定**：BGE-M3 量化版具体用哪个 commit？需要锁定版本避免不同版本 embedding 不兼容
4. **RRF 的 k 参数**：默认 60，是否需要调参？初期用默认值，后续看效果
5. **降级策略**：sqlite-vec 加载失败 / 模型下载失败时，退化为纯 FTS5？倾向：是，向量是增强层
6. **embedding 生成时机**：归档时同步生成（阻塞归档）？还是异步 job？倾向：同步，因为归档本身就是低频人工动作
7. **Windows arm64 支持**：当前无官方构建，是否需要社区 fork？你用 macOS 暂不影响，但插件发布要考虑
8. **向量维度未来切换**：如果以后换模型维度变了（如从 1024 换到 768），需要重建向量索引。FTS5 不受影响。设计上要保证重建只需删 vec0 表重新生成

---

## 十、参考资料汇总

### 官方文档
- [sqlite-vec GitHub](https://github.com/asg017/sqlite-vec) — 向量扩展源码与文档
- [Transformers.js 文档](https://huggingface.co/docs/transformers.js) — JS 模型推理库
- [BAAI/bge-m3 HF](https://huggingface.co/BAAI/bge-m3) — 模型原始页面与基准测试
- [Xenova/bge-m3 HF](https://huggingface.co/Xenova/bge-m3) — ONNX 转换版（Transformers.js 直接用这个）
- [BGE-M3 论文](https://arxiv.org/abs/2402.03216) — 模型设计论文

### 社区实践
- [openclaw/openclaw](https://github.com/openclaw/openclaw) — TS, FTS5+vec0 混合，per-platform 加载
- [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom) — 最干净的 sqlite-vec CRUD+KNN 参考
- [blakeblackshear/frigate](https://github.com/blakeblackshear/frigate) — 生产级 ONNX+sqlite-vec
- [nanbingxyz/5ire](https://github.com/nanbingxyz/5ire) — TS, Xenova/bge-m3 document embedding
- [AnnaSuSu/TechSpar](https://github.com/AnnaSuSu/TechSpar) — TS, Xenova/bge-m3 默认模型
- [Lapis0x0/obsidian-yolo](https://github.com/Lapis0x0/obsidian-yolo) — Obsidian RAG, BGE-M3 1024 维
- [CherryHQ/cherry-studio](https://github.com/CherryHQ/cherry-studio) — TS, better-sqlite3 向量搜索
- [laurent22/joplin](https://github.com/laurent22/joplin) — 笔记应用 vec0 embedding

### 基准与对比
- [本地模型 vs OpenAI 对比](https://inferenceai.tech/article/migrating-away-from-openai-embeddings-high-performance-local-vector-encoding) — BGE-M3 NDCG@10 = 65.8%
- [MTEB 排行榜](https://huggingface.co/spaces/mteb/leaderboard) — embedding 模型综合排名
- [Transformers.js issue #553](https://github.com/huggingface/transformers.js/issues/553) — BGE-M3 转换与性能讨论

### dsh 生态
- Obsidian 笔记 `社区插件/01 社区插件完整清单（全 4312 条）.md` — dsh-kb-manager / dsh-memory-connect / dsh-engram / dsh-kb-rag 等
- [[08 检索与索引——FTS5基座与注入纪律]] — V1 基座设计
- [[00 项目总览——需求与锚点]] — 源与索引分离原则
