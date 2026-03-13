FROM python:3.10-slim

# Pod GPU default. Override at build time if needed.
ARG TORCH_CHANNEL=cu126

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HOST=0.0.0.0 \
    PORT=8000 \
    HF_HOME=/runpod-volume/hf_home \
    HF_HUB_CACHE=/runpod-volume/hf_cache \
    TRANSFORMERS_CACHE=/runpod-volume/hf_cache \
    GLM_MODEL_CACHE=/runpod-volume/hf_cache \
    GLM_MODEL_HOME=/runpod-volume/hf_home \
    PYTHONPATH=/workspace \
    TORCH_CHANNEL=${TORCH_CHANNEL}

WORKDIR /workspace

COPY requirements.txt /workspace/requirements.txt
COPY app /workspace/app
COPY api /workspace/api
COPY web /workspace/web

RUN python -m pip install --upgrade pip \
    && python -m pip install --no-compile --upgrade --index-url https://download.pytorch.org/whl/${TORCH_CHANNEL} torch torchvision \
    && python -m pip install --no-compile transformers \
    && python -m pip install --no-compile -r /workspace/requirements.txt

RUN mkdir -p /runpod-volume/hf_cache /runpod-volume/hf_home

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--app-dir", "/workspace", "--host", "0.0.0.0", "--port", "8000"]