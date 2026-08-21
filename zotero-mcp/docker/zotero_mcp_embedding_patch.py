"""为 zotero-mcp 的本地 SentenceTransformer 增加 Jina 检索配置。"""

from __future__ import annotations

import os
from typing import Any


_CONFIG_KEYS = {
    "device",
    "dtype",
    "trust_remote_code",
    "batch_size",
    "normalize_embeddings",
    "show_progress_bar",
    "task",
    "document_prompt_name",
    "query_prompt_name",
    "prompt_name",
    "max_seq_length",
    "precision",
    "truncate_dim",
}


def _torch_dtype(name: str | None):
    """将配置中的 dtype 字符串转换为 torch.dtype。"""
    if not name:
        return None
    import torch

    normalized = str(name).strip().lower().removeprefix("torch.")
    try:
        return getattr(torch, normalized)
    except AttributeError as exc:
        raise ValueError(f"不支持的 embedding_config.dtype: {name}") from exc


def install() -> None:
    """让 zotero-mcp 读取 embedding_config 并分别使用 document/query prompt。"""
    from zotero_mcp import chroma_client

    if getattr(chroma_client, "_jina_embedding_patch_installed", False):
        return

    embedding_cls = chroma_client.HuggingFaceEmbeddingFunction
    original_create = chroma_client.ChromaClient._create_embedding_function

    def patched_init(self, model_name: str = "Qwen/Qwen3-Embedding-0.6B", embedding_config: dict[str, Any] | None = None):
        from sentence_transformers import SentenceTransformer
        import torch

        self.model_name = model_name
        self.embedding_config = dict(embedding_config or {})
        config = self.embedding_config
        device = config.get("device") or os.getenv("ZOTERO_EMBEDDING_DEVICE")
        if not device:
            device = "cuda" if torch.cuda.is_available() else "cpu"

        model_kwargs = {}
        dtype = _torch_dtype(config.get("dtype"))
        if dtype is not None:
            model_kwargs["dtype"] = dtype

        # Jina 的 remote code 需要 trust_remote_code；其他本地模型也兼容这个默认值。
        self.model = SentenceTransformer(
            model_name,
            trust_remote_code=bool(config.get("trust_remote_code", True)),
            device=device,
            model_kwargs=model_kwargs or None,
        )
        max_seq_length = config.get("max_seq_length")
        if max_seq_length is not None:
            self.model.max_seq_length = int(max_seq_length)
        self.max_input_tokens = getattr(self.model, "max_seq_length", 500)

    def _encode(self, texts, *, prompt_name: str | None):
        config = self.embedding_config
        kwargs: dict[str, Any] = {
            "convert_to_numpy": True,
            "show_progress_bar": bool(config.get("show_progress_bar", False)),
        }
        if config.get("batch_size") is not None:
            kwargs["batch_size"] = int(config["batch_size"])
        if "normalize_embeddings" in config:
            kwargs["normalize_embeddings"] = bool(config["normalize_embeddings"])
        if config.get("precision") is not None:
            kwargs["precision"] = config["precision"]
        if config.get("truncate_dim") is not None:
            kwargs["truncate_dim"] = int(config["truncate_dim"])
        if config.get("task"):
            kwargs["task"] = config["task"]
        if prompt_name:
            kwargs["prompt_name"] = prompt_name
        return self.model.encode(texts, **kwargs)

    def patched_call(self, input):
        """用 Jina document prompt 编码待入库文本。"""
        config = self.embedding_config
        prompt_name = config.get("document_prompt_name") or config.get("prompt_name")
        return self._jina_encode(input, prompt_name=prompt_name).tolist()

    def patched_embed_query(self, text: str):
        """用 Jina query prompt 编码搜索查询。"""
        prompt_name = self.embedding_config.get("query_prompt_name")
        return self._jina_encode([text], prompt_name=prompt_name)[0].tolist()

    def patched_get_config(self):
        config = {
            "model_name": self.model_name,
            "api_key_env_var": "HUGGINGFACE_API_KEY",
        }
        for key in _CONFIG_KEYS:
            if key in self.embedding_config:
                config[key] = self.embedding_config[key]
        return config

    @staticmethod
    def patched_build_from_config(config: dict[str, Any]):
        return embedding_cls(
            model_name=config.get("model_name", "Qwen/Qwen3-Embedding-0.6B"),
            embedding_config={key: config[key] for key in _CONFIG_KEYS if key in config},
        )

    # 保留原类和 Chroma 注册名，避免已有持久化 collection 无法恢复。
    embedding_cls.__init__ = patched_init
    embedding_cls._jina_encode = _encode
    embedding_cls.__call__ = patched_call
    embedding_cls.embed_query = patched_embed_query
    embedding_cls.get_config = patched_get_config
    embedding_cls.build_from_config = staticmethod(patched_build_from_config)

    def patched_create(self):
        model = self.embedding_model
        if model == "qwen":
            model_name = self.embedding_config.get("model_name", "Qwen/Qwen3-Embedding-0.6B")
            return embedding_cls(model_name=model_name, embedding_config=self.embedding_config)
        if model == "embeddinggemma":
            model_name = self.embedding_config.get("model_name", "google/embeddinggemma-300m")
            return embedding_cls(model_name=model_name, embedding_config=self.embedding_config)
        if model not in {"default", "openai", "gemini", "ollama"}:
            return embedding_cls(model_name=model, embedding_config=self.embedding_config)
        return original_create(self)

    chroma_client.ChromaClient._create_embedding_function = patched_create
    chroma_client._jina_embedding_patch_installed = True
