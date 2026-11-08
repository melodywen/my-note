---
type: concept
status: developing
area: growth
title: "OpenCode 与 DSH 共享记忆:选型调研"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - dsh
  - 记忆插件
  - 选型
  - 私有化部署
related:
  - "[[claude-mem-深入调研]]"
  - "[[opencode-mem-调研与上手指南]]"
  - "[[opencode-mem-值得调整的配置]]"
---

# OpenCode 与 DSH 共享记忆:选型调研

> 一句话:**想让 OpenCode 和 DSH 共用同一份本地记忆,目前最稳妥的候选是 claude-mem;架构最贴合但星数不足的是 memsearch。** 本文所有结论都来自读 README、源码和 Issue,**没有做过任何实测**,未验证的地方会单独标出。

调研日期 2026-11-07,星数当天用 shields.io 查询(GitHub API 在本机被限流)。

---

## 一、需求与筛选条件

| 条件 | 说明 |
|---|---|
| 共享 | OpenCode 与 DSH(DeepSeek Harness)读写同一份记忆 |
| 私有化 | 数据自控,能本地或内网部署,最好服务端开源可审计 |
| 模型 | 走 codebuddy 的 OpenAI 兼容接口(自定义 baseURL) |
| 语言 | 记忆内容以中文为主 |
| 侵入性 | 旁路 hook 或插件,**不要代理式**;记忆服务挂了不能影响编码 |
| 星数 | 1 万星起步 |
| 现状 | 现用 opencode-mem,只服务 OpenCode |

---

## 二、候选总表

"读到证据"指读过源头;标"未证实"的是子代理或推断的说法。

| 项目              | 星数        | 协议               | OpenCode         | DSH   | 旁路            | 私有化形态                      | 中文               | 主要问题                                |
| --------------- | --------- | ---------------- | ---------------- | ----- | ------------- | -------------------------- | ---------------- | ----------------------------------- |
| **claude-mem**  | 11.4 万    | Apache-2.0       | 官方               | 官方    | 是,hook        | 本机 SQLite + Chroma         | 有中文输出模式,向量嵌入默认英文 | 观察者模型接 codebuddy 未实测;每次工具调用都花 token |
| **memsearch**   | 2.8k(不达标) | MIT              | 官方               | 官方    | 是             | Markdown + Milvus Lite 单文件 | 自带 bge-m3 本地嵌入   | 星数低;共享范围(按项目还是全局)未读清                |
| **MemOS** 本地插件版 | 1.2 万     | Apache-2.0       | 刚合并,未读源头         | 原生    | 官方称 fail-open | 本地 SQLite                  | 国内团队,中文强         | OpenCode 支持证据不足;服务端模式要 Neo4j        |
| **OpenViking**  | 4.2 万     | **AGPLv3**       | 有                | 有     | 中等            | 常驻 Python 服务               | 较好               | AGPL;有 OpenCode 2.x 重复加载插件的 Issue   |
| **Hindsight**   | 6 万       | MIT              | 有                | 有     | 较高            | 需 Postgres                 | **有硬伤**          | Issue #1077 中文 BM25、#5519 中文重排      |
| **Supermemory** | 3.2 万     | 插件 MIT,**服务端闭源** | 官方插件,可改地址        | 无     | 是             | 单二进制                       | 默认英文嵌入           | 服务端只发二进制;免费 1 万文档上限                 |
| **memU**        | 1.46 万    | Apache-2.0       | 无专用适配,靠通用探测(未证实) | 同左    | 是             | SQLite                     | 可选豆包嵌入           | OpenCode、DSH 能否被识别未验证               |
| **Memori**      | 1.74 万    | Apache-2.0       | 无                | 无     | 是             | 只有 BYODB                   | —                | 主流程与 MCP 都指向云端,自托管无证据               |
| **mem0**        | 约 6.8 万   | Apache-2.0       | 官方插件只连云          | 同左    | 是             | Postgres                   | 存疑               | 官方插件写死云地址;自托管缺时间推理、Dream、图记忆        |
| **Cognee**      | 3.3 万     | Apache-2.0       | 仅 MCP            | 仅 MCP | 是             | 较重                         | 一般               | 没有现成插件                              |
| TDAM            | 3.1 万     | MIT              | 有                | 有     | **否,代理式**     | 单机 SQLite                  | —                | Proxy :8096 是单点,首字延迟,全量明文过代理;已否决    |
| Letta           | 2.5 万     | —                | —                | —     | **否,代理式**     | —                          | —                | 已否决                                 |
| Graphiti、Beads  | —         | —                | —                | —     | —             | —                          | —                | 一个是图框架,一个是任务追踪,定位不符                 |
| memvid          | 1.73 万    | Apache-2.0       | 无                | 无     | 是             | 单文件 `.mv2`                 | —                | 没有 MCP,要自己写胶水                       |

---

## 三、推荐排序

1. **claude-mem**:唯一同时满足"星数大、旁路、本地、两端都有官方适配、服务端开源"的。详见 [[claude-mem-深入调研]]。
2. **memsearch**:架构最贴合需求,星数放宽才能选。
   - 记忆是 Markdown 文件,向量库只是可重建的索引,服务挂了文件还在。
   - 自带本地 ONNX bge-m3 嵌入(首次下载约 558MB),BM25 加向量混合检索,中文有保障。
   - 官方给了两条命令:`opencode plugin add @zilliz/memsearch-opencode`、`dsh plugin --profile <name> add @zilliz/memsearch-dsh`。
   - 星数 2.8k 背后是 Zilliz(Milvus 公司),有人维护。
3. **MemOS 本地插件版**:中文最强,但 OpenCode 的本地插件支持刚合并(Issue #2188),没读到源头证据。

备选:memU(留着,试 `memu-agent detect`)、OpenViking(AGPLv3,要常驻服务)。

---

## 四、淘汰理由速记

- **代理式(TDAM、Letta)**:要把模型 baseURL 改指向它,挂了整体不可用。你已明确否决。
- **mem0**:官方 OpenCode 与 DSH 插件都写死 `new MemoryClient({ apiKey })`,默认连云;自托管版缺功能,跑分来自云版。
- **Supermemory**:官方文档明说本地服务端源码"不在公开仓库"。MIT 只覆盖插件、SDK 和 MCP。数据在本机,但得信任那个二进制。没有 DSH 支持。
- **Hindsight**:星数高,但中文 BM25 与重排有已知 Issue,还要 Postgres。
- **Memori**:BYODB 只是自带数据库,主流程要 `MEMORI_API_KEY`,连 `api.memorilabs.ai`。子代理说"换成自己的地址即可",README 里没有这句话。
- **memU**:专用适配只有 Codex、Claude Code、Cursor、OpenClaw、Hermes、WorkBuddy、Cola、pi。

---

## 五、证据质量说明

调研里有 3 路子代理并行,其报告有过度乐观的地方,已被源头核对修正:

| 子代理的说法 | 核对后 |
|---|---|
| memU 对 OpenCode "高度支持" | README 没有 OpenCode 和 DSH 字样 |
| Memori 可自托管、换 MCP 地址即可 | README 无此说明,只有 BYODB |
| Supermemory "极度匹配" | 服务端闭源,且无 DSH 支持 |
| claude-mem "约 10 万星" | shields.io 实测 11.4 万 |
| OpenViking 协议 | 实为 AGPLv3 |

我自己核对过的:memsearch 的 DSH 与 OpenCode 安装命令、OpenViking 协议、memU 与 Memori 两点、Supermemory 本地版与插件 README、claude-mem 的安装器与检索源码。

---

## 六、未验证项(都需要实测)

- claude-mem 的观察者模型能否接 codebuddy。
- claude-mem 在 OpenCode、DSH 上的实际表现(两端都是后加的适配器)。
- claude-mem 的中文语义召回(默认嵌入是英文模型)。
- memsearch 的共享范围:配置里 `milvus.uri` 默认 `~/.memsearch/milvus.db`(全局),但笔记在项目内 `.memsearch/memory/`(按项目)。
- MemOS 在 OpenCode 上的实际支持。
- memU 能否识别 OpenCode 与 DSH 的会话日志。

---

## 七、建议的下一步

1. 只读核实 memsearch 的共享范围(几分钟)。
2. 最小实测:先只装 OpenCode,观察者模型指向 codebuddy,跑一段真实中文会话看能否产出笔记;通过后再碰 DSH。实测前备份配置(见 [[claude-mem-深入调研]] 的部署一节)。
3. 如果中文召回是硬指标,把它作为首要验证项,或并行实测 memsearch,用同一批真实中文会话对比。
