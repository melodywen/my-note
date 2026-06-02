---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, 安装, modelscope]
created: 2026-06-01
updated: 2026-06-01
---

# 02 ms-SWIFT 安装部署

> 本页是**实战演练篇**:把 [[04 ms-SWIFT|ms-SWIFT]] 装到本地/服务器,为后续微调做准备。一句话记住:**最简单一行 `pip install ms-swift` 就能用;真要跑全流程,加装对应 extras 或直接用官方 Docker 镜像最省心。**

## 安装前:先确认基础环境

ms-SWIFT 是建立在 PyTorch 生态上的框架,装它之前先备好底座:

| 依赖 | 要求 | 说明 |
|---|---|---|
| **操作系统** | Linux(推荐)/ Windows WSL / macOS | 生产环境基本都是 Linux |
| **Python** | 3.10 ~ 3.11 | 太新太旧都可能踩坑 |
| **CUDA** | 12.x(用 NVIDIA 卡时) | 对应显卡驱动要装好 |
| **PyTorch** | 2.9 / 2.10(较新版本) | 框架核心底座 |
| **GPU** | NVIDIA A10/A100/H100、RTX 20/30/40 系等 | 也支持昇腾 NPU、Apple MPS、CPU |

> [!key-insight] 强烈建议用 conda 建独立环境
> 微调框架的依赖链很复杂(torch / transformers / peft / accelerate / vllm 互相有版本约束),**别直接装到系统 Python 里**。先建一个干净环境再装,出问题能随时删掉重来:
> ```bash
> conda create -n swift python=3.11 -y
> conda activate swift
> ```

> [!key-insight] torch 和 transformers 是什么关系?
> 上面依赖表里同时出现了 `torch` 和 `transformers`,它们**不是竞争关系,而是上下游依赖**:
>
> | 维度 | **torch (PyTorch)** | **transformers (Hugging Face)** |
> |---|---|---|
> | 定位 | 底层深度学习框架(Meta 出品) | 建立在 torch 之上的**上层库** |
> | 提供什么 | 张量计算、自动求导、GPU 加速、`nn` 基础组件 | 开箱即用的**预训练模型**(BERT/GPT/Qwen 等)+ 分词器 + pipeline |
> | 类比 | 造车的"零件和工具"(发动机、螺丝刀) | 已经造好的"整车",直接开走 |
> | 你拿它做什么 | 从零搭网络、写训练循环、自定义层 | 几行代码加载现成大模型做推理/微调 |
> | 依赖关系 | 独立 | **依赖 torch**(默认后端) |
>
> 一句话:**transformers 跑在 torch 之上**。`pip install transformers` 时底层调用的就是 PyTorch。而 ms-SWIFT 又是更上一层 —— 它封装了 transformers + peft + accelerate,把"微调全流程"也帮你打包好了。三者层级:**torch(底座) → transformers(预训练模型) → ms-SWIFT(微调全家桶)**。

## 官方推荐的完整依赖版本

上面是**底座层**的最低要求,下面这张是 ms-SWIFT 官方给出的**完整运行环境**(含训练/推理/部署/评测全链路依赖)。装 `[all]` 时这些会被一并拉进来,版本对不上时可对照此表手动锁版本:

| 依赖               | 范围            | 推荐              | 备注                                 |
| ---------------- | ------------- | --------------- | ---------------------------------- |
| **python**       | >=3.9         | 3.10 / 3.11     |                                    |
| **cuda**         |               | cuda12          | 使用 cpu / npu / mps 则无需安装           |
| **torch**        | >=2.0         | 2.8.0           | 框架底座                               |
| **transformers** | >=4.33        | 4.57.3          | 预训练模型                              |
| **modelscope**   | >=1.23        |                 | 魔搭模型/数据集下载                         |
| **peft**         | >=0.11, <0.19 |                 | LoRA 等高效微调                         |
| **flash_attn**   |               | 2.8.3 / 3.0.0b1 | 加速注意力计算                            |
| **trl**          | >=0.15, <0.25 | 0.24.0          | RLHF                               |
| **deepspeed**    | >=0.14        | 0.17.6          | 训练                                 |
| **vllm**         | >=0.5.1       | 0.11.0          | 推理 / 部署                            |
| **sglang**       | >=0.4.6       | 0.5.5.post3     | 推理 / 部署                            |
| **lmdeploy**     | >=0.5         | 0.10.1          | 推理 / 部署                            |
| **evalscope**    | >=1.0         |                 | 评测(配合 [[01 EvalScope\|EvalScope]]) |
| **gradio**       |               | 5.32.1          | Web-UI / App                       |

### 按推荐版本安装的命令

> 多数情况直接 `pip install 'ms-swift[all]'` 即可,无需手动指定版本。**只有当某个依赖版本对不上、需要锁死时**,才照下面命令逐个钉版本。

**conda 装的部分(python / cuda / torch):**

```bash
# python:建环境时指定
conda create -n swift python=3.11 -y && conda activate swift

# torch:务必按 CUDA 版本选命令(见下方对照表)
pip install torch==2.8.0
```

> [!key-insight] torch 一定要按 CUDA 版本装(来自 [PyTorch 官方安装页](https://pytorch.org/get-started/locally/))
> PyTorch 官网的安装器([pytorch.org/get-started/locally](https://pytorch.org/get-started/locally/))让你依次选 **PyTorch 版本 / 系统 / 包管理器 / 语言 / 计算平台(CUDA)**,然后生成对应命令。**核心是 `Compute Platform` 那一行 —— torch 必须和机器的 CUDA 版本对上**,否则装了也用不了 GPU。
>
> 不同 CUDA 平台对应的 pip 安装命令(通过 `--index-url` 指定对应 wheel 源):
>
> | 计算平台 | pip 安装命令 |
> |---|---|
> | **CUDA 12.6** | `pip install torch --index-url https://download.pytorch.org/whl/cu126` |
> | **CUDA 12.8** | `pip install torch --index-url https://download.pytorch.org/whl/cu128` |
> | **CUDA 13.0** | `pip install torch --index-url https://download.pytorch.org/whl/cu130` |
> | **ROCm(AMD 卡)** | `pip install torch --index-url https://download.pytorch.org/whl/rocm6.2` |
> | **CPU(无显卡 / Mac)** | `pip install torch`(默认即 CPU 版,Mac 自动带 MPS) |
>
> - `cu126` / `cu128` / `cu130` 末尾数字就是 CUDA 版本(12.6 / 12.8 / 13.0),**和你 `nvidia-smi` 看到的 CUDA 版本匹配即可**(向下兼容,可略低)。
> - 要钉 torch 版本就拼上去,如 `pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cu128`。
> - 不确定该选哪个?直接去官网选择器点一遍,它会实时生成最准的命令。

**pip 锁版本安装各依赖:**

```bash
pip install transformers==4.57.3      # 预训练模型
pip install modelscope                # 魔搭下载(>=1.23,无指定推荐版,装最新即可)
pip install peft                      # LoRA 微调(范围 >=0.11,<0.19)
pip install flash-attn==2.8.3         # 加速注意力(需编译,装不上可先跳过)
									  # flash-attn 的 CUDA kernel 需要 nvcc 编译，且只支持 NVIDIA 显卡。Mac 上根本无法安装，不是版本问题，是硬件/平台不兼容。
pip install trl==0.24.0               # RLHF
pip install deepspeed==0.17.6         # 分布式训练
pip install vllm==0.11.0              # 推理 / 部署
pip install sglang==0.5.5.post3       # 推理 / 部署
									  #   - sglang 是 NVIDIA GPU 推理引擎，和 vLLM 一样，只支持 Linux + CUDA。
pip install lmdeploy==0.10.1          # 推理 / 部署

pip install evalscope                 # 评测(>=1.0,装最新即可)
pip install gradio==5.32.1            # Web-UI / App
```

> [!key-insight] 几个安装注意点
> - **`modelscope` / `peft` / `evalscope`** 表里没给推荐具体版本,按范围装最新稳定版即可,不用钉死。
> - **`flash-attn`** 包名带连字符(`flash-attn`),且需要编译 CUDA 扩展,环境不全时容易装失败 —— 装不上可先跳过,它只是"加速"不是"必需"。
> - **`vllm` / `sglang` / `lmdeploy`** 是三选一的推理引擎,**用哪个装哪个**,不必三个都装。
> - 一行批量锁版本(可选):`pip install transformers==4.57.3 trl==0.24.0 deepspeed==0.17.6 gradio==5.32.1`

> [!key-insight] 不用一次全记住
> 这张表里**真正的硬依赖只有前几行**(python / cuda / torch / transformers / peft);后面 `vllm / sglang / lmdeploy` 是推理部署、`deepspeed / trl` 是训练、`evalscope / gradio` 是评测和界面 —— **用到哪块再关注哪块的版本**。这也正是前面 `pip install 'ms-swift[all]'` 帮你做的事:按需把这些依赖一次性装齐。

## 方式一:pip 安装(最常用)

最简单的安装,一行搞定:

```bash
pip install ms-swift
```

如果要用**特定功能**,装对应的 extras(额外依赖包):

| 命令                             | 用途                                   |
| ------------------------------ | ------------------------------------ |
| `pip install ms-swift`         | 基础安装                                 |
| `pip install 'ms-swift[llm]'`  | LLM 相关功能                             |
| `pip install 'ms-swift[eval]'` | 评测功能(配合 [[01 EvalScope\|EvalScope]]) |
| `pip install 'ms-swift[all]'`  | **全功能**(图省事直接装这个)                    |

> [!key-insight] extras 里的 `[...]` 是什么
> `ms-swift[all]` 中括号里的就是"可选依赖组"。基础包只装核心,**用到哪个能力(LLM / 评测 / 全量)就装哪个组**,把对应的额外依赖一并拉进来。不确定就 `[all]`,省得缺包。

## 方式二:源码安装(想改代码/用最新特性)

想跟最新主分支、或要改源码调试,用源码安装:

```bash
git clone https://github.com/modelscope/ms-swift.git
cd ms-swift
pip install -e .
```

> `pip install -e .` 里的 `-e` 是 **editable(可编辑)模式** —— 装的是源码目录本身,你改了源码立即生效,不用重装。适合开发/调试。

## 方式三:Docker 镜像(最省心,环境一把梭)

最怕踩"装了半天依赖还跑不起来"的坑,**官方 Docker 镜像把 CUDA / torch / vLLM / ms-swift 全打包好了**,拉下来就能用:

```bash
# 以 swift 4.0.2 镜像为例(含 cuda12.8 + torch2.10 + vllm0.17)
docker pull modelscope-registry.cn-hangzhou.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda12.8.1-py311-torch2.10.0-vllm0.17.1-modelscope1.34.0-swift4.0.2
```

> [!key-insight] 三种方式怎么选
> | 你是谁 | 推荐方式 |
> |---|---|
> | 只想快速用框架训模型 | **pip install ms-swift[all]** |
> | 要改源码/追最新特性 | **源码 `pip install -e .`** |
> | 环境老踩坑 / 要在干净机器一键起 | **Docker 镜像** |
> 镜像名里 `cuda12.8 / torch2.10 / vllm0.17 / swift4.0.2` 这串,就是把整套版本锁死打包 —— 这正是 Docker"环境即代码、避免版本地狱"的价值。

## 验证安装

装完跑一下 CLI,能打印出帮助/版本就说明 OK:

```bash
swift --help
```

ms-SWIFT 的命令是 `swift xxx` 的形式(对应 [[04 ms-SWIFT|ms-SWIFT 全流程]]):`swift sft`(微调)、`swift infer`(推理)、`swift eval`(评测)、`swift export`(量化导出)、`swift deploy`(部署)。

## 官方安装文档摘要

> 来源:[ModelScope 官方文档 · SWIFT 安装](https://modelscope.cn/docs/llm-training-and-inference/intro/swift-installation)。上面的速记已够日常用,这节把**官方原文**的几个补充点收录下来,便于对照最新版本。

### pip 安装(官方推荐加 `-U` 升级)

```bash
pip install 'ms-swift' -U              # 基础安装并升级到最新
pip install 'ms-swift[megatron]' -U    # Megatron 相关依赖
pip install 'ms-swift[eval]' -U        # 评测依赖
pip install 'ms-swift[all]' -U         # 全功能
```

> [!key-insight] 用 uv 装更快(官方推荐)
> `uv` 是新一代 Python 包管理器,解析依赖比 pip 快很多,`--torch-backend=auto` 会自动匹配 CUDA 版本:
> ```bash
> pip install uv
> uv pip install 'ms-swift' --torch-backend=auto
> ```

### 源码安装(区分 4.x / 3.x 分支)

```bash
# Swift 4.x(主分支,最新)
git clone https://github.com/modelscope/ms-swift.git
cd ms-swift
pip install -e .            # 全功能用 pip install -e '.[all]'

# Swift 3.x(稳定发布分支 release/3.12)
git clone -b release/3.12 https://github.com/modelscope/ms-swift.git
cd ms-swift
pip install -e .
```

> 也可不 clone 直接装:`pip install "ms-swift[all]@git+https://github.com/modelscope/ms-swift.git"`。**追新特性用 4.x 主分支,求稳定用 3.x release 分支。**

### 最新 Docker 镜像(官方多版本)

官方按 swift 版本提供镜像,且有 **杭州 / 北京 / 美西** 三地仓库(`cn-hangzhou` / `cn-beijing` / `us-west-1`),按地域选最近的拉取更快:

```bash
# swift 4.2.3(最新:cuda13.0 + torch2.11 + vllm0.21 + py312)
docker pull modelscope-registry.cn-hangzhou.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda13.0.3-py312-torch2.11.0-vllm0.21.0-modelscope1.36.3-swift4.2.3

# swift 4.1.3(cuda12.9 + torch2.10 + vllm0.19)
docker pull modelscope-registry.cn-hangzhou.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda12.9.1-py312-torch2.10.0-vllm0.19.1-modelscope1.35.4-swift4.1.3

# swift 3.12.5(3.x 稳定线:torch2.9 + vllm0.13)
docker pull modelscope-registry.cn-hangzhou.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda12.8.1-py311-torch2.9.0-vllm0.13.0-modelscope1.33.0-swift3.12.5
```

### 官方依赖表(比前文截图更新)

官方最新依赖要求与前文 Notion 截图略有出入,以官方为准:

| 依赖 | 范围 | 推荐 | 备注 |
|---|---|---|---|
| **python** | >=3.10 | 3.12 | 注意最低已是 3.10 |
| **cuda** | — | cuda12.8 / 13.0 | cpu / npu / mps 无需 |
| **torch** | >=2.0 | 2.8.0 / 2.11.0 | |
| **transformers** | >=4.33 | 4.57.6 / 5.8.1 | |
| **modelscope** | >=1.23 | — | |
| **datasets** | >=3.0, <4.8.5 | 3.6.0 / 4.8.4 | 数据集处理 |
| **peft** | >=0.11, <0.20 | — | |
| **flash_attn** | — | 2.8.3 / 4.0.0b15 | |
| **trl** | >=0.15, <1.0 | 0.29.1 | RLHF |
| **deepspeed** | >=0.14 | 0.18.9 | 训练 |
| **vllm** | >=0.5.1 | 0.11.0 / 0.21.0 | 推理 / 部署 |
| **sglang** | >=0.4.6 | — | 推理 / 部署 |
| **evalscope** | >=1.0 | — | 评测 |
| **gradio** | — | 5.32.1 | Web-UI / App |

### 支持的硬件

| 硬件 | 备注 |
|---|---|
| A10 / A100 / H100 | 主力训练卡 |
| RTX 20 / 30 / 40 系 | 消费级可用 |
| T4 / V100 | 部分模型可能出现 NAN |
| 昇腾 NPU | 部分模型可能 NAN 或算子不支持 |
| MPS(Apple) | 参考官方 issue 4572 |
| CPU | 可跑但慢 |

> [!key-insight] 没卡也能练手:免费 GPU Notebook
> 没有本地显卡时,可用魔搭官方的免费 GPU:登录 [ModelScope](https://www.modelscope.cn) → 左侧 **我的 Notebook** → 启动免费实例(提供 A10 GPU)。环境已预装,适合跟着实战篇做实验。

## 继续学习

- [[04 ms-SWIFT|ms-SWIFT(魔搭生态全家桶)]](装好之后,看它能干什么)
- [[01 Qwen3 高效微调环境准备|Qwen3 高效微调环境准备]](实战环境四件套总览)
- [[06 微调所需软硬件环境|微调所需软硬件环境]](装框架前先确认显卡显存够不够)
