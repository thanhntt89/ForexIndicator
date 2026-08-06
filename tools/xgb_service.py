#!/usr/bin/env python3
"""
xgb_service.py — XGBoost Auto-Training Service (System Tray)

Runs as a background process with a Windows system tray icon.
Periodically scans MT4/MT5 terminal CSV data, trains XGBoost models
per symbol+TF when sufficient data exists, and exports model data.

V12.2: Default output is binary (XGBModels.bin) to Common/Files/ for
runtime loading — indicator auto-reloads without recompile.
Legacy: Set "output_format": "mql" in config to export MQL source code.

Usage:
    python xgb_service.py                 # normal (tray icon)
    python xgb_service.py --no-tray       # headless mode (logging only)
    python xgb_service.py --train-now     # single scan+train, then exit
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

try:
    from plyer import notification as plyer_notify
    HAS_PLYER = True
except ImportError:
    HAS_PLYER = False

try:
    import pystray
    from PIL import Image, ImageDraw, ImageFont
    HAS_TRAY = True
except ImportError:
    HAS_TRAY = False

# ─── Paths ──────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_DIR = SCRIPT_DIR.parent
CONFIG_PATH = SCRIPT_DIR / "xgb_config.json"
STATE_PATH = SCRIPT_DIR / ".xgb_state.json"
LOG_PATH = SCRIPT_DIR / "xgb_service.log"
TRAINER_SCRIPT = SCRIPT_DIR / "quantedge_xgboost_train.py"
DEFAULT_OUTPUT_MQL = PROJECT_DIR / "Include" / "QuantEdge" / "AI" / "XGBModel.mqh"
LOCK_PATH = SCRIPT_DIR / ".xgb_service.lock"

APPDATA_PATH = Path(os.environ.get("APPDATA", ""))
MT_TERMINAL_BASE = APPDATA_PATH / "MetaQuotes" / "Terminal"
COMMON_FILES_DIR = MT_TERMINAL_BASE / "Common" / "Files"
DEFAULT_OUTPUT_BIN = COMMON_FILES_DIR / "QuantEdge_RSI" / "XGBModels.bin"
DEFAULT_OUTPUT_BIN_SHADOW = COMMON_FILES_DIR / "QuantEdge_RSI" / "XGBModels_shadow.bin"

TF_TO_PERIOD = {
    "M1": 1, "M5": 5, "M15": 15, "M30": 30,
    "H1": 60, "H4": 240, "D1": 1440, "W1": 10080, "MN1": 43200,
}

# ─── Logging ────────────────────────────────────────────────────────
logger = logging.getLogger("xgb_service")
logger.setLevel(logging.DEBUG)

file_handler = logging.FileHandler(LOG_PATH, encoding="utf-8")
file_handler.setLevel(logging.DEBUG)
file_handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
logger.addHandler(file_handler)

console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
logger.addHandler(console_handler)


# ─── Single-Instance Lock ────────────────────────────────────────────
_lock_handle = None


def acquire_lock() -> bool:
    """Acquire an exclusive file lock. Returns False if another instance is running."""
    global _lock_handle
    if sys.platform == "win32":
        import msvcrt
        try:
            _lock_handle = open(LOCK_PATH, "w")
            msvcrt.locking(_lock_handle.fileno(), msvcrt.LK_NBLCK, 1)
            _lock_handle.write(str(os.getpid()))
            _lock_handle.flush()
            return True
        except (OSError, IOError):
            if _lock_handle:
                _lock_handle.close()
                _lock_handle = None
            return False
    else:
        import fcntl
        try:
            _lock_handle = open(LOCK_PATH, "w")
            fcntl.flock(_lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            _lock_handle.write(str(os.getpid()))
            _lock_handle.flush()
            return True
        except (OSError, IOError):
            if _lock_handle:
                _lock_handle.close()
                _lock_handle = None
            return False


def release_lock():
    global _lock_handle
    if _lock_handle:
        try:
            _lock_handle.close()
        except Exception:
            pass
        _lock_handle = None
    if LOCK_PATH.exists():
        try:
            LOCK_PATH.unlink()
        except OSError:
            pass


# ─── Config ─────────────────────────────────────────────────────────
def load_config() -> dict:
    if not CONFIG_PATH.exists():
        logger.error(f"Config not found: {CONFIG_PATH}")
        sys.exit(1)
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def load_state() -> dict:
    if STATE_PATH.exists():
        try:
            with open(STATE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"models": {}}


def save_state(state: dict):
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, default=str)


# ─── Terminal Discovery ─────────────────────────────────────────────
def get_data_dirs(config: dict) -> list:
    """Build list of QuantEdge_RSI_Logs directories across all configured terminals."""
    dirs = []
    log_folder = config.get("log_folder_name", "QuantEdge_RSI_Logs")

    for tid in config.get("mt4_terminal_ids", []):
        d = MT_TERMINAL_BASE / tid / "MQL4" / "Files" / log_folder
        if d.is_dir():
            dirs.append(str(d))
        else:
            logger.debug(f"MT4 dir not found: {d}")

    for tid in config.get("mt5_terminal_ids", []):
        d = MT_TERMINAL_BASE / tid / "MQL5" / "Files" / log_folder
        if d.is_dir():
            dirs.append(str(d))
        else:
            logger.debug(f"MT5 dir not found: {d}")

    return dirs


# ─── Inventory ───────────────────────────────────────────────────────
def scan_inventory(data_dirs: list, timeframes: list) -> dict:
    """Scan CSV files and count resolved outcomes per (symbol, tf).
    Returns {(symbol, tf): resolved_count}."""
    import glob
    import re
    counts = {}
    for data_dir in data_dirs:
        for f in glob.glob(os.path.join(data_dir, "outcomes_*.csv")):
            fname = os.path.basename(f)
            m = re.match(r"outcomes_(.+)_([A-Z0-9]+)_\d{4}\.csv", fname)
            if not m:
                continue
            symbol, tf = m.group(1), m.group(2)
            if tf not in timeframes:
                continue
            try:
                import pandas as pd
                df = pd.read_csv(f)
                resolved = len(df[df["OUTCOME"] != "PENDING"])
            except Exception:
                resolved = 0
            key = f"{symbol}_{tf}"
            counts[key] = counts.get(key, 0) + resolved
    return counts


# ─── Training ────────────────────────────────────────────────────────
def should_train(key: str, current_count: int, state: dict, config: dict) -> tuple:
    """Check if a symbol+TF pair should be trained. Returns (should_train, reason)."""
    min_signals = config.get("min_signals", 150)
    min_retrain = config.get("min_new_signals_retrain", 50)

    if current_count < min_signals:
        return False, f"only {current_count}/{min_signals} signals"

    model_state = state.get("models", {}).get(key, {})
    last_count = model_state.get("trained_on_signals", 0)

    if last_count == 0:
        return True, f"first train ({current_count} signals)"

    new_signals = current_count - last_count
    if new_signals >= min_retrain:
        return True, f"{new_signals} new signals since last train"

    return False, f"waiting for {min_retrain - new_signals} more new signals"


def run_training(symbol: str, tf: str, data_dirs: list, output_path: str) -> dict:
    """Run quantedge_xgboost_train.py as subprocess for one symbol+TF."""
    cmd = [
        sys.executable, str(TRAINER_SCRIPT),
        "--data-dir", *data_dirs,
        "--symbol", symbol,
        "--tf", tf,
        "--output", output_path,
        "--json-output",
    ]

    logger.info(f"Training {symbol} {tf}...")
    logger.debug(f"Command: {' '.join(cmd[:6])}...")

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=600, encoding="utf-8"
        )
    except subprocess.TimeoutExpired:
        logger.error(f"Training {symbol} {tf} timed out (10min)")
        return {"symbol": symbol, "tf": tf, "status": "timeout"}
    except Exception as e:
        logger.error(f"Training {symbol} {tf} failed: {e}")
        return {"symbol": symbol, "tf": tf, "status": "error", "message": str(e)}

    if result.stderr:
        for line in result.stderr.strip().split("\n"):
            if line.strip():
                logger.debug(f"  stderr: {line}")

    # Parse JSON from last line of stdout
    stdout_lines = result.stdout.strip().split("\n")
    json_line = None
    for line in reversed(stdout_lines):
        line = line.strip()
        if line.startswith("{"):
            json_line = line
            break

    if json_line:
        try:
            return json.loads(json_line)
        except json.JSONDecodeError:
            pass

    # Log non-JSON output for debugging
    for line in stdout_lines[-20:]:
        if line.strip():
            logger.info(f"  train: {line.strip()}")

    status = "pass" if result.returncode == 0 else "fail"
    return {"symbol": symbol, "tf": tf, "status": status}


def assemble_multi_model(trained_models: list, output_path: str):
    """Assemble multiple per-symbol+TF .mqh files into one unified XGBModel.mqh.

    Each model was already exported as a standalone file. We re-import their
    quantedge_xgboost_train module and use export_multi_model().
    """
    # Import quantedge_xgboost_train for the multi-model assembler
    sys.path.insert(0, str(SCRIPT_DIR))
    try:
        import importlib
        import quantedge_xgboost_train as trainer
        importlib.reload(trainer)
    except ImportError:
        logger.error("Cannot import quantedge_xgboost_train.py for multi-model assembly")
        return

    logger.info(f"Assembling {len(trained_models)} models into {output_path}")

    # Re-train each model to get the model objects (subprocess already validated them)
    model_list = []
    data_dirs = trained_models[0]["data_dirs"]

    for tm in trained_models:
        symbol = tm["symbol"]
        tf = tm["tf"]
        df = trainer.load_and_merge(data_dirs, symbol, tf)
        if df.empty:
            continue
        if "SIGNAL_TIME" in df.columns:
            df = df.sort_values("SIGNAL_TIME").reset_index(drop=True)
        df, feature_cols = trainer.engineer_features(df)
        results = trainer.train_and_validate(df, feature_cols)
        if results is None:
            continue
        model_list.append((results, symbol, tf))

    if model_list:
        trainer.export_multi_model(model_list, output_path)
        logger.info(f"Multi-model assembly complete: {len(model_list)} models")
    else:
        logger.warning("No models assembled — all re-training failed")

    sys.path.pop(0)


def archive_newly_trained(trained_models: list, auto_promote: bool) -> int:
    """Re-fit each newly-passing key once (in-process, to get a live model object —
    the training subprocess already validated it but didn't cross the process
    boundary) and archive it into model_registry. role="champion" if auto_promote
    (restores old V12.1/V12.2 direct-overwrite behavior), else role="shadow"
    (gated — champion untouched until a manual promotion).

    Returns the number of keys successfully archived.
    """
    sys.path.insert(0, str(SCRIPT_DIR))
    try:
        import importlib
        import quantedge_xgboost_train as trainer
        importlib.reload(trainer)
        import model_registry
        importlib.reload(model_registry)
    except ImportError as e:
        logger.error(f"Cannot import trainer/model_registry for archival: {e}")
        sys.path.pop(0)
        return 0

    archived = 0
    role = "champion" if auto_promote else "shadow"

    for tm in trained_models:
        symbol = tm["symbol"]
        tf = tm["tf"]
        data_dirs = tm["data_dirs"]
        df = trainer.load_and_merge(data_dirs, symbol, tf)
        if df.empty:
            continue
        if "SIGNAL_TIME" in df.columns:
            df = df.sort_values("SIGNAL_TIME").reset_index(drop=True)
        df, feature_cols = trainer.engineer_features(df)
        results = trainer.train_and_validate(df, feature_cols)
        if results is None:
            continue
        version_id = model_registry.archive_version(symbol, tf, results, role=role)
        logger.info(f"  {symbol}_{tf}: archived as {role} ({version_id})")
        archived += 1

    sys.path.pop(0)
    return archived


def rebuild_merged_binaries(champion_path: str, shadow_path: str):
    """Splice every key's champion/shadow version into their merged binary files,
    purely from already-archived bytes — no re-training. Champion file is only
    rewritten when its content actually changes (new archival with role=champion,
    or an explicit promote/rollback), matching the gated-promotion design.
    """
    sys.path.insert(0, str(SCRIPT_DIR))
    try:
        import importlib
        import model_registry
        importlib.reload(model_registry)
    except ImportError as e:
        logger.error(f"Cannot import model_registry for binary assembly: {e}")
        sys.path.pop(0)
        return

    wrote_champion = model_registry.assemble_role_binary("champion", champion_path)
    wrote_shadow = model_registry.assemble_role_binary("shadow", shadow_path)
    sys.path.pop(0)

    if wrote_champion:
        logger.info(f"XGBModels.bin rebuilt from registry: {champion_path}")
    if wrote_shadow:
        logger.info(f"XGBModels_shadow.bin rebuilt from registry: {shadow_path}")


# ─── Notifications ───────────────────────────────────────────────────
def notify(title: str, message: str):
    logger.info(f"NOTIFY: {title} — {message}")
    if HAS_PLYER:
        try:
            plyer_notify.notify(
                title=title,
                message=message,
                app_name="XGB Service",
                timeout=10,
            )
        except Exception as e:
            logger.debug(f"Notification failed: {e}")


# ─── Core Scan+Train Loop ────────────────────────────────────────────
def scan_and_train(config: dict, state: dict, force: bool = False) -> dict:
    """Main scan+train cycle. Returns updated state."""
    data_dirs = get_data_dirs(config)
    if not data_dirs:
        logger.warning("No terminal data directories found. Check xgb_config.json terminal IDs.")
        return state

    timeframes = config.get("timeframes", ["H1", "H4"])
    logger.info(f"Scanning {len(data_dirs)} directories for TFs: {timeframes}")

    counts = scan_inventory(data_dirs, timeframes)
    if not counts:
        logger.info("No outcome data found yet.")
        return state

    logger.info(f"Found {len(counts)} symbol+TF pairs with data")
    for key, cnt in sorted(counts.items()):
        logger.info(f"  {key}: {cnt} resolved signals")

    output_format = config.get("output_format", "bin")
    output_dir = config.get("output_dir", "auto")
    if output_dir == "auto":
        if output_format == "bin":
            output_path = str(DEFAULT_OUTPUT_BIN)
        else:
            output_path = str(DEFAULT_OUTPUT_MQL)
    else:
        output_path = output_dir

    trained_this_round = []

    for key, current_count in sorted(counts.items()):
        parts = key.rsplit("_", 1)
        if len(parts) != 2:
            continue
        symbol, tf = parts

        if force:
            do_train, reason = True, "forced"
        else:
            do_train, reason = should_train(key, current_count, state, config)

        if not do_train:
            logger.debug(f"  {key}: skip — {reason}")
            continue

        logger.info(f"  {key}: will train — {reason}")

        # Train to a temp file first
        temp_output = str(SCRIPT_DIR / f"XGBModel_{key}.mqh")
        result = run_training(symbol, tf, data_dirs, temp_output)

        if result.get("status") == "pass":
            brier = result.get("brier", "?")
            auc = result.get("auc", "?")
            logger.info(f"  {key}: PASS Brier={brier}, AUC={auc}")
            state.setdefault("models", {})[key] = {
                "trained_on_signals": current_count,
                "last_train": datetime.now().isoformat(),
                "brier": brier,
                "auc": auc,
                "status": "pass",
            }
            trained_this_round.append({
                "symbol": symbol, "tf": tf, "temp_file": temp_output,
                "data_dirs": data_dirs, "brier": brier, "auc": auc,
            })
        elif result.get("status") == "skip":
            logger.info(f"  {key}: skipped — {result.get('message', '')}")
        else:
            msg = result.get("message", "validation failed")
            brier = result.get("brier", "?")
            logger.info(f"  {key}: FAIL Brier={brier} — {msg}")
            state.setdefault("models", {})[key] = {
                "trained_on_signals": current_count,
                "last_attempt": datetime.now().isoformat(),
                "brier": brier,
                "status": "fail",
                "message": msg,
            }

    # Archive only keys that trained this round (registry already holds bytes
    # for every previously-passing key — no need to re-train those every cycle).
    if trained_this_round and output_format == "bin":
        try:
            auto_promote = config.get("auto_promote", False)
            n_archived = archive_newly_trained(trained_this_round, auto_promote)
            rebuild_merged_binaries(output_path, str(DEFAULT_OUTPUT_BIN_SHADOW))

            passed = [t for t in trained_this_round]
            summary_parts = [f"{t['symbol']} {t['tf']} Brier={t['brier']}" for t in passed]
            summary = ", ".join(summary_parts)
            if auto_promote:
                notify(
                    f"XGB: {n_archived} model(s) promoted to champion",
                    f"{summary}\nModels auto-loaded, no recompile needed."
                )
            else:
                notify(
                    f"XGB: {n_archived} model(s) archived as shadow",
                    f"{summary}\nUse tray > Promote Shadow -> Champion to go live."
                )
        except Exception as e:
            logger.error(f"Model archival/assembly failed: {e}")
    elif trained_this_round and output_format != "bin":
        try:
            all_passing = []
            for key, ms in state.get("models", {}).items():
                if ms.get("status") == "pass":
                    parts = key.rsplit("_", 1)
                    if len(parts) == 2:
                        all_passing.append({"symbol": parts[0], "tf": parts[1], "data_dirs": data_dirs})
            assemble_multi_model(all_passing, output_path)
            logger.info(f"XGBModel.mqh updated with {len(all_passing)} models")
            notify(
                f"XGB: {len(trained_this_round)} model(s) updated - Compile F7",
                "Open MetaEditor > F7 to apply."
            )
        except Exception as e:
            logger.error(f"Model assembly failed: {e}")

    # Temp per-key files from run_training() are superseded by registry archival
    for tm in trained_this_round:
        temp = tm.get("temp_file", "")
        if os.path.exists(temp):
            try:
                os.remove(temp)
            except OSError:
                pass

    state["last_scan"] = datetime.now().isoformat()
    save_state(state)
    return state


# ─── Tray Icon ───────────────────────────────────────────────────────
def create_icon_image(active_models: int = 0) -> "Image":
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Gold background when models active, dark gold when idle
    bg_color = (218, 165, 32) if active_models > 0 else (184, 134, 11)
    draw.rounded_rectangle([2, 2, 62, 62], radius=10, fill=bg_color)

    try:
        font = ImageFont.truetype("arialbd.ttf", 28)
        font_sm = ImageFont.truetype("arial.ttf", 14)
    except OSError:
        try:
            font = ImageFont.truetype("arial.ttf", 28)
            font_sm = ImageFont.truetype("arial.ttf", 14)
        except OSError:
            font = ImageFont.load_default()
            font_sm = font

    draw.text((6, 4), "XG", fill="white", font=font)
    if active_models > 0:
        draw.text((20, 40), str(active_models), fill="white", font=font_sm)
    else:
        draw.text((16, 40), "...", fill=(255, 255, 255, 160), font=font_sm)

    return img


def get_status_text(state: dict) -> str:
    models = state.get("models", {})
    if not models:
        return "No models trained yet.\nService is scanning for data..."

    lines = [f"{'Key':<20} {'Signals':>8} {'Brier':>8} {'Status':>8} {'Last Train':<20}"]
    lines.append("-" * 70)
    for key, ms in sorted(models.items()):
        sig = ms.get("trained_on_signals", 0)
        brier = ms.get("brier", "?")
        status = ms.get("status", "?")
        last = ms.get("last_train", ms.get("last_attempt", "never"))
        if isinstance(last, str) and len(last) > 16:
            last = last[:16]
        brier_str = f"{brier:.4f}" if isinstance(brier, (int, float)) else str(brier)
        lines.append(f"{key:<20} {sig:>8} {brier_str:>8} {status:>8} {last:<20}")

    last_scan = state.get("last_scan", "never")
    lines.append(f"\nLast scan: {last_scan}")
    return "\n".join(lines)


class TrayService:
    def __init__(self, config: dict):
        self.config = config
        self.state = load_state()
        self.running = True
        self.scan_thread = None
        self.icon = None

    def start(self):
        if not HAS_TRAY:
            logger.error("pystray/Pillow not installed. Run: pip install pystray Pillow")
            sys.exit(1)

        active = sum(1 for m in self.state.get("models", {}).values()
                     if m.get("status") == "pass")
        image = create_icon_image(active)

        menu = pystray.Menu(
            pystray.MenuItem("Train Now", self.on_train_now),
            pystray.MenuItem("Status", self.on_status),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Promote Shadow -> Champion", self.on_promote_shadow),
            pystray.MenuItem("Rollback Champion...", self.on_rollback_champion),
            pystray.MenuItem("View Model History", self.on_view_history),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Open Log", self.on_open_log),
            pystray.MenuItem("Open Config", self.on_open_config),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Exit", self.on_exit),
        )

        self.icon = pystray.Icon(
            "xgb_service",
            image,
            "XGB Training Service",
            menu,
        )

        self.scan_thread = threading.Thread(target=self.scheduler_loop, daemon=True)
        self.scan_thread.start()

        logger.info("Tray service started")
        self.icon.run()

    def scheduler_loop(self):
        interval = self.config.get("scan_interval_minutes", 30) * 60
        time.sleep(5)  # initial delay

        while self.running:
            if self.config.get("auto_train", True):
                try:
                    self.config = load_config()
                    self.state = scan_and_train(self.config, self.state)
                    self.update_icon()
                except Exception as e:
                    logger.error(f"Scan cycle error: {e}", exc_info=True)

            for _ in range(int(interval)):
                if not self.running:
                    break
                time.sleep(1)

    def update_icon(self):
        if self.icon:
            active = sum(1 for m in self.state.get("models", {}).values()
                         if m.get("status") == "pass")
            self.icon.icon = create_icon_image(active)
            last = self.state.get("last_scan", "never")
            if isinstance(last, str) and len(last) > 16:
                last = last[:16]
            self.icon.title = f"XGB | {active} models | Last: {last}"

    def on_train_now(self, icon, item):
        def do_train():
            logger.info("Manual train triggered")
            try:
                self.config = load_config()
                self.state = scan_and_train(self.config, self.state, force=True)
                self.update_icon()
            except Exception as e:
                logger.error(f"Manual train error: {e}", exc_info=True)
        threading.Thread(target=do_train, daemon=True).start()

    @staticmethod
    def _load_model_registry():
        """Import (or reload) model_registry the same way archive_newly_trained() /
        rebuild_merged_binaries() do, so tray actions see live-edited registry code
        without a service restart. Caller must sys.path.pop(0) when done."""
        sys.path.insert(0, str(SCRIPT_DIR))
        import importlib
        import model_registry
        importlib.reload(model_registry)
        return model_registry

    def _champion_output_path(self) -> str:
        """Mirror scan_and_train()'s output_path resolution (bin format only —
        tray promote/rollback only make sense when output_format=="bin")."""
        output_dir = self.config.get("output_dir", "auto")
        return str(DEFAULT_OUTPUT_BIN) if output_dir == "auto" else output_dir

    def on_promote_shadow(self, icon, item):
        def do_promote():
            logger.info("Promote shadow -> champion triggered")
            try:
                model_registry = self._load_model_registry()
                try:
                    promoted = []
                    for symbol, tf in model_registry.all_keys():
                        if model_registry.get_shadow(symbol, tf) is None:
                            continue
                        version_id = model_registry.promote_shadow_to_champion(symbol, tf)
                        promoted.append(f"{symbol}_{tf}->{version_id}")

                    if not promoted:
                        notify("Promote Shadow", "No pending shadow versions to promote.")
                        return

                    champion_path = self._champion_output_path()
                    model_registry.assemble_role_binary("champion", champion_path)
                    model_registry.assemble_role_binary("shadow", str(DEFAULT_OUTPUT_BIN_SHADOW))
                    self.update_icon()
                    notify("Promote Shadow", f"Promoted {len(promoted)} model(s):\n" + "\n".join(promoted))
                finally:
                    sys.path.pop(0)
            except Exception as e:
                logger.error(f"Promote shadow error: {e}", exc_info=True)
                notify("Promote Shadow Error", str(e))
        threading.Thread(target=do_promote, daemon=True).start()

    def on_rollback_champion(self, icon, item):
        def do_rollback():
            logger.info("Rollback champion triggered")
            try:
                model_registry = self._load_model_registry()
                try:
                    rolled_back = []
                    for symbol, tf in model_registry.all_keys():
                        versions = model_registry.list_versions(symbol, tf)
                        champion = model_registry.get_champion(symbol, tf)
                        candidates = [v for v in versions
                                      if v["role"] == "archived"
                                      and (champion is None or v["timestamp"] < champion["timestamp"])]
                        if not candidates:
                            continue
                        target = candidates[0]  # most recent archived, older than current champion
                        model_registry.rollback_champion(symbol, tf, target["version_id"])
                        rolled_back.append(f"{symbol}_{tf}->{target['version_id']}")

                    if not rolled_back:
                        notify("Rollback Champion", "No older archived version available to roll back to.")
                        return

                    champion_path = self._champion_output_path()
                    model_registry.assemble_role_binary("champion", champion_path)
                    self.update_icon()
                    notify("Rollback Champion", f"Rolled back {len(rolled_back)} model(s):\n" + "\n".join(rolled_back))
                finally:
                    sys.path.pop(0)
            except Exception as e:
                logger.error(f"Rollback champion error: {e}", exc_info=True)
                notify("Rollback Champion Error", str(e))
        threading.Thread(target=do_rollback, daemon=True).start()

    def on_view_history(self, icon, item):
        try:
            model_registry = self._load_model_registry()
            try:
                keys = model_registry.all_keys()
                if not keys:
                    notify("Model History", "No model history recorded yet.")
                    return

                lines = []
                for symbol, tf in sorted(keys):
                    versions = model_registry.list_versions(symbol, tf)
                    champion = next((v for v in versions if v["role"] == "champion"), None)
                    shadow = next((v for v in versions if v["role"] == "shadow"), None)
                    champ_txt = f"champ={champion['version_id']}(brier={champion['brier']})" if champion else "champ=none"
                    shadow_txt = f"shadow={shadow['version_id']}(brier={shadow['brier']})" if shadow else "shadow=none"
                    lines.append(f"{symbol}_{tf}: {champ_txt} {shadow_txt} [{len(versions)} versions]")

                text = "\n".join(lines)
                logger.info(f"Model history:\n{text}")
                notify("Model History", text[:250])
            finally:
                sys.path.pop(0)
        except Exception as e:
            logger.error(f"View history error: {e}", exc_info=True)
            notify("View History Error", str(e))

    def on_status(self, icon, item):
        text = get_status_text(self.state)
        logger.info(f"Status:\n{text}")
        notify("XGB Service Status", text[:250])

    def on_open_log(self, icon, item):
        os.startfile(str(LOG_PATH))

    def on_open_config(self, icon, item):
        os.startfile(str(CONFIG_PATH))

    def on_exit(self, icon, item):
        self.running = False
        logger.info("Service stopping...")
        icon.stop()


# ─── Headless Mode ───────────────────────────────────────────────────
def headless_loop(config: dict):
    state = load_state()
    interval = config.get("scan_interval_minutes", 30) * 60

    logger.info("Running in headless mode (no tray icon)")
    while True:
        try:
            config = load_config()
            state = scan_and_train(config, state)
        except Exception as e:
            logger.error(f"Scan error: {e}", exc_info=True)
        logger.info(f"Sleeping {interval}s until next scan...")
        time.sleep(interval)


# ─── Main ────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="XGBoost Auto-Training Service")
    parser.add_argument("--no-tray", action="store_true",
                        help="Run in headless mode (no system tray icon)")
    parser.add_argument("--train-now", action="store_true",
                        help="Run a single scan+train cycle, then exit")
    args = parser.parse_args()

    if not acquire_lock():
        print("ERROR: XGB Service is already running. Only one instance allowed.")
        print(f"       Lock file: {LOCK_PATH}")
        print("       To force restart, close the existing service first (tray > Exit).")
        sys.exit(1)

    import atexit
    atexit.register(release_lock)

    config = load_config()
    logger.info(f"Config loaded: {len(config.get('mt4_terminal_ids', []))} MT4 + "
                f"{len(config.get('mt5_terminal_ids', []))} MT5 terminals, "
                f"TFs={config.get('timeframes', [])}")

    if args.train_now:
        state = load_state()
        scan_and_train(config, state, force=True)
        return

    if args.no_tray or not HAS_TRAY:
        headless_loop(config)
    else:
        svc = TrayService(config)
        svc.start()


if __name__ == "__main__":
    main()
