"""为容器中的 Zotero 本地 API 连接提供 Windows 主机地址适配。"""

import os
import runpy

import zotero_mcp_attachment_patch
import zotero_mcp_auth_patch
import zotero_mcp_embedding_patch
import zotero_mcp_tool_disable_patch

from pyzotero import Zotero


_original_init = Zotero.__init__


def _patched_init(self, *args, **kwargs):
    """把本地 API 的连接地址改为容器可访问的 Windows 主机地址。"""
    _original_init(self, *args, **kwargs)

    local = kwargs.get("local", args[5] if len(args) > 5 else False)
    local_api_base = os.getenv("ZOTERO_LOCAL_API_BASE")
    if local and local_api_base:
        self.endpoint = local_api_base.rstrip("/")
        # Zotero 本地 API 会校验 Host，连接地址和 Host 头必须分开设置。
        self.client.headers["Host"] = "localhost:23119"


Zotero.__init__ = _patched_init
zotero_mcp_attachment_patch.install()
zotero_mcp_auth_patch.install()
zotero_mcp_embedding_patch.install()
zotero_mcp_tool_disable_patch.install()

runpy.run_module("zotero_mcp.cli", run_name="__main__")
