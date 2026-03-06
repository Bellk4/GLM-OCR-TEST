FROM python:3.10-slim

# Serverless GPU default. Override at build time if needed.
ARG TORCH_CHANNEL=cu126

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/runpod-volume/hf_home \
    HF_HUB_CACHE=/runpod-volume/hf_cache \
    TRANSFORMERS_CACHE=/runpod-volume/hf_cache \
    GLM_MODEL_CACHE=/runpod-volume/hf_cache \
    TORCH_CHANNEL=${TORCH_CHANNEL}

WORKDIR /workspace

# git is required because transformers is installed from GitHub.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

COPY app /workspace/app
COPY handler.py /workspace/handler.py
COPY README.md /workspace/README.md
COPY LICENSE /workspace/LICENSE
COPY THIRD_PARTY_NOTICES.md /workspace/THIRD_PARTY_NOTICES.md

RUN python -m pip install --upgrade pip \
    && python -m pip install --upgrade --index-url https://download.pytorch.org/whl/${TORCH_CHANNEL} torch torchvision \
    && python -m pip install fastapi uvicorn python-multipart pillow pypdfium2 accelerate numpy runpod \
    && python -m pip install git+https://github.com/huggingface/transformers.git

RUN mkdir -p /runpod-volume/hf_cache /runpod-volume/hf_home

CMD ["python", "-u", "/workspace/handler.py"]
