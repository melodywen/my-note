---
type: project
status: discussing
area: dsh-plugin-dev
tags: [project, dsh, 知识库插件, security, 有出处]
created: 2026-09-27
updated: 2026-09-27
---

# 10 安全与权限——Scope 硬边界与只读 Git

> [!info] 文档状态
> - 状态：**v1**（2026-09-27，scope 硬边界 + 只读方向已裁定）
> - 前置：[[03 运行时机制——skill载体、job执行与Git集成]]、[[09 Agent工具面——六个原生工具与权限分级]]
> - dsh 三层防线（沙箱→权限预设→审批）的逐层落位，见本仓库笔记 wiki 05

## 一、最高原则：Scope 硬边界（2026-09-27 学习者裁定）

> **原话要义**：「查知识库首先要选中某一个知识库。选中后它有对应的仓库地址链接、对应的前缀路径——**你只能在这个范围里面，不能脱离这个范围**。」

**一切操作以「当前选中的知识库」为边界**：

```
选中知识库 = (repo URL, subpath) 双前缀
                │
                ├── knowledge_base_read(path)     → path 必须落在该库 vault 内
                ├── knowledge_base_search(scope)  → scope 就是库 id，默认只在选中库内搜
                ├── git 操作          → 只对该库登记簿里的仓库
                └── 追史/索引         → 只写该库自己的 vault 和 .db
```

**实现纪律**：

1. **路径双重锚定**：vault 内相对路径（`realpath` 解析符号链接后必须在 vault 根内）+ 仓库侧操作限定在绑定的 subpath 前缀内（越出子路径的文件不在追史范围）
2. **跨库检索是显式动作**：默认当前库；搜全部库要明确指定 scope（不是默认行为）
3. **选库本身是一道安全动作**：面板/工具层「选中」即建立了会话的 scope 上下文，后续操作全部继承

## 二、第二原则：Git 只读方向（同裁定）

> **原话要义**：「只能往 master 方面拉取（fetch/更新），**不允许回滚、不允许删仓库**，其他你自己看着办。」

**允许的 git 操作（白名单制）**：

| 命令 | 用途 |
|---|---|
| `git fetch` | 拉最新（追史增量检测） |
| `git log / show / diff` | 读历史与对象（史料的唯一来源） |
| `git ls-remote` | 建库校验（URL 可达性检查） |

**明确禁止**（黑名单即白名单的补集——非白名单一律拒）：

- `push / commit / reset / rebase / revert / checkout`(写) / `clean` / `rm` —— **对源仓库零写入**
- `clone --mirror` 之外的任何**删除**（`rm -rf` 仓库目录只允许出现在「用户显式解绑知识库」且经确认的流程里，且只删**自己的 clone**，不碰源）
- rebase / force push 检测到时：游标走 patch-id 兜底（02 篇 F 决议），**绝不「帮用户」做任何历史修正**

## 三、六个攻击面与防御（AI 提案，学习者已默认①④方向）

| # | 攻击面 | 防御 |
|---|---|---|
| ① | **路径逃逸**（knowledge_base_read 读 vault 外） | Scope 硬边界（第一节）；argv 分离、拒绝绝对路径、realpath+前缀校验 |
| ② | **命令注入**（git 参数） | `spawn` 数组传参绝不拼 shell；URL schema 白名单（https/git@；内网 http 见待议） |
| ③ | **凭证**（私有仓库） | 复用 dsh credentials 子系统（`.credentials.yaml`，secret 不进响应）；**token 绝不落 vault/索引/frontmatter**；git credential helper 注入 |
| ④ | **恶意的 .gitattributes filter / hooks**（clone 即 RCE） | `--no-checkout`（追史只要 git 对象，工作区文件不落地）+ `core.hooksPath=/dev/null` + 禁 filter driver |
| ⑤ | **提示词注入**（knowledge_base_submit 的内容藏指令） | 审阅闭环=人眼防线；vault 内容只作材料进上下文，工具调用权留在代码驱动主控（03 篇）；⚠️ 显式 source 标记（待议） |
| ⑥ | **索引/游标完整性** | 索引可重建（08）；游标可从已归档 frontmatter 推导（02-F）——非单点 |

## 四、dsh 三层防线的落位

| 层 | 本插件的做法 |
|---|---|
| **沙箱（最小执行面）** | git 只读白名单 + `--no-checkout` + 禁 hooks/filters |
| **权限预设** | Scope 硬边界（路径双锚定）+ argv 分离 + URL 白名单 + credentials 子系统 |
| **审批** | **审阅闭环 = 业务级审批**（归档人批准才进正式区）+ `knowledge_base_adopt` 面板专属（09） |

**Go 类比**：库层（git/路径）只管边界不管语义，业务层（审阅）管语义——防御纵深 + 审计分离。

## 五、待议清单

1. 内网 http:// git：默认拒绝 + 可配置放开，还是默认允许？（AI 倾向：默认拒，`allowInsecureGit: true` 配置项）
2. ⑤ 的 source 显式标记：做不做（返回内容带 `source: vault` 元数据）
3. `ls-remote` 建库校验的凭证探测（建库时试连需要 token？用哪个 credential helper）
4. 解绑知识库的删除流程：二次确认的形式（输入库名？）
