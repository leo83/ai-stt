FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Drop the CUDA forward-compat libcuda shipped by the base image. On a host whose
# driver is older than it (e.g. 535) the NVIDIA runtime puts it in front of the
# host driver, and on non-datacenter GPUs (RTX 3090 & co.) CTranslate2 then fails
# with "forward compatibility was attempted on non supported HW". Without it the
# CUDA 12.4 libs run on any driver >= 525 via minor-version compatibility.
RUN rm -rf /usr/local/cuda/compat /usr/local/cuda-*/compat

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3.11 python3.11-venv \
 && rm -rf /var/lib/apt/lists/*

# uv (pinned; bump the tag to upgrade, or use :latest to float).
COPY --from=ghcr.io/astral-sh/uv:0.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# 1) Dependency layer — rebuilt only when pyproject.toml / uv.lock change
#    (skips re-pulling faster-whisper/CTranslate2 on a code-only edit).
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project --extra api --python python3.11

# 2) Project layer — cheap; only re-runs on a code change.
COPY . .
RUN uv sync --frozen --no-dev --extra api --python python3.11

ENV PATH="/app/.venv/bin:$PATH" \
    HF_HOME=/cache/huggingface

# Entrypoint last so edits to it never invalidate the layers above.
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
