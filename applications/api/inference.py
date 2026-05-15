"""
Legacy entrypoint kept for compatibility.

This project now exposes inference via `vit_inference.py` and the FastAPI app in `api.py`.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from vit_inference import generate_caption


def main() -> int:
    parser = argparse.ArgumentParser(description="ViT caption inference (CLI)")
    parser.add_argument("--image", required=True, help="Path to an image file")
    parser.add_argument("--strategy", choices=["beam", "greedy"], default="beam")
    parser.add_argument("--beam-width", type=int, default=3)
    args = parser.parse_args()

    img_path = Path(args.image)
    img = Image.open(img_path).convert("RGB")
    caption = generate_caption(img, strategy=args.strategy, beam_width=args.beam_width)
    print(json.dumps({"caption": caption}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())