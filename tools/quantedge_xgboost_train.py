#!/usr/bin/env python3
"""
quantedge_xgboost_train.py — XGBoost training pipeline for QuantEdge_RSI V12

Reads CSV signal/scoring/outcome data, trains a walk-forward validated
XGBoost model, and exports the decision tree ensemble as MQL4/5 source code.

Usage (standalone):
    python quantedge_xgboost_train.py --data-dir <path_to_csv_folder>
    python quantedge_xgboost_train.py --data-dir <path> --symbol XAUUSD --tf H1

Usage (called by xgb_service.py):
    python quantedge_xgboost_train.py --data-dir <path> --symbol XAUUSD --tf H1 \
        --model-index 0 --json-output

Requirements:
    pip install -r requirements.txt
"""

import argparse
import glob
import json
import os
import re
import struct
import sys
import tempfile
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

try:
    import shap
    HAS_SHAP = True
except ImportError:
    HAS_SHAP = False


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

# P2 additions (Advanced Features: ADX/MACD/US10Y) — map to MQL feature
# array indices 21-24 in XGBPredict()/XGBPredictShadow(). Missing columns
# (old CSVs, or the toggle was OFF) default to 0 via engineer_features().
FEATURE_COLS_ADVANCED = [
    "ADX_VALUE", "MACD_HISTOGRAM", "MACD_SLOPE", "US10Y_TREND",
]

CATEGORICAL_COLS = ["CASE_NUM", "DIR_BIN", "SESSION_ENC"]
CYCLICAL_COLS = ["HOUR_SIN", "HOUR_COS", "DOW_SIN", "DOW_COS"]

MIN_SIGNALS_TOTAL = 150
MIN_OOS_PER_FOLD = 20
PURGE_BARS = 20
N_FOLDS = 5

TF_TO_PERIOD = {
    "M1": 1, "M5": 5, "M15": 15, "M30": 30,
    "H1": 60, "H4": 240, "D1": 1440, "W1": 10080, "MN1": 43200,
}


# ─── Data Loading ───────────────────────────────────────────────────
def load_csvs(data_dirs: list, prefix: str, symbol: str = None, tf: str = None) -> pd.DataFrame:
    frames = []
    for data_dir in data_dirs:
        if not os.path.isdir(data_dir):
            continue
        pattern = os.path.join(data_dir, f"{prefix}_*.csv")
        for f in sorted(glob.glob(pattern)):
            fname = os.path.basename(f)
            if symbol and f"_{symbol}_" not in fname and not fname.startswith(f"{prefix}_{symbol}_"):
                continue
            if tf:
                tf_pattern = f"_{tf}_"
                if tf_pattern not in fname:
                    continue
            try:
                df = pd.read_csv(f)
                frames.append(df)
            except Exception as e:
                print(f"  Warning: skipping {f}: {e}")
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def load_and_merge(data_dirs: list, symbol: str = None, tf: str = None) -> pd.DataFrame:
    print(f"Loading CSVs from {len(data_dirs)} director(ies)")
    if symbol:
        print(f"  Filter: symbol={symbol}")
    if tf:
        print(f"  Filter: tf={tf}")

    signals = load_csvs(data_dirs, "signals", symbol, tf)
    scoring = load_csvs(data_dirs, "scoring", symbol, tf)
    outcomes = load_csvs(data_dirs, "outcomes", symbol, tf)

    if signals.empty:
        print("ERROR: No signals CSV files found.")
        return pd.DataFrame()
    if outcomes.empty:
        print("ERROR: No outcomes CSV files found.")
        return pd.DataFrame()

    print(f"  Signals: {len(signals)} rows")
    print(f"  Scoring: {len(scoring)} rows")
    print(f"  Outcomes: {len(outcomes)} rows")

    # Dedup by SIGNAL_ID (multi-terminal may produce duplicates)
    signals = signals.drop_duplicates(subset=["SIGNAL_ID"], keep="last")
    scoring = scoring.drop_duplicates(subset=["SIGNAL_ID"], keep="last")
    outcomes = outcomes.drop_duplicates(subset=["SIGNAL_ID"], keep="last")

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

    df["target"] = (df["OUTCOME"].isin(["TP1", "TP2", "TP3"])).astype(int)
    df["DIR_BIN"] = (df["DIR"] == "BUY").astype(int)

    if "SESSION" in df.columns:
        df["SESSION_ENC"] = df["SESSION"].map(SESSION_MAP).fillna(0).astype(int)
    else:
        df["SESSION_ENC"] = 0

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

    if "D1_TREND" in df.columns:
        df["D1_TREND"] = pd.to_numeric(df["D1_TREND"], errors="coerce").fillna(0).astype(int)

    if "WF_ROBUST" in df.columns:
        df["WF_ROBUST"] = pd.to_numeric(df["WF_ROBUST"], errors="coerce").fillna(0).astype(int)

    feature_cols = []
    for c in FEATURE_COLS_SIGNALS:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0)
            feature_cols.append(c)

    for c in FEATURE_COLS_SCORING:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0)
            feature_cols.append(c)

    for c in FEATURE_COLS_ADVANCED:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0)
            feature_cols.append(c)

    feature_cols.append("D1_TREND")
    feature_cols.extend(CATEGORICAL_COLS)
    feature_cols.extend(CYCLICAL_COLS)

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
        return None

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

    print("\nTraining final model on all data...")
    final_model = xgb.XGBClassifier(**XGB_PARAMS)
    final_model.fit(X, y, verbose=False)

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
        "X_train_full": X,
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
PREDICT_PARAMS = [
    "   double rsiAtSignal,",
    "   double angleZ,",
    "   double atrRatio,",
    "   double slDistATR,",
    "   double tp1DistATR,",
    "   double rrRatio,",
    "   double spreadPips,",
    "   double timeInSessionMin,",
    "   int    caseNum,",
    "   int    dir,",
    "   int    session,",
    "   int    hour,",
    "   int    dow,",
    "   int    d1Trend,",
    "   int    mtfAgreePct,",
    "   double spreadRatio,",
    "   int    wfRobust,",
    "   int    h4Trend,",
    "   int    h1Trend,",
    "   double adxValue = 0.0,",
    "   double macdHistogram = 0.0,",
    "   double macdSlope = 0.0,",
    "   double us10yTrend = 0.0",
]

FEATURE_ARG_MAP = {
    "RSI_AT_SIGNAL":      "rsiAtSignal",
    "ANGLE_Z":            "angleZ",
    "ATR_RATIO":          "atrRatio",
    "SL_DIST_ATR":        "slDistATR",
    "TP1_DIST_ATR":       "tp1DistATR",
    "RR_RATIO":           "rrRatio",
    "SPREAD_PIPS":        "spreadPips",
    "TIME_IN_SESSION_MIN":"timeInSessionMin",
    "MTF_AGREE_PCT":      "(double)mtfAgreePct",
    "SPREAD_RATIO":       "spreadRatio",
    "WF_ROBUST":          "(double)wfRobust",
    "MTF_H4_TREND":       "(double)h4Trend",
    "MTF_H1_TREND":       "(double)h1Trend",
    "D1_TREND":           "(double)d1Trend",
    "CASE_NUM":           "(double)caseNum",
    "DIR_BIN":            "(double)dir",
    "SESSION_ENC":        "(double)session",
    "HOUR_SIN":           "MathSin(2.0*M_PI*hour/24.0)",
    "HOUR_COS":           "MathCos(2.0*M_PI*hour/24.0)",
    "DOW_SIN":            "MathSin(2.0*M_PI*dow/5.0)",
    "DOW_COS":            "MathCos(2.0*M_PI*dow/5.0)",
    "ADX_VALUE":          "adxValue",
    "MACD_HISTOGRAM":     "macdHistogram",
    "MACD_SLOPE":         "macdSlope",
    "US10Y_TREND":        "us10yTrend",
}


def tree_to_mql(booster, tree_index: int, feature_names: list, func_prefix: str) -> str:
    tree_df = booster.trees_to_dataframe()
    tree_df = tree_df[tree_df["Tree"] == tree_index].copy()

    lines = []
    params = ", ".join([f"double f{i}" for i in range(len(feature_names))])
    lines.append(f"double {func_prefix}_{tree_index}(")
    lines.append(f"   {params})")
    lines.append("{")

    node_map = {}
    for _, row in tree_df.iterrows():
        node_map[row["Node"]] = row

    def recurse(node_id: int, indent: int) -> list:
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

    lines.extend(recurse(0, 1))
    lines.append("}")
    return "\n".join(lines)


def build_tree_args(feature_cols: list) -> str:
    args = []
    for i, fname in enumerate(feature_cols):
        args.append(FEATURE_ARG_MAP.get(fname, "0.0"))
    return ", ".join(args)


def gen_model_block(results: dict, model_index: int, symbol: str, tf: str) -> tuple:
    """Generate MQL code for one model. Returns (tree_code, predict_fn, n_trees, info)."""
    model = results["model"]
    feature_cols = results["feature_cols"]
    booster = model.get_booster()
    n_trees = booster.num_boosted_rounds()
    prefix = f"XGBTree{model_index}"

    tree_code_parts = []
    exported = 0
    for t in range(n_trees):
        try:
            code = tree_to_mql(booster, t, feature_cols, prefix)
            tree_code_parts.append(code)
            exported += 1
        except Exception as e:
            print(f"  Warning: model {model_index} tree {t} export failed: {e}")

    tree_args = build_tree_args(feature_cols)

    predict_fn = f"double XGBPredictModel{model_index}(\n"
    predict_fn += "\n".join(PREDICT_PARAMS)
    predict_fn += "\n)\n{\n   double logit = 0.0;\n"
    for t in range(exported):
        predict_fn += f"   logit += {prefix}_{t}({tree_args});\n"
    predict_fn += "   double prob = 1.0 / (1.0 + MathExp(-logit));\n"
    predict_fn += "   return(prob * 100.0);\n}\n"

    info = {
        "index": model_index,
        "symbol": symbol,
        "tf": tf,
        "period": TF_TO_PERIOD.get(tf, 0),
        "trees": exported,
        "brier": results["oos_brier"],
        "auc": results["oos_auc"],
    }

    return "\n\n".join(tree_code_parts), predict_fn, exported, info


def export_single_model(results: dict, output_path: str, symbol: str, tf: str):
    """Export a single-model XGBModel.mqh (standalone mode)."""
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    timestamp = int(time.time())
    period = TF_TO_PERIOD.get(tf, 0)

    tree_code, predict_fn, n_trees, _ = gen_model_block(results, 0, symbol, tf)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(f"""//+------------------------------------------------------------------+
//| XGBModel.mqh - Auto-generated XGBoost model                      |
//| Generated: {now_str}                                |
//| Model: {symbol} {tf} ({n_trees} trees, depth {XGB_PARAMS['max_depth']})                       |
//| OOS Brier: {results['oos_brier']:.4f} | OOS AUC: {results['oos_auc']:.4f}             |
//| DO NOT EDIT - regenerate using tools/quantedge_xgboost_train.py  |
//+------------------------------------------------------------------+
#ifndef QE_XGBMODEL_MQH
#define QE_XGBMODEL_MQH

#define XGB_MODEL_COUNT     1
#define XGB_MODEL_TREES     {n_trees}
#define XGB_MODEL_DEPTH     {XGB_PARAMS['max_depth']}
#define XGB_MODEL_TRAINED   {timestamp}
#define XGB_MODEL_OOS_BRIER {results['oos_brier']:.4f}
#define XGB_MODEL_OOS_AUC   {results['oos_auc']:.4f}

int XGBFindModel(string symbol, int period)
{{
   if(symbol == "{symbol}" && period == {period}) return(0);
   // Symbol suffix tolerance (XAUUSDc, XAUUSD.a, etc.)
   if(StringFind(symbol, "{symbol}") == 0 && period == {period}) return(0);
   return(-1);
}}

""")
        f.write(tree_code)
        f.write("\n\n")
        f.write(predict_fn)
        f.write(f"""
double XGBPredict(
{chr(10).join(PREDICT_PARAMS)}
)
{{
   int idx = XGBFindModel(Symbol(), Period());
   if(idx < 0) return(50.0);
   return(XGBPredictModel0({build_tree_args(results['feature_cols'])}));
}}

#endif
""")

    print(f"\nExported {n_trees} trees to: {output_path}")


def export_multi_model(model_list: list, output_path: str):
    """Export multi-model XGBModel.mqh from a list of (results, symbol, tf) tuples."""
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    timestamp = int(time.time())
    best_brier = min(r["oos_brier"] for r, _, _ in model_list)

    all_tree_code = []
    all_predict_fns = []
    all_info = []

    for i, (results, symbol, tf) in enumerate(model_list):
        tree_code, predict_fn, n_trees, info = gen_model_block(results, i, symbol, tf)
        all_tree_code.append(f"// ── Model {i}: {symbol} {tf} (Brier={results['oos_brier']:.4f}, "
                             f"AUC={results['oos_auc']:.4f}, {n_trees} trees) ──\n\n" + tree_code)
        all_predict_fns.append(predict_fn)
        all_info.append(info)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(f"""//+------------------------------------------------------------------+
//| XGBModel.mqh - Auto-generated XGBoost multi-model                 |
//| Generated: {now_str}                                |
//| Models: {len(model_list)} | Best Brier: {best_brier:.4f}                          |
//| DO NOT EDIT - regenerate using tools/xgb_service.py               |
//+------------------------------------------------------------------+
#ifndef QE_XGBMODEL_MQH
#define QE_XGBMODEL_MQH

#define XGB_MODEL_COUNT     {len(model_list)}
#define XGB_MODEL_DEPTH     {XGB_PARAMS['max_depth']}
#define XGB_MODEL_TRAINED   {timestamp}
#define XGB_MODEL_OOS_BRIER {best_brier:.4f}

""")
        # XGBFindModel dispatcher
        f.write("int XGBFindModel(string symbol, int period)\n{\n")
        for info in all_info:
            sym = info["symbol"]
            per = info["period"]
            idx = info["index"]
            f.write(f'   if(StringFind(symbol, "{sym}") == 0 && period == {per}) return({idx});\n')
        f.write("   return(-1);\n}\n\n")

        # Tree functions
        for tc in all_tree_code:
            f.write(tc)
            f.write("\n\n")

        # Per-model predict functions
        for pf in all_predict_fns:
            f.write(pf)
            f.write("\n")

        # Main dispatcher
        tree_args = build_tree_args(all_info[0]["feature_cols"] if "feature_cols" in all_info[0]
                                     else model_list[0][0]["feature_cols"])
        f.write(f"double XGBPredict(\n{chr(10).join(PREDICT_PARAMS)}\n)\n{{\n")
        f.write("   int idx = XGBFindModel(Symbol(), Period());\n")
        f.write("   if(idx < 0) return(50.0);\n")
        for i in range(len(model_list)):
            feature_cols_i = model_list[i][0]["feature_cols"]
            args_i = build_tree_args(feature_cols_i)
            kw = "if" if i == 0 else "else if"
            f.write(f"   {kw}(idx == {i}) return(XGBPredictModel{i}({args_i}));\n")
        f.write("   return(50.0);\n}\n\n#endif\n")

    print(f"\nExported {len(model_list)} models to: {output_path}")


# ─── Binary Export (V12.2 runtime loading) ──────────────────────────
XGB_BIN_MAGIC = 0x58474231
XGB_BIN_VERSION = 1

FEATURE_INDEX_MAP = {
    "RSI_AT_SIGNAL": 0,    "ANGLE_Z": 1,          "ATR_RATIO": 2,
    "SL_DIST_ATR": 3,      "TP1_DIST_ATR": 4,     "RR_RATIO": 5,
    "SPREAD_PIPS": 6,      "TIME_IN_SESSION_MIN": 7,
    "MTF_AGREE_PCT": 8,    "SPREAD_RATIO": 9,     "WF_ROBUST": 10,
    "MTF_H4_TREND": 11,    "MTF_H1_TREND": 12,    "D1_TREND": 13,
    "CASE_NUM": 14,        "DIR_BIN": 15,         "SESSION_ENC": 16,
    "HOUR_SIN": 17,        "HOUR_COS": 18,
    "DOW_SIN": 19,         "DOW_COS": 20,
    "ADX_VALUE": 21,       "MACD_HISTOGRAM": 22,
    "MACD_SLOPE": 23,      "US10Y_TREND": 24,
    # index 25 intentionally unused — reserved slot in XGBPredict()'s
    # MQL feature array for future additions.
}
N_FEATURES_BIN = 26


def build_tree_nodes(booster, tree_index: int, feature_cols: list) -> list:
    """Convert one XGBoost tree to flat node list (depth-first pre-order).

    Returns list of dicts: {feature_index, threshold, left_child, right_child, leaf_value}.
    Node indices are 0-based within this tree.
    """
    tree_df = booster.trees_to_dataframe()
    tree_df = tree_df[tree_df["Tree"] == tree_index].copy()

    node_map = {}
    for _, row in tree_df.iterrows():
        # XGBoost trees_to_dataframe() uses 'ID' for node names (e.g. '0-0', '1-1')
        node_id = row.get("ID", row.get("Node"))
        node_map[node_id] = row

    flat_nodes = []
    old_to_new = {}

    def dfs(old_id):
        new_id = len(flat_nodes)
        old_to_new[old_id] = new_id
        node = node_map[old_id]

        if node["Feature"] == "Leaf":
            flat_nodes.append({
                "feature_index": -1,
                "threshold": 0.0,
                "left_child": -1,
                "right_child": -1,
                "leaf_value": float(node["Gain"]),
            })
            return

        feat_name = node["Feature"]
        fi = FEATURE_INDEX_MAP.get(feat_name, -1)
        if fi < 0 and feat_name in feature_cols:
            fi = feature_cols.index(feat_name)

        flat_nodes.append({
            "feature_index": fi,
            "threshold": float(node["Split"]),
            "left_child": -1,
            "right_child": -1,
            "leaf_value": 0.0,
        })

        dfs(node["Yes"])
        flat_nodes[new_id]["left_child"] = old_to_new[node["Yes"]]

        dfs(node["No"])
        flat_nodes[new_id]["right_child"] = old_to_new[node["No"]]

    root_id = f"{tree_index}-0"
    if root_id not in node_map:
        # Fallback if using integer nodes
        root_id = 0
    dfs(root_id)
    return flat_nodes


def serialize_model_block(results: dict, symbol: str, tf: str) -> tuple:
    """Serialize one trained model to its binary block (V12.2 runtime format).

    Block layout: symbol(16B) + period/n_trees/n_features(int x3) +
    oos_brier/oos_auc(double x2) + per-tree [n_nodes(int) + nodes(28B each)].
    This is the same byte layout written inline into the merged multi-model
    file by export_model_binary() — factored out so model_registry.py can
    reuse identical packing for single-version archive snapshots without
    re-training.

    Returns (block_bytes, n_trees, n_nodes).
    """
    model = results["model"]
    feature_cols = results["feature_cols"]
    booster = model.get_booster()
    n_trees = booster.num_boosted_rounds()
    period = TF_TO_PERIOD.get(tf, 0)

    chunks = []
    total_nodes = 0

    # Symbol: 16 bytes null-padded ASCII
    sym_bytes = symbol.encode("ascii")[:16].ljust(16, b"\x00")
    chunks.append(sym_bytes)

    chunks.append(struct.pack("<iii", period, n_trees, len(feature_cols)))
    chunks.append(struct.pack("<dd", results["oos_brier"], results["oos_auc"]))

    for t in range(n_trees):
        nodes = build_tree_nodes(booster, t, feature_cols)
        chunks.append(struct.pack("<i", len(nodes)))
        for nd in nodes:
            chunks.append(struct.pack("<idii d",
                nd["feature_index"],
                nd["threshold"],
                nd["left_child"],
                nd["right_child"],
                nd["leaf_value"]))
        total_nodes += len(nodes)

    return b"".join(chunks), n_trees, total_nodes


def export_model_binary(model_list: list, output_path: str):
    """Export multiple models to a single binary file (V12.2 runtime format).

    model_list: [(results, symbol, tf), ...]
    Writes to a temp file then atomically renames (prevents MQL from reading partial writes).
    """
    timestamp = int(time.time())

    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.isdir(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=output_dir, suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "wb") as f:
            # File header (28 bytes)
            f.write(struct.pack("<iiiii",
                XGB_BIN_MAGIC, XGB_BIN_VERSION, len(model_list),
                timestamp, N_FEATURES_BIN))
            f.write(struct.pack("<d", 0.0))  # reserved

            total_trees = 0
            total_nodes = 0

            for results, symbol, tf in model_list:
                block, n_trees, n_nodes = serialize_model_block(results, symbol, tf)
                f.write(block)
                total_trees += n_trees
                total_nodes += n_nodes

        os.replace(tmp_path, output_path)
        print(f"\n[BIN] Exported {len(model_list)} models, {total_trees} trees, "
              f"{total_nodes} nodes to: {output_path}")
        print(f"[BIN] File size: {os.path.getsize(output_path)} bytes, timestamp: {timestamp}")

    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


# ─── Calibration Plot ────────────────────────────────────────────────
def save_calibration_plot(results: dict, output_dir: str, label: str = ""):
    if not HAS_MATPLOTLIB:
        return

    try:
        prob_true, prob_pred = calibration_curve(
            results["oos_true"], results["oos_preds"],
            n_bins=8, strategy="quantile"
        )
    except Exception:
        return

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

    ax1.plot([0, 1], [0, 1], "k--", alpha=0.5, label="Perfect")
    ax1.plot(prob_pred, prob_true, "bo-", label="XGBoost OOS")
    ax1.set_xlabel("Mean Predicted Probability")
    ax1.set_ylabel("Fraction of Positives")
    ax1.set_title(f"Calibration {label} (Brier={results['oos_brier']:.4f})")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.hist(results["oos_preds"], bins=20, edgecolor="black", alpha=0.7)
    ax2.set_xlabel("Predicted Probability")
    ax2.set_ylabel("Count")
    ax2.set_title("Prediction Distribution")
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    suffix = f"_{label}" if label else ""
    plot_path = os.path.join(output_dir, f"xgb_calibration{suffix}.png")
    plt.savefig(plot_path, dpi=100)
    plt.close()
    print(f"  Saved calibration plot: {plot_path}")


# ─── SHAP Feature Importance Report ──────────────────────────────────
def save_shap_report(results: dict, output_dir: str, label: str = ""):
    """Compute SHAP feature importance and write a JSON report (+ PNG if available).

    Purely additive reporting — does not affect the trained model, the
    exported binary, or any runtime prediction path.
    """
    if not HAS_SHAP:
        return

    try:
        model = results["model"]
        feature_cols = results["feature_cols"]
        X = results["X_train_full"]

        explainer = shap.TreeExplainer(model)
        shap_values = explainer.shap_values(X)

        mean_abs_shap = np.abs(shap_values).mean(axis=0)
        mean_shap = shap_values.mean(axis=0)

        report = []
        for i, feat in enumerate(feature_cols):
            report.append({
                "feature": feat,
                "mean_abs_shap": float(mean_abs_shap[i]),
                "mean_shap": float(mean_shap[i]),
            })
        report.sort(key=lambda r: r["mean_abs_shap"], reverse=True)
        for rank, row in enumerate(report, start=1):
            row["rank"] = rank

        os.makedirs(output_dir, exist_ok=True)
        suffix = f"_{label}" if label else ""
        json_path = os.path.join(output_dir, f"shap_report{suffix}.json")
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)
        print(f"  Saved SHAP report: {json_path}")

        if HAS_MATPLOTLIB:
            top = report[:15]
            fig, ax = plt.subplots(figsize=(8, max(4, 0.35 * len(top))))
            names = [r["feature"] for r in reversed(top)]
            vals = [r["mean_abs_shap"] for r in reversed(top)]
            ax.barh(names, vals, color="steelblue")
            ax.set_xlabel("Mean |SHAP value|")
            ax.set_title(f"SHAP Feature Importance {label}")
            plt.tight_layout()
            png_path = os.path.join(output_dir, f"shap_importance{suffix}.png")
            plt.savefig(png_path, dpi=100)
            plt.close()
            print(f"  Saved SHAP plot: {png_path}")

    except Exception as e:
        print(f"  WARNING: SHAP report failed: {e}")


# ─── Inventory (for service) ────────────────────────────────────────
def inventory_signals(data_dirs: list) -> dict:
    """Scan CSV directories, return {(symbol, tf): resolved_count}."""
    counts = {}
    for data_dir in data_dirs:
        if not os.path.isdir(data_dir):
            continue
        for f in glob.glob(os.path.join(data_dir, "outcomes_*.csv")):
            fname = os.path.basename(f)
            m = re.match(r"outcomes_(.+)_([A-Z0-9]+)_\d{4}\.csv", fname)
            if not m:
                continue
            symbol, tf = m.group(1), m.group(2)
            try:
                df = pd.read_csv(f)
                resolved = len(df[df["OUTCOME"] != "PENDING"])
            except Exception:
                resolved = 0
            key = (symbol, tf)
            counts[key] = counts.get(key, 0) + resolved
    return counts


# ─── Main ────────────────────────────────────────────────────────────
def train_single(data_dirs: list, symbol: str, tf: str, output_path: str,
                 force: bool = False, json_output: bool = False) -> dict:
    """Train one model for a specific symbol+TF. Returns result dict for JSON output."""
    label = f"{symbol}_{tf}"
    print(f"\n{'='*60}")
    print(f"Training model: {label}")
    print(f"{'='*60}")

    df = load_and_merge(data_dirs, symbol, tf)

    if df.empty or len(df) < MIN_SIGNALS_TOTAL:
        n = len(df) if not df.empty else 0
        msg = f"Only {n} resolved signals for {label}. Need {MIN_SIGNALS_TOTAL}."
        print(f"SKIP: {msg}")
        return {"symbol": symbol, "tf": tf, "status": "skip", "signals": n, "message": msg}

    if "SIGNAL_TIME" in df.columns:
        df = df.sort_values("SIGNAL_TIME").reset_index(drop=True)

    df, feature_cols = engineer_features(df)
    print(f"\nFeatures ({len(feature_cols)}): {feature_cols}")
    print(f"Target distribution: {df['target'].value_counts().to_dict()}")

    results = train_and_validate(df, feature_cols)
    if results is None:
        return {"symbol": symbol, "tf": tf, "status": "fail", "signals": len(df),
                "message": "Not enough data for walk-forward validation"}

    passed = validate_model(results)

    plot_dir = os.path.dirname(output_path) or "."
    save_calibration_plot(results, plot_dir, label)
    shap_dir = str(Path(__file__).parent / "shap_reports")
    save_shap_report(results, shap_dir, label)

    if passed or force:
        if not passed:
            print(f"\nWARNING: Exporting {label} despite validation failure (--force)")

        export_single_model(results, output_path, symbol, tf)

        return {"symbol": symbol, "tf": tf, "status": "pass", "signals": len(df),
                "brier": round(results["oos_brier"], 4),
                "auc": round(results["oos_auc"], 4),
                "trees": results["model"].get_booster().num_boosted_rounds(),
                "output": output_path, "results": results}
    else:
        return {"symbol": symbol, "tf": tf, "status": "fail", "signals": len(df),
                "brier": round(results["oos_brier"], 4),
                "auc": round(results["oos_auc"], 4),
                "message": "Validation failed"}


def main():
    parser = argparse.ArgumentParser(description="XGBoost training for QuantEdge_RSI V12")
    parser.add_argument("--data-dir", required=True, nargs="+",
                        help="One or more directories containing signal/scoring/outcome CSVs")
    parser.add_argument("--output", default=None,
                        help="Output XGBModel.mqh path")
    parser.add_argument("--symbol", default=None,
                        help="Filter by symbol (e.g., XAUUSD)")
    parser.add_argument("--tf", default=None,
                        help="Filter by timeframe (e.g., H1)")
    parser.add_argument("--force", action="store_true",
                        help="Export even if validation fails")
    parser.add_argument("--json-output", action="store_true",
                        help="Output JSON summary to stdout (for service integration)")
    parser.add_argument("--inventory", action="store_true",
                        help="Only scan and report signal counts, do not train")
    parser.add_argument("--output-format", default="mql", choices=["mql", "bin"],
                        help="Output format: mql (source code, default) or bin (binary for runtime loading)")
    args = parser.parse_args()

    if args.output is None:
        script_dir = Path(__file__).parent.parent
        if args.output_format == "bin":
            common_files = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal" / "Common" / "Files"
            args.output = str(common_files / "QuantEdge_RSI" / "XGBModels.bin")
        else:
            args.output = str(script_dir / "Include" / "QuantEdge" / "AI" / "XGBModel.mqh")

    data_dirs = args.data_dir

    if args.inventory:
        counts = inventory_signals(data_dirs)
        if args.json_output:
            out = [{"symbol": s, "tf": t, "resolved": c} for (s, t), c in sorted(counts.items())]
            print(json.dumps(out, indent=2))
        else:
            print(f"\n{'Symbol':<15} {'TF':<6} {'Resolved':>10}")
            print("-" * 35)
            for (s, t), c in sorted(counts.items()):
                status = "READY" if c >= MIN_SIGNALS_TOTAL else f"need {MIN_SIGNALS_TOTAL - c} more"
                print(f"{s:<15} {t:<6} {c:>10}  {status}")
        return

    if args.symbol and args.tf:
        result = train_single(data_dirs, args.symbol, args.tf, args.output, args.force, args.json_output)
        if result["status"] == "pass" and args.output_format == "bin" and "results" in result:
            export_model_binary([(result["results"], args.symbol, args.tf)], args.output)
        if args.json_output:
            out = {k: v for k, v in result.items() if k != "results"}
            print(json.dumps(out, indent=2))
        if result["status"] == "fail" and not args.force:
            sys.exit(1)
    elif args.symbol or args.tf:
        print("ERROR: --symbol and --tf must be used together.")
        sys.exit(1)
    else:
        # Legacy mode: train all data together as one model
        df = load_and_merge(data_dirs)
        if df.empty or len(df) < MIN_SIGNALS_TOTAL:
            n = len(df) if not df.empty else 0
            print(f"\nERROR: Only {n} resolved signals. Need {MIN_SIGNALS_TOTAL}.")
            sys.exit(1)

        if "SIGNAL_TIME" in df.columns:
            df = df.sort_values("SIGNAL_TIME").reset_index(drop=True)

        df, feature_cols = engineer_features(df)
        print(f"\nFeatures ({len(feature_cols)}): {feature_cols}")
        print(f"Target distribution: {df['target'].value_counts().to_dict()}")

        results = train_and_validate(df, feature_cols)
        if results is None:
            sys.exit(1)

        passed = validate_model(results)
        save_calibration_plot(results, os.path.dirname(args.output) or ".")

        if passed or args.force:
            symbols = df["SYMBOL"].unique() if "SYMBOL" in df.columns else ["unknown"]
            tfs = df["TF"].unique() if "TF" in df.columns else ["unknown"]
            sym = str(symbols[0]) if len(symbols) == 1 else "MULTI"
            tf_str = str(tfs[0]) if len(tfs) == 1 else "MULTI"
            if args.output_format == "bin":
                export_model_binary([(results, sym, tf_str)], args.output)
                print(f"\nDone. Model auto-loaded by indicator (no recompile needed).")
            else:
                export_single_model(results, args.output, sym, tf_str)
                print(f"\nDone. Recompile the indicator to use the new model.")
                print(f"Remember to delete QuantEdge_SESS_*.bin files after recompiling.")
        else:
            print("\nModel NOT exported — validation failed.")
            sys.exit(1)


if __name__ == "__main__":
    main()
