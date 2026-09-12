# Qwen3 Reranker 部署（4B / 8B）

SGLang reranker 服务，OpenAI 兼容 `/v1/rerank`（decoder-only yes/no 打分）。

共享环境：`../qwen3.8-27b-fp8/sglang-install`

**不要** 加 `--is-embedding`。

**必须使用 SGLang 兼容的 chat template**（`lib/qwen3_reranker.jinja`）。  
模型自带的 `chat_template.jinja` 与 SGLang `/v1/rerank` 消息格式不兼容，会导致所有文档得分相同。

模板必须在 assistant 段包含官方 Qwen3 的空 thinking 占位（见 `lib/qwen3_reranker.jinja`）。缺少时 **8B** 在 SGLang 下分数会极低（~0.03）且排序错误。

本地权重目录名为 `Qwen3-Reranker-8`（缺 `B` 后缀），这是下载时的目录名，**不是**加载错误；`/v1/models` 会显示该路径。可用 symlink 统一命名：

```bash
ln -sfn /data/models/Qwen3-Reranker-8 /data/models/Qwen3-Reranker-8B
# 启动时: MODEL_PATH=/data/models/Qwen3-Reranker-8B ...
```

---

## 模型

| size | 路径 | 权重大小 |
|------|------|----------|
| `4b`（默认） | `/data/models/Qwen3-Reranker-4B` | ~7.6 GB |
| `8b` | `/data/models/Qwen3-Reranker-8` | ~15 GB |

---

## 显存策略

`mem-fraction-static` 控制 SGLang **预占**显存比例，与模型实际权重大小无关。

| 场景 | 4B embedding | 4B reranker | 合计（48 GB 卡） |
|------|--------------|-------------|------------------|
| **同卡共部署**（推荐） | `0.21` (~10 GB) | `0.24` (~11.5 GB) | ~21 GB 预留 + ~15 GB 权重 ≈ 36 GB |
| 独占单卡 | — | `0.48` | ~23 GB 预留 |

---

## 同卡部署示例（4B Embedding + 4B Reranker）

假设 LLM 在 GPU 1（cuda:0），Embedding + Reranker 共占 GPU 3（cuda:2）：

```bash
# 1. 重启 4B embedding（降低显存上限）
./scripts/qwen3-embedding/sglang-qwen3-embedding \
  -size=4b -slot=3 -port=20002 -mem=0.21 -y

# 2. 同卡启动 reranker
./scripts/qwen3-reranker/sglang-qwen3-reranker \
  -size=4b -slot=3 -port=30002 -mem=0.24 -y
```

验证显存（每进程约 10 GB 预留，合计 ~20 GB）：

```bash
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv
```

---

## 冒烟测试

```bash
curl http://127.0.0.1:30002/health

curl http://127.0.0.1:30002/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/Qwen3-Reranker-4B",
    "query": "What is the capital of China?",
    "documents": [
      "Beijing is the capital of China.",
      "Paris is the capital of France."
    ]
  }'
```

---

## 4×4090 RAG 布局建议

| 组件 | GPU (cuda) | port | mem-fraction |
|------|------------|------|--------------|
| LLM Qwen3.8-27B-FP8 | 0 | 10000 | 0.85 |
| Embedding 8B | 1 | 20001 | 0.45 |
| Reranker 8B | 2 | 30001 | 0.48 |
| Embedding 4B + Reranker 4B | 3 | 20002 / 30002 | 0.21 + 0.24 |
| （备用） | 3 | — | — |
