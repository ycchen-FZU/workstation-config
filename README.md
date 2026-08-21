# workstation-config

用于同步 pc-cyc 与 pc-yh 的可移植工作站配置。

## 当前内容

- `zotero-mcp/`：CYC 当前 Zotero MCP 部署源码基线；YH 部署时移除 Embedding、Semantic、Chroma、CUDA/GPU 相关内容。
- `devspace/`：`@waishnav/devspace@1.0.7` 的 Windows Git Bash shell patch。
- `cloudflared/`：Cloudflare Tunnel 说明与示例配置，不包含 token 或凭据。

## 主机差异

- CYC Zotero Resource URL：`https://zotero.chen-group.cn`
- YH Zotero Resource URL：`https://zotero-yh.chen-group.cn`
- OAuth issuer：`https://auth.chen-group.cn`
- 两台主机允许使用不同本地路径。

## 不纳入仓库

Secrets、`.codex`、skills、`AGENTS.md`、Docker volumes、Chroma 索引、模型缓存、运行数据与本机 `document2md` 配置不纳入仓库。
