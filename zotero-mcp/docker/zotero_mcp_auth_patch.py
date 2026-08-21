"""为 Zotero MCP 注入远程 OAuth Resource Server 认证。"""

from __future__ import annotations

import os

from fastmcp.server.auth import RemoteAuthProvider
from fastmcp.server.auth.providers.jwt import JWTVerifier
from pydantic import AnyHttpUrl


def install() -> None:
    """使用 Authelia JWKS 验证发给 Zotero MCP 的访问令牌。"""
    issuer = os.getenv("ZOTERO_MCP_AUTH_ISSUER", "").strip().rstrip("/")
    resource_url_raw = os.getenv("ZOTERO_MCP_RESOURCE_URL", "").strip()
    jwks_uri = os.getenv("ZOTERO_MCP_JWKS_URI", "").strip()

    if not issuer or not resource_url_raw:
        return
    if not jwks_uri:
        jwks_uri = f"{issuer}/jwks.json"

    # 与 OAuth metadata 使用同一 URL 规范化结果，避免 JWT audience 因尾部斜杠不一致而被拒绝。
    resource_url = str(AnyHttpUrl(resource_url_raw))

    # 延迟导入现有 FastMCP 实例，不修改上游 zotero-mcp-server 源码。
    from zotero_mcp._app import mcp

    verifier = JWTVerifier(
        jwks_uri=jwks_uri,
        issuer=issuer,
        audience=resource_url,
        algorithm="RS256",
        required_scopes=[],
    )
    mcp.auth = RemoteAuthProvider(
        token_verifier=verifier,
        authorization_servers=[AnyHttpUrl(issuer)],
        base_url=resource_url,
        resource_base_url=resource_url,
        scopes_supported=[],
        resource_name="Zotero",
    )
