#!/usr/bin/env python3
"""
xgb_trainer.py — Train XGBoost from RSI Advanced CSV logs and export model.json

Usage:
  python tools/xgb_trainer.py --dir "C:/Users/<name>/AppData/Roaming/MetaQuotes/Terminal/<id>/MQL4/Files/RSI_Advanced_Logs"
  python tools/xgb_trainer.py --dir <path> --symbol XAUUSD --tf H1 --depth 4 --trees 150
  python tools/xgb_trainer.py --dir <path> --out xgb_model.json

Output:
  xgb_model.json        — XGBoost booster (copy to MQL4/Files/RSI_Advanced/)
  feature_names.json    — feature order (MUST match XGBModel.mqh)
  xgb_report.txt        — AUC, Brier, feature importance
"""

import argparse, glob, json, os, sys
from pathlib import Path

# ── dependency check ──────────────────────────────────────────────────────────
MISSING = []
try:    import pandas as pd
except: MISSING.append("pandas")
try:    import numpy as np
except: MISSING.append("numpy")
try:    import xgboost as xgb
except: MISSING.append("xgboost")
try:
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import roc_auc_score, brier_score_loss
except:
    MISSING.append("scikit-learn")

if MISSING:
    print(f"[ERROR] Missing packages: {', '.join(MISSING)}")
    print(f"  Install: pip install {' '.join(MISSING)}")
    sys.exit(1)

from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, brier_score_loss

# ── constants ─────────────────────────────────────────────────────────────────
SESSION_MAP  = {"Asian": 0, "London": 1, "Overlap": 2, "LateNY": 3, "Unknown": -1}
DIR_MAP      = {"BUY": 1, "SELL": 0}
OUTCOME_MAP  = {"TP1": 1, "TP2": 1, "TP3": 1, "SL": 0, "REVERSAL": 0}

# Features used (order MUST match XGBModel.mqh FEATURE_* constants)
FEATURES = [
    "CASE_NUM",         # 0 — 1..9
    "DIR_BIN",          # 1 — 1=BUY, 0=SELL
    "RSI_AT_SIGNAL",    # 2 — RSI value at signal bar
    "ANGLE_Z",          # 3 — RSI angle z-score
    "SESSION_ID",       # 4 — 0=Asian 1=London 2=Overlap 3=LateNY
    "TF_MINUTES",       # 5 — timeframe in minutes (1,5,15,30,60,240,1440)
    "HOUR",             # 6 — hour of day (UTC)
    "DOW",              # 7 — day of week (0=Sun..6=Sat)
    "ATR_RATIO",        # 8 — current ATR / 50-bar avg ATR
    "SPREAD_PIPS",      # 9 — spread in pips
    "D1_TREND",         # 10 — D1 trend (-1,0,1)
    "RR_RATIO",         # 11 — TP1/SL risk-reward
    "SL_DIST_ATR",      # 12 — SL distance in ATR units
]

TF_MINUTES = {"M1":1,"M5":5,"M15":15,"M30":30,"H1":60,"H4":240,"D1":1440,"W1":10080,"MN":43200}

# ── helpers ───────────────────────────────────────────────────────────────────
def load_csv_glob(pattern):
    files = glob.glob(pattern)
    if not files:
        return pd.DataFrame()
    dfs = []
    for f in files:
        try:
            df = pd.read_csv(f, on_bad_lines='warn')
            dfs.append(df)
        except Exception as e:
            print(f"  [WARN] {f}: {e}")
    return pd.concat(dfs, ignore_index=True) if dfs else pd.DataFrame()

def build_features(signals: pd.DataFrame, outcomes: pd.DataFrame) -> pd.DataFrame:
    """Merge signals+outcomes and engineer features."""
    df = signals.merge(outcomes[["SIGNAL_ID","OUTCOME"]], on="SIGNAL_ID", how="inner")
    df = df[df["OUTCOME"].isin(OUTCOME_MAP.keys())].copy()
    df["TARGET"]      = df["OUTCOME"].map(OUTCOME_MAP).astype(int)
    df["DIR_BIN"]     = df["DIR"].map(DIR_MAP).fillna(0).astype(int)
    df["SESSION_ID"]  = df["SESSION"].map(SESSION_MAP).fillna(-1).astype(int)
    df["TF_MINUTES"]  = df["TF"].map(TF_MINUTES).fillna(0).astype(int)
    # Guard: fill numeric cols with median
    for col in FEATURES:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
            df[col] = df[col].fillna(df[col].median() if df[col].notna().any() else 0)
        else:
            df[col] = 0
    return df

# ── main ──────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Train XGBoost from RSI Advanced logs")
    ap.add_argument("--dir",    required=True,  help="Folder with signals_*.csv + outcomes_*.csv")
    ap.add_argument("--symbol", default="*",    help="Symbol filter (default: all)")
    ap.add_argument("--tf",     default="*",    help="Timeframe filter (default: all)")
    ap.add_argument("--depth",  type=int, default=4,   help="max_depth (default: 4)")
    ap.add_argument("--trees",  type=int, default=150, help="n_estimators (default: 150)")
    ap.add_argument("--out",    default="xgb_model.json", help="Output model file")
    args = ap.parse_args()

    base = args.dir.rstrip("/\\")
    sym  = args.symbol
    tf   = args.tf

    print(f"\n[xgb_trainer] Loading from: {base}")
    print(f"  symbol={sym} tf={tf} depth={args.depth} trees={args.trees}")

    # Load CSVs
    sig_pat = os.path.join(base, f"signals_{sym}_{tf}_*.csv")
    out_pat = os.path.join(base, f"outcomes_{sym}_{tf}_*.csv")
    signals  = load_csv_glob(sig_pat)
    outcomes = load_csv_glob(out_pat)

    if signals.empty:
        print(f"[ERROR] No signals CSV found: {sig_pat}")
        sys.exit(1)
    if outcomes.empty:
        print(f"[ERROR] No outcomes CSV found: {out_pat}")
        sys.exit(1)

    # Filter out PENDING
    outcomes = outcomes[outcomes["OUTCOME"] != "PENDING"]
    print(f"  signals={len(signals)} outcomes={len(outcomes)}")

    # Build feature matrix
    df = build_features(signals, outcomes)
    print(f"  Matched rows (signal+outcome): {len(df)}")

    if len(df) < 50:
        print("[WARN] Very few samples (<50). Model will likely overfit. Use for observation only.")
    elif len(df) < 300:
        print("[WARN] <300 samples. Model is exploratory — not production-ready.")

    X = df[FEATURES].values
    y = df["TARGET"].values
    pos_rate = y.mean()
    print(f"  Class balance: TP1={pos_rate:.1%}  SL/REV={(1-pos_rate):.1%}")

    # Train/test split (walk-forward style: last 20% as OOS)
    split = int(len(df) * 0.80)
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    # Train XGBoost
    scale_pos = (1 - pos_rate) / pos_rate if pos_rate > 0 else 1.0
    model = xgb.XGBClassifier(
        n_estimators       = args.trees,
        max_depth          = args.depth,
        learning_rate      = 0.05,
        subsample          = 0.8,
        colsample_bytree   = 0.8,
        scale_pos_weight   = scale_pos,
        objective          = "binary:logistic",
        eval_metric        = "auc",
        use_label_encoder  = False,
        random_state       = 42,
        verbosity          = 0,
    )

    eval_set = [(X_test, y_test)] if len(X_test) > 0 else []
    model.fit(X_train, y_train,
              eval_set=eval_set,
              verbose=False)

    # Evaluate on OOS
    report_lines = []
    report_lines.append("=== XGBoost Training Report ===")
    report_lines.append(f"Samples total: {len(df)}  (train={len(X_train)}, oos={len(X_test)})")
    report_lines.append(f"Features: {len(FEATURES)}")
    report_lines.append(f"Hyperparams: depth={args.depth} trees={args.trees}")
    report_lines.append(f"Class balance: TP1={pos_rate:.1%}")

    if len(X_test) >= 10:
        y_prob = model.predict_proba(X_test)[:, 1]
        auc    = roc_auc_score(y_test, y_prob)
        brier  = brier_score_loss(y_test, y_prob)
        report_lines.append(f"\nOOS Metrics:")
        report_lines.append(f"  AUC        = {auc:.4f}  (target > 0.55, good > 0.60)")
        report_lines.append(f"  Brier Loss = {brier:.4f}  (lower is better, <0.23 is good)")

        verdict = "GOOD — use in parallel" if auc > 0.60 else \
                  "WEAK — observation only" if auc > 0.55 else \
                  "POOR — collect more data"
        report_lines.append(f"  Verdict    = {verdict}")
    else:
        report_lines.append("\n[WARN] OOS set too small for reliable metrics.")

    # Feature importance
    report_lines.append("\nFeature Importance (gain):")
    importances = model.get_booster().get_score(importance_type="gain")
    sorted_imp = sorted(importances.items(), key=lambda x: -x[1])
    for fname, fval in sorted_imp:
        idx = int(fname[1:]) if fname.startswith("f") else -1
        feat_name = FEATURES[idx] if 0 <= idx < len(FEATURES) else fname
        report_lines.append(f"  {feat_name:20s}: {fval:.2f}")

    # Save model
    out_path = args.out
    model.get_booster().save_model(out_path)
    report_lines.append(f"\nModel saved: {out_path}")
    print(f"\n".join(report_lines))

    # Save feature names JSON (must match XGBModel.mqh)
    feat_json = Path(out_path).with_name("feature_names.json")
    with open(feat_json, "w") as f:
        json.dump({"features": FEATURES, "count": len(FEATURES)}, f, indent=2)
    print(f"Features saved: {feat_json}")

    # Save report
    report_path = Path(out_path).with_name("xgb_report.txt")
    with open(report_path, "w") as f:
        f.write("\n".join(report_lines))
    print(f"Report saved:  {report_path}")

if __name__ == "__main__":
    main()
