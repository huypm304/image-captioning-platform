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
    return {"status": "ok"}


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
