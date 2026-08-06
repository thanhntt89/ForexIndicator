#!/usr/bin/env python3
"""
model_registry.py — XGBoost model version history, rollback, and shadow tracking

Every successful retrain is archived as a single-model binary snapshot under
tools/model_history/<symbol>_<tf>/. Each (symbol, tf) key has a manifest
tracking version roles:

    champion  — exactly one; currently live, spliced into XGBModels.bin
    shadow    — at most one; candidate awaiting manual promotion
    archived  — any number; historical versions kept for rollback

Gated promotion (Sprint 4 decision): a passing retrain becomes the shadow,
never auto-overwrites the champion. "Promote shadow" and "rollback champion"
are both just "point champion at version X" — same manifest, same code path.

Called by xgb_service.py. Reuses quantedge_xgboost_train.serialize_model_block()
for identical byte-packing between fresh trains and archived-version reads.
"""

import json
import os
import struct
import sys
import tempfile
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
HISTORY_DIR = SCRIPT_DIR / "model_history"

sys.path.insert(0, str(SCRIPT_DIR))
import quantedge_xgboost_train as trainer  # noqa: E402

XGB_BIN_MAGIC = trainer.XGB_BIN_MAGIC
XGB_BIN_VERSION = trainer.XGB_BIN_VERSION
N_FEATURES_BIN = trainer.N_FEATURES_BIN


def _key_dir(symbol: str, tf: str) -> Path:
    d = HISTORY_DIR / f"{symbol}_{tf}"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _manifest_path(symbol: str, tf: str) -> Path:
    return _key_dir(symbol, tf) / "manifest.json"


def _load_manifest(symbol: str, tf: str) -> dict:
    path = _manifest_path(symbol, tf)
    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"versions": []}


def _save_manifest(symbol: str, tf: str, manifest: dict):
    path = _manifest_path(symbol, tf)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    os.replace(tmp_path, str(path))


def _next_version_id(manifest: dict) -> str:
    n = len(manifest["versions"]) + 1
    return f"v{n}_{int(time.time())}"


def archive_version(symbol: str, tf: str, results: dict, role: str = "shadow") -> str:
    """Serialize results to a standalone .bin snapshot and register it in the manifest.

    role="shadow": demotes any existing shadow to "archived" first (at most one shadow).
    role="champion": demotes any existing champion to "archived" first (at most one champion).
    Returns the new version_id.
    """
    if role not in ("champion", "shadow", "archived"):
        raise ValueError(f"Invalid role: {role}")

    manifest = _load_manifest(symbol, tf)
    version_id = _next_version_id(manifest)

    block, n_trees, n_nodes = trainer.serialize_model_block(results, symbol, tf)
    bin_path = _key_dir(symbol, tf) / f"{version_id}.bin"
    with open(bin_path, "wb") as f:
        f.write(block)

    if role in ("champion", "shadow"):
        for v in manifest["versions"]:
            if v["role"] == role:
                v["role"] = "archived"

    manifest["versions"].append({
        "version_id": version_id,
        "timestamp": int(time.time()),
        "brier": round(float(results["oos_brier"]), 4),
        "auc": round(float(results["oos_auc"]), 4),
        "n_trees": n_trees,
        "n_nodes": n_nodes,
        "file": f"{version_id}.bin",
        "role": role,
    })
    _save_manifest(symbol, tf, manifest)
    return version_id


def list_versions(symbol: str, tf: str) -> list:
    """Return all versions for a key, most recent first."""
    manifest = _load_manifest(symbol, tf)
    return sorted(manifest["versions"], key=lambda v: v["timestamp"], reverse=True)


def get_champion(symbol: str, tf: str) -> dict:
    """Return the champion version dict, or None if this key has never been trained."""
    for v in _load_manifest(symbol, tf)["versions"]:
        if v["role"] == "champion":
            return v
    return None


def get_shadow(symbol: str, tf: str) -> dict:
    """Return the shadow version dict, or None if no candidate is pending."""
    for v in _load_manifest(symbol, tf)["versions"]:
        if v["role"] == "shadow":
            return v
    return None


def _set_role(symbol: str, tf: str, version_id: str, new_role: str):
    manifest = _load_manifest(symbol, tf)
    for v in manifest["versions"]:
        if v["role"] == new_role and v["version_id"] != version_id:
            v["role"] = "archived"
    found = False
    for v in manifest["versions"]:
        if v["version_id"] == version_id:
            v["role"] = new_role
            found = True
    if not found:
        raise ValueError(f"Version {version_id} not found for {symbol}_{tf}")
    _save_manifest(symbol, tf, manifest)


def promote_shadow_to_champion(symbol: str, tf: str) -> str:
    """Point champion at the current shadow version. Returns the promoted version_id."""
    shadow = get_shadow(symbol, tf)
    if shadow is None:
        raise ValueError(f"No shadow version to promote for {symbol}_{tf}")
    _set_role(symbol, tf, shadow["version_id"], "champion")
    return shadow["version_id"]


def rollback_champion(symbol: str, tf: str, version_id: str):
    """Point champion at an arbitrary archived version (or the current shadow)."""
    _set_role(symbol, tf, version_id, "champion")


def all_keys() -> list:
    """Return all (symbol, tf) keys that have a manifest."""
    if not HISTORY_DIR.is_dir():
        return []
    keys = []
    for entry in HISTORY_DIR.iterdir():
        if not entry.is_dir():
            continue
        if not (entry / "manifest.json").exists():
            continue
        parts = entry.name.rsplit("_", 1)
        if len(parts) == 2:
            keys.append((parts[0], parts[1]))
    return keys


def _read_block_bytes(symbol: str, tf: str, version: dict) -> bytes:
    bin_path = _key_dir(symbol, tf) / version["file"]
    with open(bin_path, "rb") as f:
        return f.read()


def assemble_role_binary(role: str, output_path: str):
    """Splice every key's version with the given role into one merged multi-model
    binary file (same header format as trainer.export_model_binary()), without
    re-training. Used to (re)build XGBModels.bin (role="champion") or
    XGBModels_shadow.bin (role="shadow") purely from archived bytes.

    Keys with no version in the requested role are skipped.
    """
    if role not in ("champion", "shadow"):
        raise ValueError(f"assemble_role_binary only supports champion/shadow, got: {role}")

    blocks = []
    for symbol, tf in sorted(all_keys()):
        version = get_champion(symbol, tf) if role == "champion" else get_shadow(symbol, tf)
        if version is None:
            continue
        blocks.append(_read_block_bytes(symbol, tf, version))

    if not blocks:
        return False

    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.isdir(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    timestamp = int(time.time())
    tmp_fd, tmp_path = tempfile.mkstemp(dir=output_dir, suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "wb") as f:
            f.write(struct.pack("<iiiii",
                XGB_BIN_MAGIC, XGB_BIN_VERSION, len(blocks),
                timestamp, N_FEATURES_BIN))
            f.write(struct.pack("<d", 0.0))  # reserved
            for block in blocks:
                f.write(block)
        os.replace(tmp_path, output_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

    return True
