# Cloudflare Tunnel

本目录管理 Windows 主机级 Cloudflare Tunnel 相关说明与示例配置。`cloudflared` 作为主机服务运行，不进入业务 Docker Compose。

当前 Windows 服务使用 token 文件启动，由 Cloudflare 远程管理 Tunnel ingress。业务服务直接监听本机端口，Cloudflare Tunnel 直接转发到对应服务；不在本机增加额外的 DevSpace 端口代理或路径改写层。

DevSpace 对外连接使用完整 MCP 地址：

```text
https://devspace.chen-group.cn/mcp
```

DevSpace 本机直接监听 `127.0.0.1:7676`。不再使用 `7677`，也不再将 `/` 改写为 `/mcp`。

`config.example.yml` 保留为本地管理 Tunnel 时的 Zotero MCP 示例。实际凭据、token 和本机 `config.yml` 不进入代码仓库。
