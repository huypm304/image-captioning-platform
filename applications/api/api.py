from __future__ import annotations

import logging
import os
import time
import traceback
from io import BytesIO

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from prometheus_fastapi_instrumentator import Instrumentator
from pythonjsonlogger import jsonlogger

logger = logging.getLogger("backend")
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setFormatter(
    jsonlogger.JsonFormatter(
        fmt="%(asctime)s %(levelname)s %(name)s %(message)s",
        rename_fields={"asctime": "timestamp", "levelname": "level"},
    )
)
logger.addHandler(handler)


def _truthy_env(name: str, default: str = "false") -> bool:
    return os.getenv(name, default).strip().lower() in ("1", "true", "yes", "on")


STRICT_HEALTH_CHECK = _truthy_env("STRICT_HEALTH_CHECK", "false")

# Preload model + metadata at startup to avoid slow first request
_startup_error = None
try:
    logger.info("startup_preload_begin")
    from vit_inference import load_caption_model, load_metadata, VIT_CAPTION_MODEL_PATH, VIT_METADATA_PATH
    _caption_model = load_caption_model()
    _metadata = load_metadata()
    logger.info("startup_preload_complete", extra={"model_path": VIT_CAPTION_MODEL_PATH, "metadata_path": VIT_METADATA_PATH})
except Exception as e:
    _startup_error = e
    logger.error("startup_preload_failed", extra={"error": str(e), "error_type": type(e).__name__})

app = FastAPI(title="Image Captioning API (ViT)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

instrumentator = Instrumentator(
    excluded_handlers=["/health", "/metrics", "/"],
)
instrumentator.instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.get("/")
def root():
    """ALB / generic probes often hit `/` on the API host; avoid noisy 404s."""
    return {"service": "image-caption-api", "docs": "/docs", "health": "/health"}


@app.get("/health")
def health():
    if _startup_error and STRICT_HEALTH_CHECK:
        logger.warning("health_check_startup_failed")
        raise HTTPException(status_code=503, detail=f"Backend not ready: {type(_startup_error).__name__}: {str(_startup_error)}")
    return {
        "status": "ok",
        "models_ready": _startup_error is None,
        "strict_health_check": STRICT_HEALTH_CHECK,
    }


@app.post("/predict")
async def predict(
    file: UploadFile = File(...),
    strategy: str = "beam",
    beam_width: int = 3,
):
    if strategy not in {"beam", "greedy"}:
        raise HTTPException(status_code=422, detail="strategy must be 'beam' or 'greedy'")

    try:
        content = await file.read()
        img = Image.open(BytesIO(content)).convert("RGB")
    except UnidentifiedImageError:
        raise HTTPException(status_code=415, detail="Uploaded file is not a valid image")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to read image: {str(e)}")

    logger.info(
        "inference_start",
        extra={"upload_filename": file.filename, "strategy": strategy, "beam_width": beam_width},
    )

    try:
        from vit_inference import generate_caption

        start = time.perf_counter()
        caption_text = generate_caption(img, strategy=strategy, beam_width=beam_width)
        duration = time.perf_counter() - start
    except Exception as e:
        logger.exception(
            "inference_error",
            extra={"error": str(e), "error_type": type(e).__name__, "error_repr": repr(e)},
        )
        detail = f"Inference error: {type(e).__name__}: {str(e)}"
        if os.getenv("INFERENCE_DEBUG", "").strip().lower() in ("1", "true", "yes", "on"):
            tb = traceback.format_exc()
            detail = f"{detail}\n\n--- traceback ---\n{tb[-6000:]}"
        raise HTTPException(status_code=500, detail=detail)

    logger.info(
        "inference_complete",
        extra={"duration_s": round(duration, 3), "caption_length": len(caption_text.split())},
    )

    return {
        "caption": caption_text,
        "strategy": strategy,
        "beam_width": beam_width,
        "filename": file.filename,
        "content_type": file.content_type,
    }
