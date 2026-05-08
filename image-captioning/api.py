from __future__ import annotations

from io import BytesIO

from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError

from vit_inference import generate_caption


app = FastAPI(title="Image Captioning API (ViT)")


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.post("/caption")
async def caption(
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

    try:
        caption_text = generate_caption(img, strategy=strategy, beam_width=beam_width)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")

    return {
        "caption": caption_text,
        "strategy": strategy,
        "beam_width": beam_width,
        "filename": file.filename,
        "content_type": file.content_type,
    }

