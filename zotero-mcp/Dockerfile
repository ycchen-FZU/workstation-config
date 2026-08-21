FROM pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

ARG PIP_INDEX_URL=https://pypi.org/simple
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

RUN python -m pip install --no-cache-dir --break-system-packages \
    --index-url "${PIP_INDEX_URL}" \
    "zotero-mcp-server[semantic,scite]==0.9.1" \
    "sentence-transformers==5.7.0" \
    "transformers==4.57.6" \
    "peft==0.20.0"

COPY docker/zotero_mcp_entrypoint.py /app/zotero_mcp_entrypoint.py
COPY docker/zotero_mcp_attachment_patch.py /app/zotero_mcp_attachment_patch.py
COPY docker/zotero_mcp_auth_patch.py /app/zotero_mcp_auth_patch.py
COPY docker/zotero_mcp_embedding_patch.py /app/zotero_mcp_embedding_patch.py
COPY docker/zotero_mcp_tool_disable_patch.py /app/zotero_mcp_tool_disable_patch.py

ENTRYPOINT ["python", "/app/zotero_mcp_entrypoint.py"]
