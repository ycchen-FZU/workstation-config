"""让语义索引使用 document2md 已生成的 Markdown。"""

from pathlib import Path


def install() -> None:
    """标记 Markdown 来源，并过滤语义索引中的其他附件正文。"""
    from zotero_mcp import local_db, semantic_search

    if getattr(semantic_search, "_markdown_only_patch_installed", False):
        return

    original_fulltext = local_db.LocalZoteroReader._extract_fulltext_for_item
    original_process_batch = semantic_search.ZoteroSemanticSearch._process_item_batch
    original_update_database = semantic_search.ZoteroSemanticSearch.update_database

    def update_database_markdown_only(self, *args, **kwargs):
        """语义同步期间禁止回退解析非 Markdown 附件。"""
        previous = getattr(semantic_search, "_markdown_only_sync_active", False)
        semantic_search._markdown_only_sync_active = True
        try:
            return original_update_database(self, *args, **kwargs)
        finally:
            semantic_search._markdown_only_sync_active = previous

    semantic_search.ZoteroSemanticSearch.update_database = update_database_markdown_only

    def extract_fulltext_for_item(reader, item_id):
        """优先读取 document2md 生成的 Markdown；没有时保持 MCP 原生回退。"""
        markdown_candidates = []
        for key, path, ctype in reader._iter_parent_attachments(item_id):
            resolved = reader._resolve_attachment_path(key, path or "")
            if not resolved or not resolved.exists():
                continue
            normalized = (ctype or "").lower().split(";", 1)[0].strip()
            if normalized not in {"text/markdown", "text/x-markdown"} and resolved.suffix.lower() not in {".md", ".markdown"}:
                continue
            try:
                size = resolved.stat().st_size
            except OSError:
                size = 0
            markdown_candidates.append((size, resolved))

        if markdown_candidates:
            target = max(markdown_candidates, key=lambda candidate: candidate[0])[1]
            text = reader._extract_text_from_file(target)
            if text:
                return text, "markdown"

        if getattr(semantic_search, "_markdown_only_sync_active", False):
            return "", ""

        # MCP 普通读取仍使用 zotero-mcp 官方原生逻辑。
        return original_fulltext(reader, item_id)

    local_db.LocalZoteroReader._extract_fulltext_for_item = extract_fulltext_for_item

    def process_item_batch_only_markdown(self, items, force_rebuild=False, _failed_docs=None):
        """条目元数据照常入库；附件正文只允许 Markdown。"""
        sanitized_items = []
        for item in items:
            data = item.get("data", {})
            if data.get("fulltext") and data.get("fulltextSource") != "markdown":
                item = dict(item)
                item["data"] = dict(data)
                item["data"]["fulltext"] = ""
                item["data"]["fulltextSource"] = ""
            sanitized_items.append(item)
        return original_process_batch(
            self,
            sanitized_items,
            force_rebuild=force_rebuild,
            _failed_docs=_failed_docs,
        )

    semantic_search.ZoteroSemanticSearch._process_item_batch = process_item_batch_only_markdown
    semantic_search._markdown_only_patch_installed = True
