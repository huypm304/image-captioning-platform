from __future__ import annotations

import os
import pickle
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import numpy as np
from PIL import Image

import tensorflow as tf
from tensorflow.keras.utils import pad_sequences

import torch
from transformers import AutoImageProcessor, ViTModel


# =============================================================================
# Paths (override via environment variables)
# =============================================================================
HERE = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ASSETS_DIR = os.environ.get("MODELS_DIR", str(_REPO_ROOT / "models"))

VIT_CAPTION_MODEL_PATH = os.getenv(
    "VIT_CAPTION_MODEL_PATH",
    os.path.join(DEFAULT_ASSETS_DIR, "vit_attention_full_patched.keras"),
)
VIT_PROJ_W_PATH = os.getenv(
    "VIT_PROJ_W_PATH",
    os.path.join(DEFAULT_ASSETS_DIR, "vit_proj_W.npy"),
)
VIT_METADATA_PATH = os.getenv(
    "VIT_METADATA_PATH",
    os.path.join(DEFAULT_ASSETS_DIR, "v2_metadata.pkl"),
)


# =============================================================================
# Keras custom objects (to load the ViT+Attention caption model)
# =============================================================================
keras = tf.keras

KerasEmbedding = keras.layers.Embedding
KerasDense = keras.layers.Dense


class PatchedEmbedding(KerasEmbedding):
    @classmethod
    def from_config(cls, config):
        cfg = dict(config)
        cfg.pop("quantization_config", None)
        return super().from_config(cfg)


class PatchedDense(KerasDense):
    @classmethod
    def from_config(cls, config):
        cfg = dict(config)
        cfg.pop("quantization_config", None)
        return super().from_config(cfg)


class BahdanauAttention(keras.layers.Layer):
    def __init__(self, units: int, **kwargs):
        super().__init__(**kwargs)
        self.units = units
        self.W1 = keras.layers.Dense(units, name="attn_W1")
        self.W2 = keras.layers.Dense(units, name="attn_W2")
        self.V = keras.layers.Dense(1, name="attn_V")

    def call(self, features, hidden):
        orig_dtype = features.dtype
        f = tf.cast(features, tf.float32)
        h = tf.cast(hidden, tf.float32)

        hidden_exp = tf.expand_dims(h, 1)
        score = tf.nn.tanh(self.W1(f) + self.W2(hidden_exp))
        attention_logits = self.V(score)
        attention_weights = tf.nn.softmax(attention_logits, axis=1)
        context_vector = tf.reduce_sum(attention_weights * f, axis=1)

        context_vector = tf.cast(context_vector, orig_dtype)
        attention_weights = tf.cast(attention_weights, orig_dtype)
        return context_vector, attention_weights

    def get_config(self):
        cfg = super().get_config()
        cfg.update({"units": self.units})
        return cfg


CUSTOM_OBJECTS = {
    "Embedding": PatchedEmbedding,
    "keras.layers.Embedding": PatchedEmbedding,
    "keras.layers.core.embedding.Embedding": PatchedEmbedding,
    "keras.src.layers.core.embedding.Embedding": PatchedEmbedding,
    "Dense": PatchedDense,
    "keras.layers.Dense": PatchedDense,
    "keras.layers.core.dense.Dense": PatchedDense,
    "keras.src.layers.core.dense.Dense": PatchedDense,
    "InputLayer": keras.layers.InputLayer,
    "keras.layers.InputLayer": keras.layers.InputLayer,
    "keras.layers.core.input_layer.InputLayer": keras.layers.InputLayer,
    "keras.src.layers.core.input_layer.InputLayer": keras.layers.InputLayer,
    "BahdanauAttention": BahdanauAttention,
    "keras.layers.BahdanauAttention": BahdanauAttention,
}


# =============================================================================
# Metadata
# =============================================================================
@dataclass(frozen=True)
class CaptionMetadata:
    wordtoix: dict[str, int]
    ixtoword: dict[int, str]
    max_len: int


def load_metadata(path: str = VIT_METADATA_PATH) -> CaptionMetadata:
    if not path or not os.path.exists(path):
        raise FileNotFoundError(f"Missing metadata file: {path}")
    meta = pickle.load(open(path, "rb"))
    w2i = meta.get("wordtoix")
    i2w = meta.get("ixtoword")
    ml = meta.get("max_len", meta.get("max_length"))
    if not isinstance(w2i, dict) or not isinstance(i2w, dict) or not isinstance(ml, int):
        raise ValueError("metadata must contain wordtoix, ixtoword, max_len/max_length")
    return CaptionMetadata(wordtoix=w2i, ixtoword=i2w, max_len=ml)


# =============================================================================
# Decoding
# =============================================================================
def greedy_search(model, photo, wordtoix, ixtoword, max_length: int) -> str:
    in_text = "startseq"
    for _ in range(max_length):
        seq = [wordtoix[w] for w in in_text.split() if w in wordtoix]
        seq = pad_sequences([seq], maxlen=max_length, padding="post")
        yhat = model.predict([photo, seq], verbose=0)
        yhat = int(np.argmax(yhat))
        word = ixtoword.get(yhat, "")
        if not word:
            break
        in_text += " " + word
        if word == "endseq":
            break
    return " ".join(in_text.split()[1:-1])


def beam_search(model, photo, wordtoix, ixtoword, max_length: int, beam_width: int = 3) -> str:
    start = wordtoix["startseq"]
    end = wordtoix["endseq"]
    sequences = [[[start], 0.0]]  # [seq, cumulative_neg_log_prob]

    for _ in range(max_length):
        all_candidates: list[list[object]] = []
        for seq, score in sequences:
            if seq[-1] == end:
                all_candidates.append([seq, score])
                continue

            padded = pad_sequences([seq], maxlen=max_length, padding="post")
            yhat = model.predict([photo, padded], verbose=0)[0]
            top_k = np.argsort(yhat)[-beam_width:]
            for word_idx in top_k:
                new_score = float(score) - float(np.log(yhat[word_idx] + 1e-10))
                all_candidates.append([seq + [int(word_idx)], new_score])

        sequences = sorted(all_candidates, key=lambda x: x[1] / (len(x[0]) ** 0.7))[:beam_width]
        if all(s[-1] == end for s, _ in sequences):
            break

    best_seq = sequences[0][0]
    words = [ixtoword.get(i, "") for i in best_seq if i not in [start, end]]
    return " ".join(words)


# =============================================================================
# ViT encoder: PIL -> patches -> projection (196, 256)
# =============================================================================
_VIT_CACHE = {"processor": None, "vit": None}
_PROJ_CACHE: dict[tuple[object, int, int, int], np.ndarray] = {}


def _get_vit():
    if _VIT_CACHE["processor"] is None:
        _VIT_CACHE["processor"] = AutoImageProcessor.from_pretrained("google/vit-base-patch16-224")
    if _VIT_CACHE["vit"] is None:
        _VIT_CACHE["vit"] = ViTModel.from_pretrained("google/vit-base-patch16-224")
        _VIT_CACHE["vit"].eval()
    return _VIT_CACHE["processor"], _VIT_CACHE["vit"]


def _load_or_make_proj_W(proj_w_path: str | None, in_dim: int = 768, out_dim: int = 256, seed: int = 42) -> np.ndarray:
    key = (proj_w_path or "__random__", in_dim, out_dim, seed)
    if key in _PROJ_CACHE:
        return _PROJ_CACHE[key]

    W = None
    if proj_w_path and str(proj_w_path).strip():
        p = str(proj_w_path).strip()
        if os.path.exists(p):
            W = np.load(p)

    if W is None:
        rng = np.random.default_rng(seed)
        W = rng.normal(0, 1.0 / np.sqrt(out_dim), size=(in_dim, out_dim)).astype("float32")

    W = np.asarray(W, dtype="float32")
    _PROJ_CACHE[key] = W
    return W


def encode_pil_image_vit(pil_img: Image.Image, proj_w_path: str = VIT_PROJ_W_PATH) -> np.ndarray:
    processor, vit = _get_vit()

    img = pil_img.convert("RGB")
    inputs = processor(images=img, return_tensors="pt")
    with torch.no_grad():
        outputs = vit(**inputs)

    patches = outputs.last_hidden_state[:, 1:, :].cpu().numpy().astype("float32")[0]  # (196,768)
    W = _load_or_make_proj_W(proj_w_path, in_dim=patches.shape[-1], out_dim=256, seed=42)
    proj = (patches @ W).astype("float32")  # (196,256)
    return proj.reshape(1, proj.shape[0], proj.shape[1])


# =============================================================================
# Keras model loader (cached)
# =============================================================================
_MODEL_CACHE: dict[str, object] = {}


def load_caption_model(path: str = VIT_CAPTION_MODEL_PATH):
    p = (path or "").strip()
    if not p:
        raise ValueError("Empty model path")
    if not os.path.exists(p):
        raise FileNotFoundError(f"Missing model file: {p}")
    if p not in _MODEL_CACHE:
        try:
            _MODEL_CACHE[p] = keras.models.load_model(
                p,
                compile=False,
                safe_mode=False,
                custom_objects=CUSTOM_OBJECTS,
            )
        except TypeError:
            _MODEL_CACHE[p] = keras.models.load_model(p, compile=False, custom_objects=CUSTOM_OBJECTS)
    return _MODEL_CACHE[p]


Strategy = Literal["greedy", "beam"]


def generate_caption(
    image: Image.Image,
    *,
    strategy: Strategy = "beam",
    beam_width: int = 3,
    model_path: str = VIT_CAPTION_MODEL_PATH,
    metadata_path: str = VIT_METADATA_PATH,
    proj_w_path: str = VIT_PROJ_W_PATH,
) -> str:
    if beam_width < 2:
        beam_width = 2

    model = load_caption_model(model_path)
    meta = load_metadata(metadata_path)
    features = encode_pil_image_vit(image, proj_w_path=proj_w_path)

    if strategy == "greedy":
        return greedy_search(model, features, meta.wordtoix, meta.ixtoword, meta.max_len)
    return beam_search(model, features, meta.wordtoix, meta.ixtoword, meta.max_len, beam_width=beam_width)

