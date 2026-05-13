from __future__ import annotations

import logging
import numbers
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
_path = Path(__file__).resolve()
# Repo: .../applications/api/vit_inference.py → parents[2] is repo root.
# Container: /app/vit_inference.py → only parents[0..1]; parents[2] raises IndexError.
try:
    _REPO_ROOT = _path.parents[2]
except IndexError:
    _REPO_ROOT = _path.parent
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


logger = logging.getLogger("vit_inference")


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


def _normalize_ixtoword(raw: dict) -> dict[int, str]:
    """Pickles often store JSON-style string keys ("0","1",…); decoding needs int keys."""
    out: dict[int, str] = {}
    for k, v in raw.items():
        if isinstance(k, (int, np.integer)):
            nk = int(k)
        elif isinstance(k, (float, np.floating)) and float(k).is_integer():
            nk = int(k)
        elif isinstance(k, str) and (k.isdigit() or (k.startswith("-") and k[1:].isdigit())):
            nk = int(k)
        elif isinstance(k, bytes) and k.decode().isdigit():
            nk = int(k.decode())
        else:
            continue
        out[nk] = v.decode("utf-8", errors="replace") if isinstance(v, bytes) else str(v)
    return out


def _as_word_index(v: object) -> int:
    if isinstance(v, numbers.Integral):
        return int(v)
    if isinstance(v, (float, np.floating)) and float(v).is_integer():
        return int(v)
    if isinstance(v, (str, bytes)):
        s = v.decode("utf-8", errors="replace") if isinstance(v, bytes) else v
        return int(float(s)) if "." in s else int(s)
    return int(np.asarray(v).reshape(-1)[0].item())


def _normalize_wordtoix(raw: dict) -> dict[str, int]:
    out: dict[str, int] = {}
    for k, v in raw.items():
        sk = k.decode("utf-8", errors="replace") if isinstance(k, bytes) else str(k)
        out[sk] = _as_word_index(v)
    return out


def load_metadata(path: str = VIT_METADATA_PATH) -> CaptionMetadata:
    if not path or not os.path.exists(path):
        raise FileNotFoundError(f"Missing metadata file: {path}")
    meta = pickle.load(open(path, "rb"))
    w2i_raw = meta.get("wordtoix")
    i2w_raw = meta.get("ixtoword")
    ml = meta.get("max_len", meta.get("max_length"))
    if not isinstance(w2i_raw, dict) or not isinstance(i2w_raw, dict) or ml is None:
        raise ValueError("metadata must contain wordtoix, ixtoword, max_len/max_length")
    if not isinstance(ml, numbers.Integral):
        raise ValueError("max_len / max_length must be an integer")
    w2i = _normalize_wordtoix(w2i_raw)
    i2w = _normalize_ixtoword(i2w_raw)
    if "startseq" not in w2i or "endseq" not in w2i:
        raise ValueError('metadata wordtoix must contain "startseq" and "endseq" tokens')
    return CaptionMetadata(wordtoix=w2i, ixtoword=i2w, max_len=int(ml))


# =============================================================================
# Keras predict (Keras 3 / multi-input checkpoints)
# =============================================================================
def _predict_caption_step(model: object, photo: np.ndarray, seq_batch: np.ndarray) -> np.ndarray:
    """Single decoder forward pass. Tries dict feeds, swapped inputs, extra zero inputs, list, and __call__."""
    names = list(getattr(model, "input_names", None) or [])
    inputs = getattr(model, "inputs", None) or []
    batch = int(np.shape(photo)[0])
    dict_errors: list[str] = []

    def _np_dtype_for_spec(spec: object):
        dt = getattr(spec, "dtype", None)
        name = (getattr(dt, "name", None) or str(dt) or "").lower()
        if "int64" in name:
            return np.int64
        if "int32" in name:
            return np.int32
        if "float64" in name:
            return np.float64
        return np.float32

    def _zeros_for_input(idx: int) -> np.ndarray:
        spec = inputs[idx]
        dims: list[int] = []
        for d_i, dim in enumerate(spec.shape):
            if d_i == 0:
                dims.append(batch)
            elif dim is None:
                dims.append(1)
            else:
                dims.append(int(dim))
        npdt = _np_dtype_for_spec(spec)
        return np.zeros(dims, dtype=npdt)

    def _squeeze_batch(out: object) -> np.ndarray:
        if hasattr(out, "numpy") and callable(out.numpy):
            out = out.numpy()
        out_arr = np.asarray(out)
        if out_arr.ndim >= 2 and out_arr.shape[0] == 1:
            return out_arr[0]
        return out_arr

    def _extras() -> dict[str, np.ndarray]:
        feedx: dict[str, np.ndarray] = {}
        if len(names) > 2 and inputs and len(inputs) >= len(names):
            for idx in range(2, len(names)):
                feedx[names[idx]] = _zeros_for_input(idx)
        return feedx

    if len(names) >= 2 and inputs and len(inputs) >= 2:
        for a, b in ((photo, seq_batch), (seq_batch, photo)):
            base = {names[0]: a, names[1]: b}
            feed = {**base, **_extras()}
            try:
                return _squeeze_batch(model.predict(feed, verbose=0))
            except Exception as e:
                dict_errors.append(f"predict({list(feed.keys())} order=({a is photo})): {type(e).__name__}: {e!r}")
                continue

    err_list: Exception | None = None
    try:
        return _squeeze_batch(model.predict([photo, seq_batch], verbose=0))
    except Exception as e:
        err_list = e

    err_call: Exception | None = None
    try:
        y = model((photo, seq_batch), training=False)
        return _squeeze_batch(y)
    except Exception as e:
        err_call = e

    try:
        y = model([photo, seq_batch], training=False)
        return _squeeze_batch(y)
    except Exception as e_call2:
        hint = "; ".join(dict_errors[-6:]) if dict_errors else "(no dict attempts)"
        raise RuntimeError(
            f"Caption model forward failed (input_names={names!r}). Dict: {hint}. "
            f"List predict: {err_list!r}. __call__(tuple): {err_call!r}. __call__(list): {e_call2!r}."
        ) from e_call2


# =============================================================================
# Decoding
# =============================================================================
def _flatten_vocab_logits(yhat: np.ndarray) -> np.ndarray:
    """Model may return (1, vocab), (vocab,), or higher-D; beam/greedy need a 1-D probability vector."""
    a = np.asarray(yhat, dtype=np.float64).reshape(-1)
    if a.size == 0:
        raise ValueError("empty model output logits")
    return a


def greedy_search(model, photo, wordtoix, ixtoword, max_length: int) -> str:
    in_text = "startseq"
    for _ in range(max_length):
        seq = [wordtoix[w] for w in in_text.split() if w in wordtoix]
        seq = pad_sequences([seq], maxlen=max_length, padding="post")
        yhat = _flatten_vocab_logits(_predict_caption_step(model, photo, seq))
        yhat_i = int(np.argmax(yhat))
        word = ixtoword.get(yhat_i, "")
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
            yhat = _flatten_vocab_logits(_predict_caption_step(model, photo, padded))
            bw = min(beam_width, yhat.size)
            top_k = np.argsort(yhat)[-bw:] if bw > 0 else np.array([], dtype=np.int64)
            for word_idx in top_k:
                wi = int(word_idx)
                new_score = float(score) - float(np.log(float(yhat[wi]) + 1e-10))
                all_candidates.append([seq + [wi], new_score])

        if not all_candidates:
            break
        sequences = sorted(all_candidates, key=lambda x: x[1] / (len(x[0]) ** 0.7))[:beam_width]
        if not sequences:
            break
        if all(s[-1] == end for s, _ in sequences):
            break

    if not sequences:
        return ""
    best_seq = sequences[0][0]
    words = [
        ixtoword.get(int(i), "")
        for i in best_seq
        if int(i) not in (int(start), int(end))
    ]
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
        m = _MODEL_CACHE[p]
        inames = getattr(m, "input_names", None)
        n_in = len(getattr(m, "inputs", None) or [])
        logger.info("caption_model_ready", extra={"path": p, "input_names": inames, "n_inputs": n_in})
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
    try:
        return beam_search(model, features, meta.wordtoix, meta.ixtoword, meta.max_len, beam_width=beam_width)
    except Exception as e:
        logger.warning("beam_search_failed_using_greedy", extra={"error": repr(e)})
        return greedy_search(model, features, meta.wordtoix, meta.ixtoword, meta.max_len)

