FROM --platform=linux/amd64 python:3.10-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/hf-cache \
    TRANSFORMERS_CACHE=/hf-cache

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Preload ViT artifacts to avoid first-request download failures in restricted networks.
RUN python - <<'PY'
from transformers import AutoImageProcessor, ViTModel
AutoImageProcessor.from_pretrained('google/vit-base-patch16-224')
ViTModel.from_pretrained('google/vit-base-patch16-224')
print('ViT cache primed')
PY

COPY api.py vit_inference.py inference.py ./

EXPOSE 8000
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
