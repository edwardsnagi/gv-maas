# qwen3.8-27b-fp8@4090

在 **4× RTX 4090 (48 GB)** 上部署 **Qwen3.8-27B-FP8** 推理服务（SGLang，OpenAI 兼容 `/v1`）。

详细配置见 [`scripts/qwen3.8-27b-fp8/README.md`](../scripts/qwen3.8-27b-fp8/README.md)。

---

## 前提

| 项目 | 值 |
|------|-----|
| 模型权重 | `/data/models/Qwen3.8-27B-FP8`（~28 GB FP8，单卡可跑） |
| venv | `/data/edwardluke/venvs/sglang` |
| 驱动 CUDA | 12.4 → 必须用 **cu129** 轮子 |
| 默认端口 | `8000` |

首次使用创建数据目录：

```bash
sudo mkdir -p /data/edwardluke/{venvs,cache/uv,cache/pip,cache/tmp,cache/sglang}
sudo chown -R $USER:$USER /data/edwardluke
```

---

## 1. 安装环境（一次性）

```bash
cd ~/singulardance/gv/gv-maas
./scripts/qwen3.8-27b-fp8/sglang-install
```

安装完成后应满足：`torch.cuda.is_available() == True`，`sglang 0.5.19`，`sglang-kernel +cu129`。

---

## 2. 启动服务

### 交互式（推荐）

三步向导：卡槽 → tp/dp → port。已有实例时会提示 **Replace / Abort**。

```bash
./scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8
```

### 非交互

```bash
./scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8 -slot=0 -port=8000 -tp=1 -dp=1 -y
```

脚本会后台启动，**等待 `/health` 返回 200 后再回到终端**（首次约 1–3 分钟，含 CUDA graph capture）。

### 4090 推荐配置

| 场景 | 命令示例 |
|------|----------|
| ★ 单卡推理（默认） | `-slot=0 -tp=1 -dp=1` |
| 双卡 Tensor Parallel | `-slot=0,1 -tp=2 -dp=1` |
| 双副本 Data Parallel | `-slot=0,1 -tp=1 -dp=2` |

---

## 3. 验证

```bash
curl http://127.0.0.1:8000/health

curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/data/models/Qwen3.8-27B-FP8","messages":[{"role":"user","content":"你好"}],"max_tokens":64}'
```

---

## 4. 运维

```bash
# 日志
tail -f /data/edwardluke/cache/sglang/sglang-server.log

# PID
cat /data/edwardluke/cache/sglang/sglang-server.pid

# GPU 状态
nvidia-smi
```

重启：再次运行启动脚本即可（交互模式下可选 Replace 停止旧实例；`-y` 模式自动替换）。

---

## 常见问题

| 现象 | 处理 |
|------|------|
| `ModuleNotFoundError: sglang` | 运行 `sglang-install` |
| `nvcc fatal: Unknown option '--compress-mode=size'` | 重装环境（install 会自动 patch flashinfer） |
| `/health` 长时间 503 | 首次启动正常，查看日志等待 graph capture 完成 |
| 根分区满 | 确保 venv/缓存都在 `/data/edwardluke`，勿写 `~/.venvs` |
