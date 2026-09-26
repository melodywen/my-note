---
type: reference
status: done
area: growth
tags: [learning, dsh, 插件包, 桌面版, patch, peerDependencies, esbuild, 实战, 有出处]
created: 2026-09-26
updated: 2026-09-26
---

# 04 从 --patch 到插件包——让 dsh-learn 插件走进桌面版

> **一句话**：dsh 插件有两种形态——「patch 改装件」和「认证配件包」。本文记录把 dsh-learn 的两个插件（codebuddy-llm-v2 + codebuddy-web-search）从前者改造成后者的完整过程，踩过的坑、源码依据、最终模板。

## 1 背景：为什么 --patch 走不进桌面版

### 1.1 --patch 是什么

`dsh web --patch <file.yml>` 在启动时叠一层 cordis 配置覆盖，插件入口写绝对路径：

```yaml
# cordis.patch.yml（patch 形态）
- insert:
    - id: codebuddy-llm-v2
      name: '/Users/me/.../codebuddy-llm-v2/codebuddy-llm.ts'
```

loader 按绝对路径加载 `.ts` 文件，Node 的 type stripping 直接跑 TypeScript——不需要编译，不需要 node_modules，开发体验最轻。

### 1.2 桌面版的三道墙

桌面版（Electron，`apps/desktop`）有独立的 `desktop` profile，CLI 对它无管理权（`apps/cli/src/args.ts:69`）：

```typescript
if (profile.toLowerCase() === 'desktop')
  program.error('error: profile "desktop" is managed exclusively by the Electron application')
```

插件通过桌面版的插件管理器 UI 安装，走 pnpm + 严格校验（`apps/desktop/src/project-manager.ts`）。三道墙：

| 墙 | 源码依据 | 含义 |
|---|---|---|
| **必须声明 `dsh.bundle.patch`** | `project-manager.ts:212`：`typeof patch !== 'string' → does not declare dsh.bundle.patch` | package.json 没有 `dsh.bundle` → 当普通依赖拒收 |
| **禁止 symlink** | `profile-packages.ts:228`：`linked private package` / `profile-packages.ts:210`：`linked package container` | node_modules 里的 symlink 全部报错 |
| **宿主包只能 peerDependencies** | `profile-packages.ts:244`：`must declare ${name} as a peer dependency` | `@deepseek-ai/*` 声明成 dependencies → 报错 |

> **Go 类比**：--patch 像手动改线路的改装件；插件包像贴了认证标签、从整机仓库领标准件、不私拉电线的认证配件。

### 1.3 报错现场

桌面版插件管理器 → 添加本地插件目录 → 填插件路径：

> ❌ **codebuddy-llm-v2 declares no dsh.bundle**（这个包没有声明组合包，无法作为插件安装）

原因：package.json 只有 `name/version/type/private/description`，没有 `dsh` 字段。

## 2 改造清单

两个插件改法对称，以 codebuddy-llm-v2 为主例。

### 2.1 package.json：加四个声明

改造前（patch 形态）：

```json
{
  "name": "codebuddy-llm-v2",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "..."
}
```

改造后（插件包形态）：

```json
{
  "name": "@melodycchen/dsh-llm-codebuddy",
  "version": "0.1.0",
  "type": "module",
  "description": "...",
  "license": "MIT",
  "exports": {
    ".": "./dist/codebuddy-llm.js",
    "./cordis.patch.yml": "./cordis.patch.yml",
    "./package.json": "./package.json"
  },
  "scripts": {
    "build": "esbuild codebuddy-llm.ts --bundle --platform=node --format=esm --outfile=dist/codebuddy-llm.js --external:@deepseek-ai/* --external:node:*"
  },
  "dsh": {
    "bundle": {
      "patch": "./cordis.patch.yml"
    }
  },
  "peerDependencies": {
    "@deepseek-ai/cordis": ">=0.1.0",
    "@deepseek-ai/dsh-llm": ">=0.1.0",
    "@deepseek-ai/dsh-attachment": ">=0.1.0",
    "@deepseek-ai/schemastery": ">=0.1.0"
  },
  "devDependencies": {
    "esbuild": "^0.28.0"
  }
}
```

逐项说明：

| 字段 | 作用 | 出处 |
|---|---|---|
| `name` 改 scoped | 合法 npm 包名，loader 用它从 profile node_modules 解析入口 | `project-manager.ts:118` `assertPackageName` |
| `exports["."]` 指向 `.js` | Node 24 禁止 `node_modules/` 下直接跑 `.ts`（`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`） | Node.js 24 ESM type stripping 限制 |
| `scripts.build` | esbuild 打包命令，`npm run build` 一键编译 | — |
| `dsh.bundle.patch` | **判定插件身份的唯一标签**，指向 cordis patch 文件 | `plugin.ts:44`：`manifest.dsh?.bundle?.patch !== undefined` |
| `peerDependencies` | 声明用到的宿主包；profile 的 host links 会提供全部 282 个 `@deepseek-ai/*` 包 | `profile-packages.ts:244`：dependencies 里的宿主包会报错 |
| `devDependencies` | esbuild 构建工具 | — |
| 去掉 `private` | `private: true` 的包 pnpm 不接受安装 | npm 规范 |

### 2.2 cordis.patch.yml：入口从路径改包名

改造前：

```yaml
- insert:
    - id: codebuddy-llm-v2
      name: '/Users/me/.../codebuddy-llm-v2/codebuddy-llm.ts'
```

改造后：

```yaml
- insert:
    - id: codebuddy-llm-v2
      name: '@melodycchen/dsh-llm-codebuddy'
```

loader 不再按绝对路径找文件，而是从 profile 的 `node_modules` 解析包名 → 读 `package.json` 的 `exports["."]` → 加载 `dist/codebuddy-llm.js`。

> 社区标杆 modlens 的 patch 就是这种写法：`name: '@liustack/modlens'`。

### 2.3 删除 node_modules symlink

原来插件目录有 `node_modules/@deepseek-ai/*` 符号链接指向全局 dsh 包，让 `import` 能解析到宿主包。

改造后**必须删**——桌面版校验器 `validateDesktopPluginGraph`（`profile-packages.ts:228`）明确禁止 `linked private package`。profile 的 host links 会提供全部宿主包，peerDependencies 声明即可。

### 2.4 编译 .ts → .js（esbuild bundle）

```bash
npx esbuild codebuddy-llm.ts --bundle --platform=node --format=esm \
  --outfile=dist/codebuddy-llm.js \
  --external:@deepseek-ai/* --external:node:*
```

- `--bundle`：把 `provider.ts` / `types.ts` 等本地 .ts 文件全部打进一个 .js
- `--external:@deepseek-ai/*`：宿主包不打包，运行时从 profile node_modules 解析
- `--external:node:*`：Node 内置模块不打包
- 产物 ~29KB（llm-v2）/ ~7KB（web-search）

> **为什么必须编译？** Node 24 的 type stripping（`--experimental-strip-types` 默认开启）在 `node_modules/` 目录下被禁用，只允许项目根目录的 .ts 直跑。插件复制进 profile 的 node_modules 后，.ts 入口直接报 `ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`。

### 2.5 代码层面：去掉 --patch 时代的 workaround

codebuddy-llm-v2 原来有一个 `loadHostSchemastery()` 函数——因为 --patch 模式下插件目录无 node_modules，解析不到 `@deepseek-ai/schemastery`，只能从 `process.argv[1]`（CLI 入口）用 `createRequire` 反向解析宿主安装树。

改造后直接 `import Schema from '@deepseek-ai/schemastery'`——peerDependencies 从 profile 解析，干净利落。

## 3 安装与启动

### 3.1 CLI（web profile）

```bash
# 安装（file: spec 让 pnpm 复制进 profile，不是 symlink）
dsh plugin --profile web add file:/path/to/plugins/codebuddy-llm-v2
dsh plugin --profile web add file:/path/to/plugins/codebuddy-web-search

# 启动（不再需要 --patch）
dsh web
```

安装后 profile 的 `package.json` 里 `dsh.profile.bundles` 自动追加：

```json
"bundles": [
  "@deepseek-ai/dsh-base",
  "@deepseek-ai/dsh-web-app",
  "@melodycchen/dsh-llm-codebuddy",
  "@melodycchen/dsh-web-search-codebuddy"
]
```

### 3.2 桌面版

插件管理器 → 添加本地插件目录 → 填插件路径 → 安装。

桌面版用自带的 pnpm + Node 运行时安装，复制进 `~/.dsh/profiles/desktop/node_modules/`。

> ⚠️ **首次安装本地插件后必须重启 App**
>
> 桌面版在运行进程中缓存了插件的导入结果。首次安装本地插件后，旧进程仍持有失败的导入状态，插件管理器里会显示 "failed to import"。**完全退出 App（Cmd+Q）再重新打开**，新进程会重新加载 profile，插件才能正常激活。
>
> 这个现象容易误判为插件本身的问题（因为另一个同样条件的插件可能恰好成功了），实际原因只是进程级缓存——重启即解。

### 3.3 start.sh 自动化

```bash
# 构建插件（检测 .ts 比 .js 新时自动编译）
build_plugins

# 确保插件已安装到 profile（首次或切 profile 时自动安装）
ensure_plugins

# 启动（不再需要 --patch）
dsh web
```

## 4 踩坑记录

### 4.1 `link:` vs `file:` —— 一字之差

| pnpm spec | 行为 | 能否解析宿主包 |
|---|---|---|
| `add /path/to/plugin`（裸目录） | `link:` symlink → 源目录 | ❌ Node ESM resolver 从 symlink 真实路径出发找 node_modules，源目录没有 → `Cannot find package` |
| `add file:/path/to/plugin` | 复制进 profile node_modules | ✅ 从 profile node_modules 树解析 → host links 提供 `@deepseek-ai/*` |

**结论**：本地目录安装必须用 `file:` 前缀，不能用裸目录路径。

### 4.2 Node 24 禁止 node_modules 下跑 .ts

```
Error [ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING]:
  Stripping types is currently unsupported for files under node_modules
```

`--patch` 模式时插件入口在源码目录（不在 node_modules 里），.ts 直跑没问题。`file:` 复制进 profile 的 node_modules 后，Node 24 拒绝 type stripping。

**解法**：esbuild 编译成 .js，`exports` 指向 `.js` 入口。

### 4.4 桌面版首次安装插件后需重启 App

插件通过桌面版插件管理器安装后，`package.json` 和 `node_modules/` 都已就位，但插件状态可能显示 "failed to import"。

**根因**：桌面版 Electron 主进程在运行时缓存了插件导入结果。安装新插件后旧进程不会自动重新加载 profile，仍持有安装前的失败状态。

**解法**：完全退出 App（Cmd+Q 杀掉所有 DeepSeek Harness 进程）→ 重新打开 → 新进程重新加载 profile → 插件正常激活。

> 这个坑很隐蔽——同一个 profile 下另一个插件可能恰好能激活，容易让人怀疑是插件代码差异。实际只是进程级缓存的时序问题：先安装的插件在进程启动时就导入了，后安装的插件命中了旧缓存。重启后大一统。

### 4.5 桌面版 vs CLI 的版本漂移

| | dsh 版本 | Node 版本 |
|---|---|---|
| 全局 CLI | 0.1.5-rc.1 | v24.14.0 |
| 桌面版 App | 0.1.7-rc.2 | v24.21.0 |

`LlmAdapter` 抽象面（`stream`/`prepareCall`/`listModels`）两版一致，但细粒度类型（`GenerateOptions` 等）可能有漂移。装上跑一个会话才知道，别假设零风险。

### 4.6 改代码后需要重装吗？

| 场景 | CLI（`file:` 复制） | 桌面版 |
|---|---|---|
| 改 .ts 逻辑代码 | `npm run build` → `dsh plugin --profile web add file:...`（重装刷新副本） | 桌面端「移除→重装」 |
| 改 package.json 依赖 | 同上 | 同上 |
| start.sh | 自动检测 .ts 比 .js 新 → 自动 build → 但不会自动重装（已装则跳过） | 手动 |

> **改进方向**：start.sh 的 `ensure_plugins` 目前只检测是否已装，不检测 dist.js 是否过期。如果改了代码但忘了重装，profile 里的副本是旧的。后续可以加 `--force` 逻辑或检测 dist.js 时间戳。

## 5 插件包形态模板

改造后的插件目录结构：

```
my-plugin/
├── package.json          # dsh.bundle.patch + exports + peerDeps + scripts.build
├── cordis.patch.yml      # name 用包名，不用绝对路径
├── index.ts              # 插件入口（源码）
├── provider.ts           # 业务逻辑（源码）
├── types.ts              # 类型定义（源码）
├── dist/
│   └── index.js          # esbuild 产物（gitignore）
└── .gitignore            # dist/ + .codebuddy-auth.json
```

package.json 最小模板：

```json
{
  "name": "@scope/dsh-plugin-name",
  "version": "0.1.0",
  "type": "module",
  "license": "MIT",
  "exports": {
    ".": "./dist/index.js",
    "./cordis.patch.yml": "./cordis.patch.yml",
    "./package.json": "./package.json"
  },
  "scripts": {
    "build": "esbuild index.ts --bundle --platform=node --format=esm --outfile=dist/index.js --external:@deepseek-ai/* --external:node:*"
  },
  "dsh": {
    "bundle": { "patch": "./cordis.patch.yml" }
  },
  "peerDependencies": {
    "@deepseek-ai/cordis": ">=0.1.0"
  },
  "devDependencies": {
    "esbuild": "^0.28.0"
  }
}
```

cordis.patch.yml 最小模板：

```yaml
- insert:
    - id: my-plugin
      name: '@scope/dsh-plugin-name'
```

## 6 关键源码索引

| 文件 | 行 | 作用 |
|---|---|---|
| `apps/cli/src/plugin.ts` | 44 | `manifest.dsh?.bundle?.patch !== undefined` — 判定插件身份 |
| `apps/desktop/src/project-manager.ts` | 212 | 桌面版同款校验：`does not declare dsh.bundle.patch` |
| `apps/desktop/src/project-manager.ts` | 162-164 | `plugin dependencies must use exact registry versions` |
| `apps/desktop/src/profile-packages.ts` | 228 | `linked private package` — 禁止 symlink |
| `apps/desktop/src/profile-packages.ts` | 244 | `must declare ${name} as a peer dependency` — 宿主包只能 peer |
| `apps/desktop/src/paths.ts` | 31 | `profile: join(dshHome, 'profiles', 'desktop')` — 桌面 profile 路径 |
| `apps/cli/src/args.ts` | 69 | CLI 拒绝 `--profile desktop` |
| `packages/bundle/base/package.json` | — | 官方 bundle 的 `dsh.bundle.patch` 声明标杆 |

## 7 相关笔记

- [[02 modlens 视觉插件——为什么 dsh-learn 不需要它]] — modlens 的 `dsh.bundle` 声明是本文改造的参照模板
- [[03 创造模式（cordis preset）——内置的"造 Agent 的 Agent"全拆解]] — 创造模式本身就是一个插件包（cordis preset），用同样的声明机制
- [[00 社区插件全景——4312 个插件、23 个分类]] — 社区插件都是插件包形态
