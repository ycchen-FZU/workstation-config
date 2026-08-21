"""关闭用户指定的 Zotero MCP 工具。"""


DISABLED_TOOLS = {
    "zotero_search_by_citation_key",
    "zotero_get_attachment_path",
    "zotero_get_recent",
    "zotero_get_notes",
    "zotero_manage_note",
    "zotero_update_annotation",
    "zotero_read_pdf_pages",
    "zotero_attach_file",
    "zotero_batch_update",
}


def install() -> None:
    """包装官方 toolset 应用逻辑，使核心禁用项在每次重应用后仍保持关闭。"""
    from zotero_mcp import toolsets

    if getattr(toolsets, "_local_tool_disable_patch_installed", False):
        return

    original_apply_toolsets = toolsets.apply_toolsets

    def apply_toolsets_with_disabled_tools(mcp, *, raw=None, transport=None):
        enabled = original_apply_toolsets(mcp, raw=raw, transport=transport)
        mcp.disable(names=DISABLED_TOOLS)
        return enabled

    toolsets.apply_toolsets = apply_toolsets_with_disabled_tools
    toolsets._local_tool_disable_patch_installed = True
