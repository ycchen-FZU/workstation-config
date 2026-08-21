# zotero-mcp

`zotero-mcp` 是独立的 Zotero MCP 网关。它把 Zotero 本地 API、Markdown 优先全文索引、Jina Embedding、Chroma/RAG 和 MCP `streamable-http` 服务放在同一个 Docker 容器中。

## 职责边界

| 组件 | 职责 | 运行位置 |
| --- | --- | --- |
| Zotero Desktop | 提供本地 API 和文献数据 | Windows 主机 |
| `zotero-mcp` | MCP、Embedding、Chroma/RAG、Zotero 适配补丁 | Docker 容器 |
| `cloudflared` | HTTPS 公网传输和 Cloudflare Tunnel | Windows 主机服务 |
| `document2md` | 文档转 Markdown，不属于本容器 | 独立项目/独立 Compose |

本项目不包含 PaddleOCR、Docling 或 tunnel 凭据。`document2md` 生成的 Markdown 是语义索引的优先正文来源。

## 目录职责

| 目录/文件 | 职责 |
| --- | --- |
| `Dockerfile` | 构建 MCP + Embedding/RAG 运行镜像 |
| `docker/` | Windows 主机 Zotero API 适配、Markdown 索引和工具补丁 |
| `config/` | Zotero 数据库与语义索引配置 |
| `env/` | 本地运行参数模板；真实凭据不提交 |
| `integrations/document2md.js` | Zotero Actions & Tags 调用 document2md 的 server/local 配置脚本 |
| `docker-compose.yml` | 只编排 Zotero MCP 容器、数据挂载和持久化卷 |

## 启动

首次使用时复制环境模板，并根据实际 Zotero 数据目录调整 `ZOTERO_DATA_DIR`：

```powershell
Copy-Item env/.env.example env/.env
docker compose --env-file env/.env up -d --build
```

启动前确认：

1. Zotero Desktop 正在运行，并已启用本地 API；
2. `ZOTERO_DATA_DIR` 指向包含 `zotero.sqlite` 的 Zotero 数据目录；
3. Docker Desktop 已启用 WSL2、NVIDIA Container Toolkit 和 GPU 支持；
4. 首次启动会下载 `jinaai/jina-embeddings-v5-text-small`，耗时取决于网络和模型缓存。

服务仅绑定本机：

```text
http://127.0.0.1:8000
```

## Embedding 与 RAG

- Embedding 模型和 MCP 服务在同一个 `zotero-mcp` 容器中运行。
- Chroma 数据使用 `zotero-mcp-chroma` Docker volume 持久化。
- Hugging Face 模型缓存使用独立的外部 Docker volume。
- Zotero 数据目录以只读方式挂载到 `/mnt/zotero`；索引读取 Markdown 优先，不修改原始附件。
- 需要更新索引时，在容器中运行：

```powershell
docker compose --env-file env/.env exec zotero-mcp zotero-mcp update-db
```

## Cloudflare Tunnel

Tunnel 不放进 MCP 容器，也不暴露 Zotero `23119`、PaddleOCR `8080` 或 document2md `18321`。

主机级 Cloudflare 配置统一归入 [`infra/cloudflared`](../../infra/cloudflared)；目标固定为：

```text
ChatGPT 网页版
    ↓ HTTPS
Cloudflare Tunnel
    ↓
127.0.0.1:8000 → zotero-mcp
```

Cloudflare 配置只保存 Tunnel ID 和凭据文件路径；凭据文件保存在用户目录，不进入项目。

## Zotero document2md 脚本

脚本顶部使用 `DOCUMENT2MD_PROFILE` 明确选择渠道：

```javascript
const DOCUMENT2MD_PROFILE = "local"; // 或 "server"
```

- `local`：调用 `http://127.0.0.1:18321/process`，适合 Windows 本地 GPU Compose；
- `server`：调用 `https://api.chen-group.cn/v1/document2md`，适合服务器官方 PaddleOCR API；
- server 模式的共享密钥只填入本机 Zotero 脚本，不提交到代码仓库。

## 网络和数据边界

- MCP 容器通过 `host.docker.internal:23119` 访问 Windows 主机上的 Zotero 本地 API。
- MCP 端口绑定 `127.0.0.1:8000`，公网入口只由 Cloudflare Tunnel 提供。
- document2md 和 zotero-mcp 使用独立 Compose、镜像、网络和数据卷，仅通过 HTTP API 与共享 Zotero 附件目录协作。
- 不使用 `paddleocr-https-proxy`，不保留 Windows 原生 `zotero-mcp-runtime`。
