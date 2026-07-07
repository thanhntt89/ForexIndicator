#!/usr/bin/env python3
"""
xgb_validate.py — Walk-forward validation of XGBoost model vs Brier baseline

Usage:
  python tools/xgb_validate.py --dir <log_folder>
  python tools/xgb_validate.py --dir <log_folder> --symbol XAUUSD --tf H1 --folds 5

Output:
  Walk-forward AUC per fold + cumulative
  Comparison: XGBoost vs Brier (from scoring_*.csv)
  Feature importance chart (if matplotlib available)
"""

import argparse, glob, json, os, sys
from pathlib import Path
import warnings
warnings.filterwarnings("ignore")

MISSING = []
try:    import pandas as pd
except: MISSING.append("pandas")
try:    import numpy as np
except: MISSING.append("numpy")
try:    import xgboost as xgb
except: MISSING.append("xgboost")
try:    from sklearn.metrics import roc_auc_score, brier_score_loss
except: MISSING.append("scikit-learn")

if MISSING:
    print(f"[ERROR] Missing packages: {', '.join(MISSING)}")
    print(f"  Install: pip install {' '.join(MISSING)}")
    sys.exit(1)

from sklearn.metrics import roc_auc_score, brier_score_loss

SESSION_MAP = {"Asian":0,"London":1,"Overlap":2,"LateNY":3,"Unknown":-1}
DIR_MAP     = {"BUY":1,"SELL":0}
OUTCOME_MAP = {"TP1":1,"TP2":1,"TP3":1,"SL":0,"REVERSAL":0}
TF_MINUTES  = {"M1":1,"M5":5,"M15":15,"M30":30,"H1":60,"H4":240,"D1":1440}
FEATURES    = ["CASE_NUM","DIR_BIN","RSI_AT_SIGNAL","ANGLE_Z","SESSION_ID",
               "TF_MINUTES","HOUR","DOW","ATR_RATIO","SPREAD_PIPS","D1_TREND",
               "RR_RATIO","SL_DIST_ATR"]

def load_csv_glob(pattern):
    files = glob.glob(pattern)
    if not files: return pd.DataFrame()
    dfs = []
    for f in files:
        try: dfs.append(pd.read_csv(f, on_bad_lines='warn'))
        except Exception as e: print(f"  [WARN] {f}: {e}")
    return pd.concat(dfs, ignore_index=True) if dfs else pd.DataFrame()

def build_df(signals, outcomes):
    df = signals.merge(outcomes[["SIGNAL_ID","OUTCOME"]], on="SIGNAL_ID", how="inner")
    df = df[df["OUTCOME"].isin(OUTCOME_MAP.keys())].copy()
    df["TARGET"]     = df["OUTCOME"].map(OUTCOME_MAP).astype(int)
    df["DIR_BIN"]    = df["DIR"].map(DIR_MAP).fillna(0).astype(int)
    df["SESSION_ID"] = df["SESSION"].map(SESSION_MAP).fillna(-1).astype(int)
    df["TF_MINUTES"] = df["TF"].map(TF_MINUTES).fillna(0).astype(int)
    for col in FEATURES:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)
        else:
            df[col] = 0
    return df

def walk_forward_cv(df, n_folds=5, depth=4, trees=100):
    """Walk-forward: train on [0..i], test on [i..i+fold_size]."""
    results = []
    n = len(df)
    if n < n_folds * 10:
        print(f"  [WARN] Too few rows ({n}) for {n_folds} folds. Reducing to 3.")
        n_folds = 3
    fold_size = n // (n_folds + 1)
    min_train = fold_size

    for fold in range(n_folds):
        train_end = min_train + fold * fold_size
        test_start = train_end
        test_end   = min(test_start + fold_size, n)
        if test_end <= test_start: break

        X_tr = df[FEATURES].values[:train_end]
        y_tr = df["TARGET"].values[:train_end]
        X_te = df[FEATURES].values[test_start:test_end]
        y_te = df["TARGET"].values[test_start:test_end]

        if len(np.unique(y_te)) < 2: continue

        pos_rate = y_tr.mean()
        scale_pw  = (1 - pos_rate) / pos_rate if pos_rate > 0 else 1.0
        m = xgb.XGBClassifier(n_estimators=trees, max_depth=depth,
                               learning_rate=0.05, subsample=0.8,
                               colsample_bytree=0.8, scale_pos_weight=scale_pw,
                               objective="binary:logistic", random_state=42,
                               verbosity=0, use_label_encoder=False)
        m.fit(X_tr, y_tr, verbose=False)
        prob = m.predict_proba(X_te)[:, 1]
        auc  = roc_auc_score(y_te, prob)
        brier = brier_score_loss(y_te, prob)
        results.append({"fold": fold+1, "train_n": train_end, "test_n": len(y_te),
                         "auc": auc, "brier": brier})
        print(f"  Fold {fold+1}/{n_folds}: train={train_end} test={len(y_te)} AUC={auc:.4f} Brier={brier:.4f}")
    return results

def compare_with_brier(df_scored):
    """Compare XGB (trained on all data) vs Brier scores from scoring CSV."""
    if df_scored.empty or "PROB_TP1" not in df_scored.columns:
        return None
    # Brier scores from indicator's own calibration
    brier_col = pd.to_numeric(df_scored["PROB_TP1"], errors="coerce") / 100.0
    return brier_col

def main():
    ap = argparse.ArgumentParser(description="Walk-forward XGBoost validation")
    ap.add_argument("--dir",    required=True)
    ap.add_argument("--symbol", default="*")
    ap.add_argument("--tf",     default="*")
    ap.add_argument("--folds",  type=int, default=5)
    ap.add_argument("--depth",  type=int, default=4)
    ap.add_argument("--trees",  type=int, default=100)
    args = ap.parse_args()

    base = args.dir.rstrip("/\\")
    print(f"\n[xgb_validate] {base}")

    signals  = load_csv_glob(os.path.join(base, f"signals_{args.symbol}_{args.tf}_*.csv"))
    outcomes = load_csv_glob(os.path.join(base, f"outcomes_{args.symbol}_{args.tf}_*.csv"))
    scoring  = load_csv_glob(os.path.join(base, f"scoring_{args.symbol}_{args.tf}_*.csv"))

    if signals.empty or outcomes.empty:
        print("[ERROR] No signal/outcome CSVs found."); sys.exit(1)

    outcomes = outcomes[outcomes["OUTCOME"] != "PENDING"]
    df = build_df(signals, outcomes)
    print(f"  Total matched rows: {len(df)}")
    if len(df) < 30:
        print("[ERROR] Too few samples. Need at least 30."); sys.exit(1)

    print(f"\n--- Walk-Forward Validation ({args.folds} folds) ---")
    results = walk_forward_cv(df, args.folds, args.depth, args.trees)

    if results:
        aucs   = [r["auc"]   for r in results]
        briers = [r["brier"] for r in results]
        print(f"\n  Mean AUC  : {sum(aucs)/len(aucs):.4f}  (std={( sum((a-sum(aucs)/len(aucs))**2 for a in aucs)/len(aucs))**0.5:.4f})")
        print(f"  Mean Brier: {sum(briers)/len(briers):.4f}")
        verdict = "PRODUCTION READY" if min(aucs) > 0.57 else \
                  "OBSERVATION ONLY" if min(aucs) > 0.52 else \
                  "COLLECT MORE DATA"
        print(f"  Verdict   : {verdict}")

    # Compare vs indicator Brier
    if not scoring.empty:
        brier_probs = compare_with_brier(scoring)
        if brier_probs is not None:
            # Merge with outcomes to get ground truth
            scored_m = scoring.merge(
                outcomes[["SIGNAL_ID","OUTCOME"]], on="SIGNAL_ID", how="inner")
            scored_m = scored_m[scored_m["OUTCOME"].isin(OUTCOME_MAP.keys())]
            if len(scored_m) >= 10:
                y_true = scored_m["OUTCOME"].map(OUTCOME_MAP).astype(int).values
                brier_p = pd.to_numeric(scored_m["PROB_TP1"], errors="coerce").fillna(50) / 100.0
                brier_score = brier_score_loss(y_true, brier_p.values)
                print(f"\n  Indicator Brier Score (current system): {brier_score:.4f}")
                print(f"  XGB Mean Brier                        : {sum(briers)/len(briers) if results else 'n/a':.4f}")

    print("\n[Done] Run xgb_trainer.py to export the final model.json")

if __name__ == "__main__":
    main()
