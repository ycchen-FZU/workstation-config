# DevSpace workstation patch

本目录固化 Windows 工作站上的 `@waishnav/devspace@1.0.7` 二次配置。

## 目标

- DevSpace 只监听 `127.0.0.1:7676`，公网访问交给 Cloudflare Tunnel。
- MCP 地址为 `https://<host>/mcp`。
- OAuth 统一由 `https://auth.chen-group.cn` 的 Authelia 签发 JWT。
- DevSpace 只作为 OAuth Resource Server，通过 Authelia JWKS 校验 RS256 access token。
- Windows `exec_command` 使用 Git Bash，而不是 `cmd.exe`。

## 文件

- `patch-devspace-authelia-auth.ps1`：将上游内置 owner-token OAuth 替换为 Authelia/JWT Resource Server。
- `patch-devspace-codex-shell.ps1`：将 Windows Codex shell 从 `cmd.exe` 改为 Git Bash。
- `config.example.json`：`~/.devspace/config.json` 无敏感信息模板。

两个补丁均锁定 `@waishnav/devspace@1.0.7`，遇到未知文件状态会拒绝修改。

## 安装/恢复

```powershell
npm install -g @waishnav/devspace@1.0.7

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\patch-devspace-authelia-auth.ps1

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\patch-devspace-codex-shell.ps1
```

正式执行前可分别加 `-CheckOnly` 检查兼容性。

将 `config.example.json` 复制为 `%USERPROFILE%\.devspace\config.json` 后，按工作站修改：

- `allowedRoots`
- `publicBaseUrl`
- `oauth.resourceUrl`

`oauth.resourceUrl` 使用工作站对应的公网 origin；补丁会规范化为带尾斜杠的 audience。

## Authelia client

每台工作站使用独立 public/PKCE client。至少保持：

- `public: true`
- `require_pkce: true`
- `pkce_challenge_method: S256`
- `grant_types: authorization_code, refresh_token`
- `response_types: code`
- `token_endpoint_auth_method: none`
- `scopes: offline_access`
- `requested_audience_mode: explicit`
- `access_token_signed_response_alg: RS256`
- audience 与该工作站 `oauth.resourceUrl` 完全一致
- redirect URI 使用 ChatGPT Connector 实际生成的 URI，不复用其他工作站 URI

ChatGPT Connector 的服务器地址必须包含 `/mcp`，例如：

```text
https://devspace-yh.chen-group.cn/mcp
```

## 旧 OAuth 状态

补丁不再读取 `~/.devspace/auth.json`，也不再读取/写入 SQLite 中旧的 `oauth_*` 表。历史文件和表可保留，不影响运行；无需为了清理历史状态直接修改数据库。

## 重启边界

补丁修改的是已安装 npm 包代码。运行中的 DevSpace 不会自动加载修改；需要由工作站用户手动重启 DevSpace 后生效。
