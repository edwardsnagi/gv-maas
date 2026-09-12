# Qwen3 Embedding 部署（4B / 8B）

SGLang embedding 服务，OpenAI 兼容 `/v1/embeddings`。

共享环境安装：`../qwen3.8-27b-fp8/sglang-install`（同一 venv）。

---

## 目录

| 文件 | 用途 |
|------|------|
| `sglang-qwen3-embedding` | 启动脚本（交互 / CLI） |
| `lib/embedding-wizard.sh` | 三步向导：size → slot → port |

---

## 模型

| size | 路径 | 说明 |
|------|------|------|
| `8b`（默认） | `/data/models/Qwen3-Embedding-8B` | 更高质量 |
| `4b` | `/data/models/Qwen3-Embedding-4B` | 更省显存、更快 |

---

## 默认参数

| 项 | 默认值 |
|----|--------|
| GPU slot | `1`（LLM 常用 slot 0 时可错开） |
| port | `20001`（Embedding 2xxxx） |
| mem-fraction-static | `4b=0.21`, `8b=0.45`（非模型实际占用，是 SGLang 预占上限） |
| attention-backend | `triton` |
| 日志 | `/data/edwardluke/cache/sglang/sglang-embedding-server.log` |

---

## 启动

```bash
# 交互式（推荐）：选 size → slot → port
./scripts/qwen3-embedding/sglang-qwen3-embedding

# 非交互：8B，slot 1，port 20001
./scripts/qwen3-embedding/sglang-qwen3-embedding -size=8b -slot=1 -port=20001 -y

# 4B + 同卡 reranker（mem 默认 0.21，约 10 GB 预占）
./scripts/qwen3-embedding/sglang-qwen3-embedding -size=4b -slot=3 -port=20002 -y

# 显式指定 mem-fraction-static
./scripts/qwen3-embedding/sglang-qwen3-embedding -size=4b -slot=3 -port=20002 -mem=0.21 -y
```

已有同模型/同端口实例时，交互模式会提示 **Replace / Abort**。

---

## 冒烟测试

```bash
curl http://127.0.0.1:20001/health

curl http://127.0.0.1:20001/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"/data/models/Qwen3-Embedding-8B","input":"你好"}'
```

---

## RAG 三件套 slot 建议（4×4090）

| 组件 | slot (cuda) | port | mem-fraction |
|------|-------------|------|--------------|
| LLM Qwen3.8-27B-FP8 | 0 | 10000 | 0.85 |
| Embedding 8B | 1 | 20001 | 0.45 |
| Embedding 4B + Reranker 4B（同卡） | 3 | 20002 / 30002 | 0.21 + 0.24 |

Reranker 启动：`./scripts/qwen3-reranker/sglang-qwen3-reranker`
