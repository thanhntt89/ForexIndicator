#!/usr/bin/env python3
"""
rsi_xgboost_train.py — XGBoost training pipeline for RSI_Advanced V12

Reads CSV signal/scoring/outcome data, trains a walk-forward validated
XGBoost model, and exports the decision tree ensemble as MQL4/5 source code.

Usage:
    python rsi_xgboost_train.py --data-dir <path_to_csv_folder> [--output <XGBModel.mqh>]

The CSV folder should contain:
    signals_SYMBOL_TF_YYYY.csv
    scoring_SYMBOL_TF_YYYY.csv
    outcomes_SYMBOL_TF_YYYY.csv

Requirements:
    pip install xgboost pandas numpy scikit-learn matplotlib
"""

import argparse
import glob
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import brier_score_loss, roc_auc_score
from sklearn.calibration import calibration_curve

try:
    import xgboost as xgb
except ImportError:
    print("ERROR: xgboost not installed. Run: pip install xgboost")
    sys.exit(1)

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False


# ─── Configuration ──────────────────────────────────────────────────
XGB_PARAMS = {
    "objective":        "binary:logistic",
    "eval_metric":      "logloss",
    "max_depth":        4,
    "n_estimators":     50,
    "learning_rate":    0.05,
    "min_child_weight": 10,
    "subsample":        0.7,
    "colsample_bytree": 0.7,
    "reg_alpha":        0.1,
    "reg_lambda":       1.0,
    "gamma":            0.1,
    "random_state":     42,
    "verbosity":        0,
}

FEATURE_COLS_SIGNALS = [
    "RSI_AT_SIGNAL", "ANGLE_Z", "ATR_RATIO", "SL_DIST_ATR",
    "TP1_DIST_ATR", "RR_RATIO", "SPREAD_PIPS", "TIME_IN_SESSION_MIN",
]

FEATURE_COLS_SCORING = [
    "MTF_AGREE_PCT", "SPREAD_RATIO", "WF_ROBUST",
    "MTF_H4_TREND", "MTF_H1_TREND",
]

CATEGORICAL_COLS = ["CASE_NUM", "DIR_BIN", "SESSION_ENC"]
CYCLICAL_COLS = ["HOUR_SIN", "HOUR_COS", "DOW_SIN", "DOW_COS"]

EXCLUDED_SCORING_COLS = [
    "PROB_TP1", "PROB_SL", "EV", "RR",
    "RAW_T1", "RAW_T2", "COUNT_T3", "REAL_PCT",
]

MIN_SIGNALS_TOTAL = 150
MIN_OOS_PER_FOLD = 20
PURGE_BARS = 20
N_FOLDS = 5


# ─── Data Loading ───────────────────────────────────────────────────
def load_csvs(data_dir: str, prefix: str) -> pd.DataFrame:
    pattern = os.path.join(data_dir, f"{prefix}_*.csv")
    files = sorted(glob.glob(pattern))
    if not files:
        return pd.DataFrame()
    frames = []
    for f in files:
        try:
            df = pd.read_csv(f)
            frames.append(df)
        except Exception as e:
            print(f"  Warning: skipping {f}: {e}")
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def load_and_merge(data_dir: str) -> pd.DataFrame:
    print(f"Loading CSVs from: {data_dir}")
    signals = load_csvs(data_dir, "signals")
    scoring = load_csvs(data_dir, "scoring")
    outcomes = load_csvs(data_dir, "outcomes")

    if signals.empty:
        print("ERROR: No signals CSV files found.")
        sys.exit(1)
    if outcomes.empty:
        print("ERROR: No outcomes CSV files found.")
        sys.exit(1)

    print(f"  Signals: {len(signals)} rows")
    print(f"  Scoring: {len(scoring)} rows")
    print(f"  Outcomes: {len(outcomes)} rows")

    outcomes = outcomes[outcomes["OUTCOME"] != "PENDING"].copy()
    print(f"  Resolved outcomes: {len(outcomes)}")

    merged = signals.merge(scoring, on="SIGNAL_ID", how="left", suffixes=("", "_sc"))
    merged = merged.merge(outcomes, on="SIGNAL_ID", how="inner", suffixes=("", "_oc"))
    print(f"  Merged (joined): {len(merged)} rows")

    return merged


# ─── Feature Engineering ────────────────────────────────────────────
SESSION_MAP = {"Asian": 0, "London": 1, "Overlap": 2, "LateNY": 3}


def engineer_features(df: pd.DataFrame) -> tuple:
    df = df.copy()

    # Target: binary (TP1+ = 1, SL/REVERSAL = 0)
    df["target"] = (df["OUTCOME"].isin(["TP1", "TP2", "TP3"])).astype(int)

    # Direction binary
    df["DIR_BIN"] = (df["DIR"] == "BUY").astype(int)

    # Session encode
    if "SESSION" in df.columns:
        df["SESSION_ENC"] = df["SESSION"].map(SESSION_MAP).fillna(0).astype(int)
    else:
        df["SESSION_ENC"] = 0

    # Cyclical hour/dow
    if "HOUR" in df.columns:
        df["HOUR_SIN"] = np.sin(2 * np.pi * df["HOUR"] / 24)
        df["HOUR_COS"] = np.cos(2 * np.pi * df["HOUR"] / 24)
    else:
        df["HOUR_SIN"] = 0.0
        df["HOUR_COS"] = 1.0

    if "DOW" in df.columns:
        df["DOW_SIN"] = np.sin(2 * np.pi * df["DOW"] / 5)
        df["DOW_COS"] = np.cos(2 * np.pi * df["DOW"] / 5)
    else:
        df["DOW_SIN"] = 0.0
        df["DOW_COS"] = 1.0

    # D1_TREND as numeric
    if "D1_TREND" in df.columns:
        df["D1_TREND"] = pd.to_numeric(df["D1_TREND"], errors="coerce").fillna(0).astype(int)

    # WF_ROBUST as int
    if "WF_ROBUST" in df.columns:
        df["WF_ROBUST"] = pd.to_numeric(df["WF_ROBUST"], errors="coerce").fillna(0).astype(int)

    # Build feature list
    feature_cols = []
    for c in FEATURE_COLS_SIGNALS:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0)
            feature_cols.append(c)

    for c in FEATURE_COLS_SCORING:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0)
            feature_cols.append(c)

    feature_cols.append("D1_TREND")
    feature_cols.extend(CATEGORICAL_COLS)
    feature_cols.extend(CYCLICAL_COLS)

    # Keep only valid features
    feature_cols = [c for c in feature_cols if c in df.columns]

    return df, feature_cols


# ─── Walk-Forward Cross-Validation ──────────────────────────────────
def walk_forward_splits(n_samples: int, n_folds: int, purge: int):
    fold_size = n_samples // (n_folds + 1)
    splits = []
    for i in range(n_folds):
        train_end = fold_size * (i + 2)
        val_start = train_end + purge
        val_end = min(val_start + fold_size, n_samples)
        if val_end - val_start < MIN_OOS_PER_FOLD:
            continue
        splits.append((list(range(train_end)), list(range(val_start, val_end))))
    return splits


def train_and_validate(df: pd.DataFrame, feature_cols: list) -> dict:
    X = df[feature_cols].values
    y = df["target"].values

    splits = walk_forward_splits(len(df), N_FOLDS, PURGE_BARS)
    if not splits:
        print("ERROR: Not enough data for walk-forward validation.")
        sys.exit(1)

    print(f"\nWalk-Forward Validation: {len(splits)} folds")

    oos_preds_all = []
    oos_true_all = []
    fold_metrics = []

    for fold_i, (train_idx, val_idx) in enumerate(splits):
        X_train, y_train = X[train_idx], y[train_idx]
        X_val, y_val = X[val_idx], y[val_idx]

        model = xgb.XGBClassifier(**XGB_PARAMS)
        model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

        y_pred = model.predict_proba(X_val)[:, 1]
        brier = brier_score_loss(y_val, y_pred)
        auc = roc_auc_score(y_val, y_pred) if len(np.unique(y_val)) > 1 else 0.5

        fold_metrics.append({"fold": fold_i + 1, "n_train": len(train_idx),
                             "n_val": len(val_idx), "brier": brier, "auc": auc})
        oos_preds_all.extend(y_pred.tolist())
        oos_true_all.extend(y_val.tolist())

        print(f"  Fold {fold_i+1}: train={len(train_idx)}, val={len(val_idx)}, "
              f"Brier={brier:.4f}, AUC={auc:.4f}")

    oos_preds = np.array(oos_preds_all)
    oos_true = np.array(oos_true_all)

    overall_brier = brier_score_loss(oos_true, oos_preds)
    overall_auc = roc_auc_score(oos_true, oos_preds) if len(np.unique(oos_true)) > 1 else 0.5

    print(f"\n  Overall OOS Brier: {overall_brier:.4f}")
    print(f"  Overall OOS AUC:   {overall_auc:.4f}")

    # Final model on all data
    print("\nTraining final model on all data...")
    final_model = xgb.XGBClassifier(**XGB_PARAMS)
    final_model.fit(X, y, verbose=False)

    # Feature importance
    importances = final_model.feature_importances_
    fi_df = pd.DataFrame({"feature": feature_cols, "importance": importances})
    fi_df = fi_df.sort_values("importance", ascending=False)
    print("\nFeature Importance (top 10):")
    for _, row in fi_df.head(10).iterrows():
        print(f"  {row['feature']:25s} {row['importance']:.4f}")

    max_importance = fi_df["importance"].max()
    if max_importance > 0.50:
        print(f"\n  WARNING: Feature '{fi_df.iloc[0]['feature']}' has {max_importance:.1%} "
              f"of total importance — potential overfitting to single feature.")

    return {
        "model": final_model,
        "feature_cols": feature_cols,
        "oos_brier": overall_brier,
        "oos_auc": overall_auc,
        "oos_preds": oos_preds,
        "oos_true": oos_true,
        "fold_metrics": fold_metrics,
        "feature_importance": fi_df,
    }


# ─── Validation Gates ───────────────────────────────────────────────
def validate_model(results: dict) -> bool:
    passed = True

    if results["oos_brier"] >= 0.25:
        print(f"\nFAIL: OOS Brier {results['oos_brier']:.4f} >= 0.25 (no skill)")
        passed = False
    else:
        print(f"\nPASS: OOS Brier {results['oos_brier']:.4f} < 0.25")

    if results["oos_auc"] <= 0.55:
        print(f"FAIL: OOS AUC {results['oos_auc']:.4f} <= 0.55 (minimal discrimination)")
        passed = False
    else:
        print(f"PASS: OOS AUC {results['oos_auc']:.4f} > 0.55")

    max_fi = results["feature_importance"]["importance"].max()
    if max_fi > 0.50:
        print(f"WARN: Single feature dominance {max_fi:.1%} > 50%")

    if HAS_MATPLOTLIB:
        try:
            prob_true, prob_pred = calibration_curve(
                results["oos_true"], results["oos_preds"], n_bins=8, strategy="quantile"
            )
            diffs = np.diff(prob_true)
            if np.all(diffs >= -0.05):
                print("PASS: Calibration curve approximately monotonic")
            else:
                print("WARN: Calibration curve not monotonic (may be noise with small data)")
        except Exception:
            print("SKIP: Calibration curve check (insufficient data per bin)")

    return passed


# ─── MQL Code Generation ────────────────────────────────────────────
def tree_to_mql(booster, tree_index: int, feature_names: list) -> str:
    tree_df = booster.trees_to_dataframe()
    tree_df = tree_df[tree_df["Tree"] == tree_index].copy()

    lines = []
    lines.append(f"double XGBTree{tree_index}(")
    params = ", ".join([f"double f{i}" for i in range(len(feature_names))])
    lines.append(f"   {params})")
    lines.append("{")

    node_map = {}
    for _, row in tree_df.iterrows():
        node_map[row["ID"]] = row

    def recurse(node_id: str, indent: int) -> list:
        node = node_map[node_id]
        pad = "   " * indent

        if node["Feature"] == "Leaf":
            return [f"{pad}return({node['Gain']:.8f});"]

        feat_name = node["Feature"]
        feat_idx = feature_names.index(feat_name) if feat_name in feature_names else 0
        threshold = node["Split"]

        result = []
        result.append(f"{pad}if(f{feat_idx} < {threshold:.8f})")
        result.append(f"{pad}{{")
        result.extend(recurse(node["Yes"], indent + 1))
        result.append(f"{pad}}}")
        result.append(f"{pad}else")
        result.append(f"{pad}{{")
        result.extend(recurse(node["No"], indent + 1))
        result.append(f"{pad}}}")
        return result

    lines.extend(recurse(f"{tree_index}-0", 1))
    lines.append("}")
    return "\n".join(lines)


def export_model_to_mql(results: dict, output_path: str, data_summary: str):
    model = results["model"]
    feature_cols = results["feature_cols"]
    booster = model.get_booster()
    n_trees = booster.num_boosted_rounds()

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    timestamp = int(time.time())

    header = f"""//+------------------------------------------------------------------+
//| XGBModel.mqh - Auto-generated XGBoost model                      |
//| Generated: {now_str}                                |
//| Training data: {data_summary[:50]:50s}|
//| OOS Brier: {results['oos_brier']:.4f} | OOS AUC: {results['oos_auc']:.4f}             |
//| Trees: {n_trees} | Depth: {XGB_PARAMS['max_depth']}                                           |
//| DO NOT EDIT - regenerate using tools/rsi_xgboost_train.py        |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_XGBMODEL_MQH
#define RSI_ADV_XGBMODEL_MQH

//+------------------------------------------------------------------+
//| Model metadata                                                     |
//+------------------------------------------------------------------+
#define XGB_MODEL_TREES     {n_trees}
#define XGB_MODEL_DEPTH     {XGB_PARAMS['max_depth']}
#define XGB_MODEL_TRAINED   {timestamp}
#define XGB_MODEL_OOS_BRIER {results['oos_brier']:.4f}
#define XGB_MODEL_OOS_AUC   {results['oos_auc']:.4f}

"""

    # Feature name → parameter mapping comment
    feature_map_comment = "// Feature mapping:\n"
    for i, fname in enumerate(feature_cols):
        feature_map_comment += f"//   f{i} = {fname}\n"
    feature_map_comment += "\n"

    # Generate individual tree functions
    tree_functions = []
    for t in range(n_trees):
        try:
            tree_code = tree_to_mql(booster, t, feature_cols)
            tree_functions.append(tree_code)
        except Exception as e:
            print(f"  Warning: tree {t} export failed: {e}")

    # Generate ensemble prediction function
    param_list = []
    param_list.append("   double rsiAtSignal,")
    param_list.append("   double angleZ,")
    param_list.append("   double atrRatio,")
    param_list.append("   double slDistATR,")
    param_list.append("   double tp1DistATR,")
    param_list.append("   double rrRatio,")
    param_list.append("   double spreadPips,")
    param_list.append("   double timeInSessionMin,")
    param_list.append("   int    caseNum,")
    param_list.append("   int    dir,")
    param_list.append("   int    session,")
    param_list.append("   int    hour,")
    param_list.append("   int    dow,")
    param_list.append("   int    d1Trend,")
    param_list.append("   int    mtfAgreePct,")
    param_list.append("   double spreadRatio,")
    param_list.append("   int    wfRobust,")
    param_list.append("   int    h4Trend,")
    param_list.append("   int    h1Trend")

    # Build feature-to-f_index mapping
    feature_to_arg = {}
    for i, fname in enumerate(feature_cols):
        if fname == "RSI_AT_SIGNAL":   feature_to_arg[i] = "rsiAtSignal"
        elif fname == "ANGLE_Z":       feature_to_arg[i] = "angleZ"
        elif fname == "ATR_RATIO":     feature_to_arg[i] = "atrRatio"
        elif fname == "SL_DIST_ATR":   feature_to_arg[i] = "slDistATR"
        elif fname == "TP1_DIST_ATR":  feature_to_arg[i] = "tp1DistATR"
        elif fname == "RR_RATIO":     feature_to_arg[i] = "rrRatio"
        elif fname == "SPREAD_PIPS":   feature_to_arg[i] = "spreadPips"
        elif fname == "TIME_IN_SESSION_MIN": feature_to_arg[i] = "timeInSessionMin"
        elif fname == "MTF_AGREE_PCT": feature_to_arg[i] = "(double)mtfAgreePct"
        elif fname == "SPREAD_RATIO":  feature_to_arg[i] = "spreadRatio"
        elif fname == "WF_ROBUST":     feature_to_arg[i] = "(double)wfRobust"
        elif fname == "MTF_H4_TREND":  feature_to_arg[i] = "(double)h4Trend"
        elif fname == "MTF_H1_TREND":  feature_to_arg[i] = "(double)h1Trend"
        elif fname == "D1_TREND":      feature_to_arg[i] = "(double)d1Trend"
        elif fname == "CASE_NUM":      feature_to_arg[i] = "(double)caseNum"
        elif fname == "DIR_BIN":       feature_to_arg[i] = "(double)dir"
        elif fname == "SESSION_ENC":   feature_to_arg[i] = "(double)session"
        elif fname == "HOUR_SIN":      feature_to_arg[i] = "MathSin(2.0*M_PI*hour/24.0)"
        elif fname == "HOUR_COS":      feature_to_arg[i] = "MathCos(2.0*M_PI*hour/24.0)"
        elif fname == "DOW_SIN":       feature_to_arg[i] = "MathSin(2.0*M_PI*dow/5.0)"
        elif fname == "DOW_COS":       feature_to_arg[i] = "MathCos(2.0*M_PI*dow/5.0)"
        else:                          feature_to_arg[i] = "0.0"

    # Build the args string for tree calls
    tree_args = ", ".join([feature_to_arg.get(i, "0.0") for i in range(len(feature_cols))])

    predict_fn = f"""
//+------------------------------------------------------------------+
//| XGBPredict - Ensemble prediction (sigmoid of tree sum)            |
//+------------------------------------------------------------------+
double XGBPredict(
{chr(10).join(param_list)}
)
{{
   double logit = 0.0;
"""
    for t in range(len(tree_functions)):
        predict_fn += f"   logit += XGBTree{t}({tree_args});\n"

    predict_fn += """
   double prob = 1.0 / (1.0 + MathExp(-logit));
   return(prob * 100.0);
}

#endif
"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(header)
        f.write(feature_map_comment)
        for tree_fn in tree_functions:
            f.write(tree_fn)
            f.write("\n\n")
        f.write(predict_fn)

    print(f"\nExported {len(tree_functions)} trees to: {output_path}")
    total_lines = header.count("\n") + sum(fn.count("\n") for fn in tree_functions) + predict_fn.count("\n")
    print(f"  Total lines: ~{total_lines}")


# ─── Calibration Plot ────────────────────────────────────────────────
def save_calibration_plot(results: dict, output_dir: str):
    if not HAS_MATPLOTLIB:
        print("  Skipping calibration plot (matplotlib not installed)")
        return

    try:
        prob_true, prob_pred = calibration_curve(
            results["oos_true"], results["oos_preds"],
            n_bins=8, strategy="quantile"
        )
    except Exception:
        print("  Skipping calibration plot (insufficient data)")
        return

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

    ax1.plot([0, 1], [0, 1], "k--", alpha=0.5, label="Perfect")
    ax1.plot(prob_pred, prob_true, "bo-", label="XGBoost OOS")
    ax1.set_xlabel("Mean Predicted Probability")
    ax1.set_ylabel("Fraction of Positives")
    ax1.set_title(f"Calibration Curve (Brier={results['oos_brier']:.4f})")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.hist(results["oos_preds"], bins=20, edgecolor="black", alpha=0.7)
    ax2.set_xlabel("Predicted Probability")
    ax2.set_ylabel("Count")
    ax2.set_title("Prediction Distribution")
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plot_path = os.path.join(output_dir, "xgb_calibration.png")
    plt.savefig(plot_path, dpi=100)
    plt.close()
    print(f"  Saved calibration plot: {plot_path}")


# ─── Main ────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="XGBoost training for RSI_Advanced V12")
    parser.add_argument("--data-dir", required=True,
                        help="Directory containing signal/scoring/outcome CSVs")
    parser.add_argument("--output", default=None,
                        help="Output XGBModel.mqh path (default: Include/RSI_Advanced/XGBModel.mqh)")
    parser.add_argument("--force", action="store_true",
                        help="Export even if validation fails")
    args = parser.parse_args()

    if args.output is None:
        script_dir = Path(__file__).parent.parent
        args.output = str(script_dir / "Include" / "RSI_Advanced" / "XGBModel.mqh")

    # Load and merge
    df = load_and_merge(args.data_dir)

    if len(df) < MIN_SIGNALS_TOTAL:
        print(f"\nERROR: Only {len(df)} resolved signals. Need at least {MIN_SIGNALS_TOTAL}.")
        print("Continue collecting data with the indicator running.")
        sys.exit(1)

    # Sort by signal time for walk-forward
    if "SIGNAL_TIME" in df.columns:
        df = df.sort_values("SIGNAL_TIME").reset_index(drop=True)

    # Feature engineering
    df, feature_cols = engineer_features(df)
    print(f"\nFeatures ({len(feature_cols)}): {feature_cols}")
    print(f"Target distribution: {df['target'].value_counts().to_dict()}")

    # Train and validate
    results = train_and_validate(df, feature_cols)

    # Validation gates
    passed = validate_model(results)

    # Calibration plot
    save_calibration_plot(results, os.path.dirname(args.output) or ".")

    # Export
    if passed or args.force:
        if not passed:
            print("\nWARNING: Exporting despite validation failure (--force)")

        symbols = df["SYMBOL"].unique() if "SYMBOL" in df.columns else ["unknown"]
        tfs = df["TF"].unique() if "TF" in df.columns else ["unknown"]
        data_summary = f"{len(df)} signals, {','.join(symbols)}, {','.join(tfs)}"

        export_model_to_mql(results, args.output, data_summary)
        print(f"\nDone. Recompile the indicator to use the new model.")
        print(f"Remember to delete RSI_SESS_*.bin files after recompiling.")
    else:
        print("\nModel NOT exported — validation failed.")
        print("Options:")
        print("  1. Collect more data (target: 300+ resolved signals)")
        print("  2. Use --force to export anyway (not recommended)")
        sys.exit(1)


if __name__ == "__main__":
    main()
