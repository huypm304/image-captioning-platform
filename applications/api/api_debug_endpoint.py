# This is the /debug endpoint code to add to api.py
# Insert this after the @app.get("/health") function

@app.get("/debug")
def debug():
    """Diagnostic endpoint: check startup errors, model files, and paths without kubectl."""
    from pathlib import Path

    models_dir = os.getenv("MODELS_DIR", "/models")
    vit_model_path = os.getenv("VIT_CAPTION_MODEL_PATH", "")
    vit_proj_path = os.getenv("VIT_PROJ_W_PATH", "")
    vit_meta_path = os.getenv("VIT_METADATA_PATH", "")

    def file_status(path: str) -> dict:
        p = Path(path)
        if not path:
            return {"path": path, "exists": False, "size_mb": None}
        if not p.exists():
            return {"path": path, "exists": False, "is_file": False, "size_mb": None}
        return {
            "path": path,
            "exists": True,
            "is_file": p.is_file(),
            "size_mb": round(p.stat().st_size / (1024 * 1024), 2) if p.is_file() else None,
        }

    return {
        "startup_error": str(_startup_error) if _startup_error else None,
        "models_ready": _startup_error is None,
        "models_dir": models_dir,
        "models_dir_exists": Path(models_dir).exists(),
        "file_status": {
            "vit_caption_model": file_status(vit_model_path),
            "vit_proj_w": file_status(vit_proj_path),
            "vit_metadata": file_status(vit_meta_path),
        },
    }
