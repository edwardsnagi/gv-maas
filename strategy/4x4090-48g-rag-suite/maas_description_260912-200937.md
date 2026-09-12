# Qwen3 RAG MaaS 接入手册

> 自动生成于 2026-09-12 20:09:37 +0800  
> 策略目录: `/home/edwardluke/singulardance/gv/gv-maas/strategy/4x4090-48g-rag-suite`  
> **对外服务地址: 100.65.44.116**（Tailscale 自动探测；仅限局域网/本地调试：`127.0.0.1`、`192.168.50.17`）

本文档供其它项目/单位快速接入本机部署的 Qwen3 RAG 推理服务。所有接口均为 **OpenAI 兼容** REST API（SGLang 后端），无需 API Key。跨单位接入请使用上方**对外服务地址**及下文 URL，勿使用括号内地址。

---

## 1. 服务与端口一览

| 组件 | 型号 | GPU (cuda) | 端口 | mem-frac | 向量维度 | Health | API |
|------|------|------------|------|----------|----------|--------|-----|
| LLM | Qwen3.8-27B-FP8 | 0 | **10000** | 0.85 | — | `/health` | `/v1/chat/completions` |
| Embedding | Qwen3-Embedding-8B | 1 | **20001** | 0.45 | 4096 | `/health` | `/v1/embeddings` |
| Reranker | Qwen3-Reranker-8B | 2 | **30001** | 0.48 | — | `/health` | `/v1/rerank` |
| Embedding | Qwen3-Embedding-4B | 3 | **20002** | 0.21 | 2560 | `/health` | `/v1/embeddings` |
| Reranker | Qwen3-Reranker-4B | 3 | **30002** | 0.24 | — | `/health` | `/v1/rerank` |

**端口规则:** LLM `1xxxx` · Embedding `2xxxx` · Reranker `3xxxx`

---

## 2. 模型与官方地址

请求体中的 `model` 字段须使用下表 **服务端 model ID**（本地权重路径），与 HuggingFace 仓库名不同。

| 组件 | 服务端 model ID | HuggingFace 官方 |
|------|-----------------|------------------|
| LLM | `/data/models/Qwen3.8-27B-FP8` | [Qwen/Qwen3.8-27B-FP8](https://huggingface.co/Qwen/Qwen3.8-27B-FP8) |
| Embedding 8B | `/data/models/Qwen3-Embedding-8B` | [Qwen/Qwen3-Embedding-8B](https://huggingface.co/Qwen/Qwen3-Embedding-8B) |
| Embedding 4B | `/data/models/Qwen3-Embedding-4B` | [Qwen/Qwen3-Embedding-4B](https://huggingface.co/Qwen/Qwen3-Embedding-4B) |
| Reranker 8B | `/data/models/Qwen3-Reranker-8` | [Qwen/Qwen3-Reranker-8B](https://huggingface.co/Qwen/Qwen3-Reranker-8B) |
| Reranker 4B | `/data/models/Qwen3-Reranker-4B` | [Qwen/Qwen3-Reranker-4B](https://huggingface.co/Qwen/Qwen3-Reranker-4B) |

---

## 3. 环境变量（复制到其他项目）

```bash
# --- LLM ---
LLM_BASE_URL=http://100.65.44.116:10000/v1
LLM_MODEL=/data/models/Qwen3.8-27B-FP8
LLM_HEALTH=http://100.65.44.116:10000/health

# --- Embedding 8B（高质量 RAG，4096 维）---
EMBEDDING_8B_BASE_URL=http://100.65.44.116:20001/v1
EMBEDDING_8B_MODEL=/data/models/Qwen3-Embedding-8B
EMBEDDING_8B_DIM=4096

# --- Embedding 4B（轻量，2560 维）---
EMBEDDING_4B_BASE_URL=http://100.65.44.116:20002/v1
EMBEDDING_4B_MODEL=/data/models/Qwen3-Embedding-4B
EMBEDDING_4B_DIM=2560

# --- Reranker 8B ---
RERANKER_8B_BASE_URL=http://100.65.44.116:30001/v1
RERANKER_8B_MODEL=/data/models/Qwen3-Reranker-8

# --- Reranker 4B ---
RERANKER_4B_BASE_URL=http://100.65.44.116:30002/v1
RERANKER_4B_MODEL=/data/models/Qwen3-Reranker-4B
```

---

## 4. 健康检查

```bash
curl http://100.65.44.116:10000/health
curl http://100.65.44.116:20001/health
curl http://100.65.44.116:20002/health
curl http://100.65.44.116:30001/health
curl http://100.65.44.116:30002/health
```

返回 `200` 且 body 含 `healthy` 即表示就绪。

---

## 5. API 调用示例

### 5.1 LLM 对话 — `POST /v1/chat/completions`

```bash
curl http://100.65.44.116:10000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/Qwen3.8-27B-FP8",
    "messages": [{"role": "user", "content": "你好，请用一句话介绍你自己。"}],
    "max_tokens": 128,
    "temperature": 0.7
  }'
```

**Python（OpenAI SDK）:**

```python
from openai import OpenAI

client = OpenAI(base_url="http://100.65.44.116:10000/v1", api_key="unused")
resp = client.chat.completions.create(
    model="/data/models/Qwen3.8-27B-FP8",
    messages=[{"role": "user", "content": "你好"}],
    max_tokens=128,
)
print(resp.choices[0].message.content)
```

---

### 5.2 文本向量 — `POST /v1/embeddings`

**8B（4096 维，端口 20001）:**

```bash
curl http://100.65.44.116:20001/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/Qwen3-Embedding-8B",
    "input": "Qwen3-Embedding-8B 用于语义检索"
  }'
```

**4B（2560 维，端口 20002）:**

```bash
curl http://100.65.44.116:20002/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/Qwen3-Embedding-4B",
    "input": "Qwen3-Embedding-4B 轻量向量模型"
  }'
```

**Python:**

```python
from openai import OpenAI

emb = OpenAI(base_url="http://100.65.44.116:20001/v1", api_key="unused")
vec = emb.embeddings.create(
    model="/data/models/Qwen3-Embedding-8B",
    input="待检索的文档片段",
).data[0].embedding
print(len(vec))  # 4096
```

---

### 5.3 重排序 — `POST /v1/rerank`

**简单案例（8B，端口 30001）:**

```bash
curl http://100.65.44.116:30001/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/Qwen3-Reranker-8",
    "query": "What is Python?",
    "documents": [
      "Python is a programming language.",
      "The sky is blue."
    ]
  }'
```

**RAG 语义案例（验证 8B reranker 能区分相关文档）:**

```bash
curl http://100.65.44.116:30001/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/Qwen3-Reranker-8",
    "query": "Qwen embedding model with 4096 dimensions?",
    "documents": [
      "Qwen3-Embedding-8B produces 4096-dimensional vectors for semantic retrieval tasks.",
      "Qwen3-Embedding-4B produces 2560-dimensional vectors and is faster than the 8B variant.",
      "OpenAI text-embedding-3-large maps text to high-dimensional vectors for search."
    ]
  }'
```

返回为 `[{"index": 0, "score": ...}, ...]`，按 `score` 降序即为重排结果。4B reranker 将 `30001` 换为 `30002`，`model` 换为 `/data/models/Qwen3-Reranker-4B`。

---

## 6. RAG 接入建议

| 场景 | Embedding | Reranker | 说明 |
|------|-----------|----------|------|
| **高质量（推荐）** | :20001 8B (4096d) | :30001 8B | 精度优先 |
| **轻量 / 省显存** | :20002 4B (2560d) | :30002 4B | 两服务同卡 cuda:3 |

**典型 RAG 流程:**

1. 用 Embedding 服务将 query 与候选文档转为向量，做 Top-K 召回（Milvus / FAISS / pgvector 等）。
2. 将 query + Top-K 文档送入 Reranker，按 score 重排，取 Top-N 作为上下文。
3. 将重排后的上下文 + 用户问题送入 LLM（:10000）生成答案。

**注意:** Embedding 8B 与 4B 向量维度不同，索引库须与所选 Embedding 服务一致，不可混用。

---

## 7. 完整 RAG 最小示例（curl 串联）

```bash
HOST=100.65.44.116

# Step 1: 对 query 做 embedding
curl -s "http://${HOST}:20001/v1/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"model":"/data/models/Qwen3-Embedding-8B","input":"什么是 RAG？"}' \
  | jq '.data[0].embedding | length'   # 应输出 4096

# Step 2: 对召回候选做 rerank（此处直接传入 3 段文本模拟召回结果）
curl -s "http://${HOST}:30001/v1/rerank" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"/data/models/Qwen3-Reranker-8",
    "query":"什么是 RAG？",
    "documents":[
      "RAG（Retrieval-Augmented Generation）通过检索外部知识增强大模型回答。",
      "Python 是一种解释型编程语言。",
      "向量数据库用于存储 embedding 并做相似度搜索。"
    ]
  }' | jq 'sort_by(-.score)'

# Step 3: 将最相关上下文送入 LLM
curl -s "http://${HOST}:10000/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"/data/models/Qwen3.8-27B-FP8",
    "messages":[
      {"role":"system","content":"根据给定上下文回答。上下文：RAG（Retrieval-Augmented Generation）通过检索外部知识增强大模型回答。"},
      {"role":"user","content":"什么是 RAG？"}
    ],
    "max_tokens":256
  }' | jq -r '.choices[0].message.content'
```

---

## 8. 运维信息

| 项目 | 值 |
|------|-----|
| 一键启动脚本 | `/home/edwardluke/singulardance/gv/gv-maas/strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh` |
| 启动策略 | Wave 1 四卡并行 → Wave 2 Reranker 4B 串行（cuda:3 同卡） |
| 对外地址 | 默认自动探测（Tailscale `100.x` 优先）；可 `SERVICE_HOST=<ip>` 覆盖 |
| 跳过冒烟测试 | `SKIP_SMOKE_TEST=1 ./strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh` |
| 并行启动日志 | `/data/edwardluke/cache/sglang/launch-{llm,embedding-8b,embedding-4b,reranker-8b}.log` |
| LLM 日志 | `/data/edwardluke/cache/sglang/sglang-llm.log` |
| Embedding 8B 日志 | `/data/edwardluke/cache/sglang/sglang-embedding-8b.log` |
| Embedding 4B 日志 | `/data/edwardluke/cache/sglang/sglang-embedding-4b.log` |
| Reranker 8B 日志 | `/data/edwardluke/cache/sglang/sglang-reranker-8b.log` |
| Reranker 4B 日志 | `/data/edwardluke/cache/sglang/sglang-reranker-4b.log` |

每次重新运行启动脚本会替换同端口旧实例，删除旧手册并**重新生成本手册**。

---

## 9. 常见问题

| 问题 | 处理 |
|------|------|
| 连接超时 | 确认防火墙放行 10000/20001/20002/30001/30002；跨网段时使用 `SERVICE_HOST` 指定的可达 IP |
| `/health` 503 | 首次启动需 1–3 分钟（含 CUDA graph capture），查看对应日志 |
| Reranker 分数全部相同 | 服务端 chat template 配置问题，联系运维；正常时 hard case 最高分应 > 0.1 |
| Embedding 维度不符 | 8B→4096，4B→2560；检查是否连错端口 |
| `model` 字段报错 | 必须使用本文「服务端 model ID」列的路径，不能用 HF 短名 |

