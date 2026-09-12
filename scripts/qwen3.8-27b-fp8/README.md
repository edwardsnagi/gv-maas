# gv-maas Scripts 配置清单

SGLang MaaS 部署脚本索引。修改路径或默认值时，优先改本文档对应章节，再同步脚本内变量。

---

## 目录结构

| 路径 | 用途 |
|------|------|
| `scripts/qwen3.8-27b-fp8/README.md` | 本配置清单 |
| `scripts/qwen3.8-27b-fp8/lib/interactive.sh` | 终端交互 UI |
| `scripts/qwen3.8-27b-fp8/sglang-install` | SGLang 环境一键安装 |
| `scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8` | Qwen3.8-27B-FP8 推理服务启动 |

---

## 硬件与环境前提

| 项目 | 当前环境 | 说明 |
|------|----------|------|
| GPU | 4 × NVIDIA RTX 4090 (48 GB) | 单卡可跑 Qwen3.8-27B-FP8 |
| 驱动 CUDA | 12.4 (max) | 必须使用 **cu129** 轮子，不能用 cu130 |
| Python | 3.10+ | venv 位于 `/data/edwardluke/venvs/sglang` |
| 磁盘 | 权重在 `/data`，缓存/venv 在 `/data/edwardluke` | 避免根分区 `/` 写满 |

---

## 路径默认值

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DATA_ROOT` | `/data/edwardluke` | venv、缓存根目录 |
| `VENV_DIR` | `${DATA_ROOT}/venvs/sglang` | SGLang 虚拟环境 |
| `SGLANG_CACHE_DIR` | `${DATA_ROOT}/cache/sglang` | JIT / CUDA graph 编译缓存 |
| `UV_CACHE_DIR` | `${DATA_ROOT}/cache/uv` | uv 包缓存 |
| `TMPDIR` | `${DATA_ROOT}/cache/tmp` | 安装临时目录 |
| `MODEL_PATH` | `/data/models/Qwen3.8-27B-FP8` | 主 LLM 权重 |
| `LOG_FILE` | `${SGLANG_CACHE_DIR}/sglang-server.log` | 服务日志 |
| `PID_FILE` | `${SGLANG_CACHE_DIR}/sglang-server.pid` | 后台 PID |

首次使用前需确保目录归属正确：

```bash
sudo mkdir -p /data/edwardluke/{venvs,cache/uv,cache/pip,cache/tmp,cache/sglang}
sudo chown -R $USER:$USER /data/edwardluke
```

---

## 安装配置 (`sglang-install`)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SGLANG_VERSION` | `0.5.19` | 稳定版，避免 GitHub nightly |
| `USE_CN_MIRROR` | `1` | 清华 PyPI + PyTorch 镜像 |
| `CUDA_MAJOR` | 自动检测 | 驱动 < CUDA 13 时强制 cu129 栈 |
| `FORCE` | — | `FORCE=1` 重建 venv |

安装后关键包：

- `torch 2.13.0+cu129`
- `sglang 0.5.19`
- `sglang-kernel +cu129`（必须从 `docs.sglang.ai/whl/cu129/` 单独装）
- 自动 patch flashinfer（兼容系统 nvcc 12.4）
- 自动移除 `sgl-deep-gemm` / `torchcodec` 等 cu130 可选包

```bash
./scripts/qwen3.8-27b-fp8/sglang-install
```

---

## 推理服务配置 (`sglang-qwen3.8-27b-fp8`)

### 模型与 SGLang 固定参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 模型 | Qwen3.8-27B-FP8 | ~28 GB FP8 权重 |
| `--reasoning-parser` | `qwen3` | 思考链解析 |
| `--tool-call-parser` | `qwen3_coder` | 工具调用解析 |
| `--mem-fraction-static` | `0.85` | 静态显存占比 |
| `--mamba-ssm-dtype` | `bfloat16` | Mamba 层 dtype |
| `--chunked-prefill-size` | `2048` | 分块 prefill |
| `--attention-backend` | `triton` | 规避 flashinfer JIT + 旧 nvcc 问题 |
| `--trust-remote-code` | 开启 | Qwen 自定义代码 |

### 可调运行参数

| 变量 / CLI | 默认值 | 说明 |
|------------|--------|------|
| `-slot=N[,N...]` | `0` | 物理 GPU 槽位，逗号分隔 |
| `-port=N` | `10000` | HTTP 服务端口（LLM 1xxxx） |
| `-tp=N` | `1` | Tensor Parallel（模型切分） |
| `-dp=N` | `1` | Data Parallel（模型副本数） |
| `HOST` | `0.0.0.0` | 监听地址 |
| `STARTUP_TIMEOUT` | `600` | 等待 `/health` 秒数 |
| `-y` / `--yes` | — | 跳过交互，用 CLI/环境变量默认值 |

**GPU 数量约束：** `slot 数量 ≥ tp × dp`。SGLang 按 `CUDA_VISIBLE_DEVICES` 顺序使用前 `tp×dp` 张卡。

### 推荐方案（4×4090）

| 方案 | slot | tp | dp | port | 适用场景 |
|------|------|----|----|------|----------|
| ★ 单卡推理 | `0` | 1 | 1 | 10000 | 默认；27B-FP8 单卡 48 GB 足够 |
| 双卡 TP | `0,1` | 2 | 1 | 10000 | 更大 KV cache / 降低单卡压力 |
| 双副本 DP | `0,1` | 1 | 2 | 10000 | 两路并发副本（高级） |
| 四卡 TP | `0,1,2,3` | 4 | 1 | 10000 | 极限切分（通常不必） |

### 启动行为

1. 停止同模型 / 同端口旧进程
2. `nohup` 后台启动
3. 轮询 `http://127.0.0.1:${PORT}/health` 直到 200
4. 打印 PID / 日志 / URL 后返回 shell

```bash
# 交互式三步向导（推荐）
#   Step 1 → GPU 卡槽
#   Step 2 → tp / dp 并行策略
#   Step 3 → HTTP port
./scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8

# 非交互
./scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8 -slot=0 -port=10000 -tp=1 -dp=1 -y
```

关闭动画：`UI_ANIM=0 ./scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8`

Unicode 边框（终端支持 UTF-8 时）：`UI_UTF8=1 ./scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8`

### 冒烟测试

```bash
curl http://127.0.0.1:10000/health

curl http://127.0.0.1:10000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/data/models/Qwen3.8-27B-FP8","messages":[{"role":"user","content":"你好"}],"max_tokens":64}'
```

---

## RAG 三件套规划（待扩展）

| 组件 | 模型路径（规划） | 建议 slot | 建议 port |
|------|------------------|-----------|-----------|
| LLM | `/data/models/Qwen3.8-27B-FP8` | 0 | 10000 |
| Embedding 8B | `/data/models/Qwen3-Embedding-8B` | 1 | 20001 |
| Reranker 8B | `/data/models/Qwen3-Reranker-8` | 2 | 30001 |
| Embedding 4B + Reranker 4B | 同卡 cuda:3 | 20002 / 30002 | 见 `strategy/4x4090-48g-rag-suite/` |

Embedding：`./scripts/qwen3-embedding/sglang-qwen3-embedding`  
Reranker：`./scripts/qwen3-reranker/sglang-qwen3-reranker`  
同卡共部署时 Embedding 4B 用 `0.21`、Reranker 4B 用 `0.24`。

---

## 常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| `nvcc fatal: Unknown option '--compress-mode=size'` | flashinfer vs CUDA 12.4 nvcc | 重装环境或手动 patch `flashinfer/jit/core.py` |
| `libnvrtc.so.13` / cu130 包 | 混装 cu130 轮子 | 重装 cu129 栈，去掉 extra-index |
| `/health` 503 持续很久 | 首次 CUDA graph capture | 正常，约 1–3 分钟 |
| 根分区满 | venv 在 `~` | 迁移到 `/data/edwardluke` |

---

## 日志与运维

```bash
tail -f /data/edwardluke/cache/sglang/sglang-server.log
cat /data/edwardluke/cache/sglang/sglang-server.pid
nvidia-smi
```

重启 = 再次运行启动脚本（会自动 stop 旧实例）。
