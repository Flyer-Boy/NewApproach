"""
Embedding providers for the knowledge store. Chosen with the EMBEDDINGS environment variable (or --embeddings):

  none            no vectors; full-text + graph + past-questions retrieval only (default)
  voyage-4-nano   Voyage AI's open-weight model, run locally via sentence-transformers. No API key.
                  ~346M parameters, ~700 MB download on first use (Hugging Face: voyageai/voyage-4-nano).
                  Loads with trust_remote_code=True (the model ships its own code) -- only from that repo.
                  pip install sentence-transformers torch
  voyage-api      Voyage AI hosted API (voyage-4-lite by default; VOYAGE_MODEL to change). Needs VOYAGE_API_KEY.
                  pip install voyageai
  hash            deterministic bag-of-words hashing. For offline tests only -- no semantic quality.

Vectors are L2-normalized; the relate vector index uses cosine similarity. Voyage 4 models share one embedding
space, so voyage-4-nano (local) and voyage-4-lite (API) vectors are comparable.
"""
from __future__ import annotations

import hashlib
import math
import os
import re

DEFAULT_DIMS = 1024


class Embedder:
    name = "none"
    dims = 0

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        raise NotImplementedError

    def embed_query(self, text: str) -> list[float]:
        raise NotImplementedError


def _normalize(v):
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]


class Voyage4NanoLocal(Embedder):
    name = "voyage-4-nano"

    def __init__(self, dims: int = DEFAULT_DIMS):
        try:
            from sentence_transformers import SentenceTransformer
        except ImportError as exc:
            raise SystemExit("EMBEDDINGS=voyage-4-nano needs: pip install sentence-transformers torch") from exc
        import time
        self.dims = dims
        t0 = time.time()
        print("Loading voyageai/voyage-4-nano (first time: ~700 MB download from Hugging Face)...", flush=True)
        # truncate_dim: Matryoshka embeddings -- the leading dims are a valid smaller embedding (1024 = Voyage default)
        self.model = SentenceTransformer("voyageai/voyage-4-nano", trust_remote_code=True, truncate_dim=dims)
        print(f"Model loaded in {time.time() - t0:.0f}s on {self.model.device}.", flush=True)

    def embed_documents(self, texts):
        vecs = self.model.encode_document(texts, normalize_embeddings=True, show_progress_bar=len(texts) > 8)
        return [list(map(float, v)) for v in vecs]

    def embed_query(self, text):
        return list(map(float, self.model.encode_query([text], normalize_embeddings=True)[0]))


class VoyageAPI(Embedder):
    name = "voyage-api"

    def __init__(self, dims: int = DEFAULT_DIMS):
        try:
            import voyageai
        except ImportError as exc:
            raise SystemExit("EMBEDDINGS=voyage-api needs: pip install voyageai (and VOYAGE_API_KEY)") from exc
        self.client = voyageai.Client()
        self.model = os.environ.get("VOYAGE_MODEL", "voyage-4-lite")
        self.dims = dims

    def _embed(self, texts, input_type):
        r = self.client.embed(texts, model=self.model, input_type=input_type, output_dimension=self.dims)
        return [_normalize(list(map(float, v))) for v in r.embeddings]

    def embed_documents(self, texts):
        out = []
        for i in range(0, len(texts), 64):
            out.extend(self._embed(texts[i:i + 64], "document"))
        return out

    def embed_query(self, text):
        return self._embed([text], "query")[0]


class HashEmbedder(Embedder):
    """Offline test stand-in: hashed word + word-prefix features. Similar wording -> similar vectors; no semantics."""
    name = "hash"

    def __init__(self, dims: int = 256):
        self.dims = dims

    def _vec(self, text):
        v = [0.0] * self.dims
        for w in re.findall(r"[a-z0-9]+", text.lower()):
            for feat in (w, w[:5]):
                h = int(hashlib.md5(feat.encode()).hexdigest(), 16)
                v[h % self.dims] += 1.0 if (h >> 8) & 1 else -1.0
        return _normalize(v)

    def embed_documents(self, texts):
        return [self._vec(t) for t in texts]

    def embed_query(self, text):
        return self._vec(text)


def get_embedder(name: str | None = None) -> Embedder | None:
    name = (name or os.environ.get("EMBEDDINGS") or "none").strip().lower()
    if name in ("", "none", "off"):
        return None
    if name == "voyage-4-nano":
        return Voyage4NanoLocal()
    if name == "voyage-api":
        return VoyageAPI()
    if name == "hash":
        return HashEmbedder()
    raise SystemExit(f"Unknown EMBEDDINGS={name!r}: use none, voyage-4-nano, voyage-api or hash")


def template_text(title: str, description: str, workflows: list[str], concepts: list[str]) -> str:
    """The text embedded for a template: what it answers, in business words plus the model's own names."""
    parts = [title, description]
    if workflows:
        parts.append("Workflow: " + ", ".join(workflows))
    if concepts:
        parts.append("Uses: " + ", ".join(concepts))
    return "\n".join(p for p in parts if p)
