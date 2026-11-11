---
type: concept
status: developing
area: growth
title: "claude-mem 升级与版本记录"
created: 2026-11-11
updated: 2026-11-11
tags:
  - learning
  - opencode
  - claude-mem
  - 升级
related:
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-从0到1总览]]"
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-配置详解]]"
---

# claude-mem 升级与版本记录

> 一句话:**本机 claude-mem 现为 v15.16.0(2026-11-11 升级)。这篇记录版本轨迹、升级的实际命令与坑,以及每个版本对旧文档结论的影响。**

## 一、版本轨迹

| 时间 | 版本 | 说明 |
|---|---|---|
| 2026-11-08 | 15.12.0 → 15.12.1 | 首次安装与早期调教,多数文档的源码依据是 15.12.0 |
| 2026-11-11 | v15.16.0 | 升级;期间核对过 v15.15.1 / v15.15.2 的源码与发布说明 |

## 二、升级怎么做(实测路径)

1. **先备份**:`claude-mem.db`、`settings.json`、`~/.chroma_env`、旧插件文件、opencode 配置,放到 `~/.claude-mem/upgrade-backup-<时间戳>/`。
2. **只指定 opencode 安装**:`npx claude-mem@latest install --ide opencode --no-auto-start`。
   - 不指定 IDE 的整体 `install` 曾报 `all-ides-failed`,单独指定 `--ide` 可以绕过。
3. **重启 worker**:`npx claude-mem@latest restart`。升级后不重启,旧 worker 仍在跑旧代码。
4. **重启 opencode**,让新插件 `~/.config/opencode/plugins/claude-mem.js` 生效。
5. **核对**:插件文件与插件源 dist 哈希一致;`settings.json`、`~/.chroma_env` 对比备份无变化;my-note 观察条数不变(升级前后均 1377 条)。

升级不会覆盖已有的 `settings.json` 与向量模型配置。

## 三、配置文件统一为 opencode.json

- opencode V2 同时读取 `opencode.json` 与 `opencode.jsonc` 并合并,**并存不冲突**。
- 但 claude-mem 安装器写死 `opencode.json`(`OpenCodeInstaller.ts:109`),不检查 `.jsonc`,不存在就新建。升级时因此新建了一份 `opencode.json`。
- 处理:把 `.jsonc`(原文件无注释)合并进 `~/.config/opencode/opencode.json`,删除 `.jsonc`。以后新增配置都改 `opencode.json`。合并后 `opencode mcp list` 全部 MCP 为 connected。
- V2 的 debug config 里 MCP 显示为 `mcp.servers.<名字>`,V1 写法 `mcp.<名字>` 仍兼容。

## 四、各版本对旧结论的影响

| 版本 | 变化 | 对文档结论的影响 |
|---|---|---|
| v15.16.0 | 修复 #5666:插件把小写 `bash` 映射为 `Bash` | `SKIP_BASH_PATTERNS` 对 OpenCode **从此生效**。实测 Bash+命中脚本 => `skipped(bash_pattern_excluded)`,小写 bash 仍入队 |
| v15.16.0 | 搜索只有边界修复(Unicode、project key、timeline 前缀) | 发布说明层面,未读 v15.16.0 代码 diff;检索结论仍以 v15.15.1 源码为准 |
| v15.15.2 | `REDACT_ENABLED=true` 时 server capture 先脱敏 | 本机是本地 worker 模式,是否实际生效未核对 |
| v15.15.1 | (源码核对基线) | 搜索机制:本地向量优先、SQLite 为空才补、无 RRF;RRF 仅服务器 Postgres 模式 |

`SKIP_BASH_PATTERNS` 生效后的限制:只拦命中的脚本调用本身,拦不住 `cd` 进目录后相对路径调用,也拦不住读旧记忆的 `curl`。

## 五、升级后做过的采集配置调整

- `CLAUDE_MEM_SKIP_TOOLS` 追加 `claude_mem_search`、`claude_mem_timeline`、`claude_mem_get_observations`(现共 17 项)。匹配规则:整名精确相等、不分大小写、不支持通配符。worker 另有内置 `memory_retrieval` 规则也会跳过它们,这里是双保险。
- 不开 `SKIP_SUBAGENT_OBSERVATIONS`:判定 subagent 需 `agentId` 与 `agentType` 同时存在,opencode 插件不带,对 OpenCode 无效;即使有效也会丢掉 subagent 探索、评审时有价值的发现。
- `REDACT_ENABLED` / `REDACT_GENERIC_ENABLED` 出厂默认均为 false(opt-in),本机均设为 true。
- 配置仓库 `opencode-config` 提交:`333ce9c`(jsonc→json)、`9c99566`(SKIP_TOOLS 与示例注释同步)。

## 六、仍未做 / 未验证

- 未把 `api/(observations/batch|import)` 追加进 `SKIP_BASH_PATTERNS`(只是建议)。
- 未逐项重新核对 v15.16.0 的 238 键清单。
- 未做 v15.15.1 → v15.16.0 搜索链路的代码 diff。
- `EXCLUDED_PROJECTS` 整体排除整理链路的方案未实测(不确定 opencode 起 subagent 能否指定 cwd)。
- 升级后未重新做检索效果评测,只确认接口正常召回、bge-m3/Ollama 配置保留。

## 相关

- [[claude-mem-安装部署]]
- [[claude-mem-调教清单]]
- [[claude-mem-存储与读取机制]]
