# Sprint 4: XGB Model Versioning + SHAP + A/B Shadow

> **Goal:** Model version history/rollback, SHAP feature importance export, A/B shadow mode in the indicator
> **Duration:** 1 week
> **Prerequisite:** Sprint 3 (DONE), V12.1/V12.2 auto-train infra (DONE, pre-dates this sprint)
> **Status:** `DONE` (2026-08-06)

---

## Scope Decision

Auto-train infrastructure — system tray service, periodic scan/retrain, CSV auto-export, runtime binary loading in the indicator — shipped in V12.1/V12.2 (`tools/xgb_service.py`, `Include/QuantEdge/AI/XGBModel.mqh`) and is **not** re-implemented here. Sprint 4 = 3 net-new capabilities layered on top of that infra:

1. **Model version history + rollback** — every successful retrain used to silently overwrite the live `XGBModels.bin` with no way to see what changed or revert a regression.
2. **SHAP feature importance export** — gain-based `feature_importances_` was the only importance signal; SHAP adds a more robust, per-prediction-consistent one, for reporting only.
3. **A/B shadow mode** — the indicator can run a second "candidate" model alongside the live one and track/display both Brier scores independently, so a retrain proves itself before being trusted.

Design decisions (confirmed with user before implementation):
- **Auto-promote: Gated.** A passing retrain becomes the *shadow* model, not an automatic champion overwrite (`xgb_config.json`: `"auto_promote": false`). "Promote shadow → champion" and "rollback champion → older version" are the same underlying registry operation (point champion at version X).
- **Indicator shadow code: duplicate file, not shared refactor.** `XGBModelShadow.mqh` duplicates the loader/predictor pattern under separate globals/functions. Only pure binary-format primitives (`XGB_BIN_MAGIC`, `XGB_BIN_VERSION`, `XGB_MAX_MODELS`, `ReadFixedString()`) are reused from `XGBModel.mqh` — these must stay byte-identical between champion/shadow anyway, and are not champion-path decision logic. Zero lines changed in the already-shipped, working `XGBModel.mqh`. Shadow predictions never feed `CombineXGBWithBayesian()`, `XGBIsReady()`, or any EA-facing buffer — purely observational.
- **`ProbabilityEngine.mqh` touched, but additively only.** The plan originally assumed shadow wiring could avoid this file entirely, but `curSig`/`orange`/`bbUp`/`bbLo` (needed by `XGBGetShadowPrediction()`) are local to the STEP 5.1 block and not available in the main `.mq4`/`.mq5` files at the per-signal capture site. The shadow call was added as a single new gated line (`if(InpEnableXGBShadow) g_xgbShadowProbTP1 = XGBGetShadowPrediction(...)`) immediately after the existing `g_xgbProbTP1 = xgbProb;` line, strictly before the `PROB_XGBOOST`/`PROB_ENSEMBLE` branch. It reads existing in-scope locals and writes only to the new `g_xgbShadowProbTP1` global — zero existing lines changed, zero existing state read or written. With `InpEnableXGBShadow=false` (default) behavior is byte-identical to pre-Sprint-4. This satisfies the intent of Master Plan Rule #2 (protect the champion decision path from drift) without literally requiring Walk-Forward re-validation, since no decision-path behavior changes.

---

## Tasks

| # | Task | Status | Files |
|---|---|---|---|
| 4.1 | Model version registry (archive/list/promote/rollback) | `DONE` | `tools/model_registry.py` (new) |
| 4.2 | Extract `serialize_model_block()` for registry reuse | `DONE` | `tools/quantedge_xgboost_train.py` |
| 4.3 | SHAP feature importance export | `DONE` | `tools/quantedge_xgboost_train.py`, `tools/requirements.txt` |
| 4.4 | Gated promotion flow + shadow `.bin` output + tray menu | `DONE` | `tools/xgb_service.py`, `tools/xgb_config.json` |
| 4.5 | Shadow model loader/predictor (indicator) | `DONE` | `Include/QuantEdge/AI/XGBModelShadow.mqh` (new) |
| 4.6 | Shadow prediction + Brier tracking helpers | `DONE` | `Include/QuantEdge/AI/XGBIntegration.mqh` |
| 4.7 | Shadow field/globals/input plumbing | `DONE` | `Structs.mqh`, `Globals.mqh`, `Config.mqh` |
| 4.8 | Shadow panel line (A/B Brier comparison) | `DONE` | `Include/QuantEdge/Display/PanelDrawing.mqh` |
| 4.9 | Wire shadow prediction call (additive) + per-signal capture | `DONE` | `Include/QuantEdge/Engine/ProbabilityEngine.mqh`, `QuantEdge_RSI.mq4`, `.mq5` |
| 4.10 | Update MASTER_PLAN + this file | `DONE` | `MASTER_PLAN.md`, `SPRINT_4_XGB_AUTOTRAIN.md` |
| 4.11 | Compile verify (MQ4 + MQ5) — USER | `NOT STARTED` | *(user task, Rule #5)* |

### 4.1 Model Version Registry

`tools/model_registry.py` — manifest-based versioning per `(symbol, tf)`:
- Manifest at `tools/model_history/<symbol>_<tf>/manifest.json`: list of `{version_id, timestamp, brier, auc, n_signals, file_path, role}`, `role ∈ {"champion", "shadow", "archived"}` — exactly one `"champion"`, at most one `"shadow"` per key.
- Each version's raw model bytes stored standalone at `tools/model_history/<symbol>_<tf>/<version_id>.bin` (single-model binary block, reusing the existing header+block format) so any version can be read back and re-spliced without re-training.
- `archive_version()`, `list_versions()`, `get_champion()`, `get_shadow()`, `promote_shadow_to_champion()`, `rollback_champion()`, `all_keys()`, `assemble_role_binary(role, output_path)` (rebuilds a merged multi-model `.bin` from per-key champion/shadow raw bytes across the registry — no re-training).

### 4.2 `serialize_model_block()` Extraction

`export_model_binary()` in `quantedge_xgboost_train.py` used to inline the per-model `struct.pack` loop. Extracted into `serialize_model_block(results, symbol, tf) -> bytes`; `export_model_binary()` is now header + `serialize_model_block()` per entry, written via the unchanged atomic temp-file + `os.replace()` pattern. Lets `model_registry.py` reuse identical byte-packing for fresh trains and reuse raw bytes (no re-training) for archived/promoted versions.

### 4.3 SHAP Feature Importance Export

- `import shap` guarded by `HAS_SHAP` flag (same optional-dependency pattern as `HAS_MATPLOTLIB`).
- `save_shap_report(results, output_dir, label)` called from `train_single()` next to the existing `save_calibration_plot()` call site: `shap.TreeExplainer(final_model).shap_values(X)` → `tools/shap_reports/<label>.json` (`{feature, mean_abs_shap, mean_shap, rank}` per feature) + bar-chart PNG when matplotlib is available.
- Pure post-hoc reporting — no change to `XGBPredict()` or any runtime path.
- `tools/requirements.txt`: added `shap`.

### 4.4 Gated Promotion Flow (Service + Tray)

- `xgb_config.json`: `"auto_promote": false` (default). If `true`, restores old V12.1/V12.2 behavior (retrain directly overwrites champion).
- `archive_newly_trained(trained_models, auto_promote)`: archives each newly-passing retrain with `role="champion"` if `auto_promote` else `role="shadow"`.
- `rebuild_merged_binaries()`: assembles the live champion `.bin` and the shadow `.bin` (`XGBModels_shadow.bin`, same `Common/Files/QuantEdge_RSI/` directory) from already-archived registry bytes — avoids re-training every passing model every scan cycle.
- New tray menu items (via `TrayService`, live-reloading `model_registry` per action so edits apply without a service restart):
  - **Promote Shadow → Champion** (`on_promote_shadow`): promotes every key with a pending shadow, re-assembles both champion and shadow merged binaries.
  - **Rollback Champion** (`on_rollback_champion`): for each key, finds the most recent `archived` version older than the current champion and rolls back to it, re-assembles the champion binary.
  - **View Model History** (`on_view_history`): notification summary of champion/shadow version + Brier per key.

### 4.5 Shadow Model Loader (Indicator)

`Include/QuantEdge/AI/XGBModelShadow.mqh` (new) — duplicates `XGBModel.mqh`'s structs/globals/functions under shadow-specific names, reading `Common/Files/QuantEdge_RSI/XGBModels_shadow.bin`:
- Structs: `XGBShadowNode`, `XGBShadowTreeMeta`, `XGBShadowModelMeta`.
- Globals: `g_xgbShadowNodes[]`, `g_xgbShadowTrees[]`, `g_xgbShadowModels[]`, `g_xgbShadowLoaded`, `g_xgbShadowFileTimestamp`, `g_xgbShadowBestBrier`, `g_xgbShadowLastCheck`.
- Functions: `LoadXGBShadowModel()`, `CheckXGBShadowReload()` (300s auto-reload, mirrors champion's 5-min cadence), `XGBFindShadowModel()`, `EvalShadowTree()`, `XGBPredictShadow(...)` — 19-param signature identical to `XGBPredict()`.
- Shares only pure binary-format constants (`XGB_BIN_MAGIC`, `XGB_BIN_VERSION`, `XGB_MAX_MODELS`) and the `ReadFixedString()` helper with `XGBModel.mqh` — no loader/predictor logic shared.

### 4.6 Shadow Prediction + Brier Tracking

`Include/QuantEdge/AI/XGBIntegration.mqh`:
- `XGBGetShadowPrediction(sig, orange, bbUp, bbLo)` mirrors `XGBGetPrediction()`, calling `XGBPredictShadow()`.
- `UpdateXGBShadowBrierMetrics()` mirrors `UpdateXGBBrierMetrics()`, reading `g_signals[si].xgbShadowPredictedProb` and writing `g_xgbShadowBrierSamples`/`g_xgbShadowBrierScore` instead of the champion equivalents.

### 4.7 Shadow Field/Globals/Input Plumbing

- `Structs.mqh`: `double xgbShadowPredictedProb;` added to `SignalData`, next to `xgbPredictedProb`.
- `Globals.mqh`: `g_xgbShadowProbTP1`, `g_xgbShadowBrierScore` (init 0.25, random baseline), `g_xgbShadowBrierSamples`.
- `Config.mqh`: `input bool InpEnableXGBShadow = false;` in the Probability Engine input group — single shared file included once by both `.mq4`/`.mq5`, so this one line satisfies MQ4/MQ5 sync automatically.

### 4.8 Shadow Panel Line

`Include/QuantEdge/Display/PanelDrawing.mqh` — conditional line shown only when `InpEnableXGBShadow && g_xgbShadowLoaded`, right after the existing champion XGB line: `Candidate: XX.X% Brier:0.YYY [n=NN]`. Labeled **"Candidate:"** rather than "Shadow:" to avoid colliding with the pre-existing, unrelated `"[shadow N/20]"` tag on the champion line (that one means "not yet Brier-qualified" — a different concept). Line color turns `clrLime` when the candidate's Brier score beats the champion's and has enough samples (`MIN_XGB_BRIER_SAMPLES`).

### 4.9 Shadow Prediction Wiring

- `ProbabilityEngine.mqh` STEP 5.1 (additive, gated, see Scope Decision above): shadow call inserted immediately after `g_xgbProbTP1 = xgbProb;`, before the `PROB_XGBOOST`/`PROB_ENSEMBLE` branch.
- `QuantEdge_RSI.mq4` / `.mq5` (4 sites each, kept in sync):
  - After `LoadXGBModels()`: `if(InpEnableXGBShadow) LoadXGBShadowModel();`
  - After `CheckXGBReload()`: `if(InpEnableXGBShadow) CheckXGBShadowReload();`
  - After `UpdateXGBBrierMetrics()`: `if(InpEnableXGBShadow) UpdateXGBShadowBrierMetrics();`
  - Next to the existing `g_signals[g_activeSignalIndex].xgbPredictedProb = ...` capture: sibling `if(InpEnableXGBShadow && ...) g_signals[g_activeSignalIndex].xgbShadowPredictedProb = g_xgbShadowProbTP1;`

**Explicit non-goals (mirroring Sprint 3's "NOT touched" callout):**
- No changes to `SLTP.mqh`, `SLTPOptimizer.mqh`, `Normalize.mqh`, `CombineXGBWithBayesian()`, `XGBIsReady()` — shadow prediction never influences the real decision/probability path.
- No new/changed EA-facing buffers — buffer count stays locked at 25 per `12_EA_EXPORT_CONTRACT.md`.
- `XGBPredict()`'s existing 19-param signature and champion loading path untouched.
- `ProbabilityEngine.mqh` changed by exactly one new statement (see 4.9) — no existing line modified.

---

## Acceptance Criteria

- [x] `tools/model_registry.py` created — archive/list/get-champion/get-shadow/promote/rollback/assemble-binary
- [x] `serialize_model_block()` extracted and reused by both fresh-train export and registry re-assembly
- [x] SHAP report (`tools/shap_reports/<label>.json` + optional PNG) generated per training run when `shap` installed
- [x] `xgb_config.json` has `"auto_promote": false` — passing retrains archive as shadow, champion `.bin` untouched until a promote/rollback action runs
- [x] Tray has "Promote Shadow → Champion", "Rollback Champion", "View Model History" — all live-reload `model_registry` so edits apply without a service restart
- [x] `Include/QuantEdge/AI/XGBModelShadow.mqh` created — loads `XGBModels_shadow.bin`, zero shared decision logic with `XGBModel.mqh`
- [x] `InpEnableXGBShadow` defaults `false` — zero cost when off (no shadow file access, no extra CPU)
- [x] Panel shows "Candidate:" line only when shadow enabled and loaded, independent Brier/sample tracking from champion
- [x] Shadow prediction wiring is strictly additive in `ProbabilityEngine.mqh` — zero existing lines changed, zero existing state read/written
- [x] Zero new indicator buffers — buffer count remains 25
- [x] MQ4/MQ5 shadow call sites verified identical (4 sites each) via grep diff
- [x] MASTER_PLAN.md updated: Sprint 4 status, dates, AI Training readiness score
- [ ] MQ4 compile 0 errors (user verify)
- [ ] MQ5 compile 0 errors (user verify)
- [ ] With `InpEnableXGBShadow=true` + `XGBModels_shadow.bin` present: panel shows both champion and candidate Brier lines updating independently (user verify)
- [ ] `xgb_service.py --train-now` with `auto_promote:false`: champion `.bin` timestamp unchanged after a passing retrain, `XGBModels_shadow.bin` updated instead; tray "Promote Shadow → Champion" then updates champion timestamp (user verify)

---

## Files Changed/Created (13)

| File | Change |
|------|--------|
| `tools/model_registry.py` | New — version manifest, archive/promote/rollback, binary re-assembly |
| `tools/quantedge_xgboost_train.py` | Extracted `serialize_model_block()`; added `save_shap_report()` + `HAS_SHAP` guard |
| `tools/xgb_service.py` | Gated promotion flow (`archive_newly_trained`, `rebuild_merged_binaries`), 3 new tray handlers |
| `tools/xgb_config.json` | Added `"auto_promote": false` |
| `tools/requirements.txt` | Added `shap` |
| `Include/QuantEdge/AI/XGBModelShadow.mqh` | New — duplicated shadow loader/predictor, shares only binary-format primitives |
| `Include/QuantEdge/AI/XGBIntegration.mqh` | Added `XGBGetShadowPrediction()`, `UpdateXGBShadowBrierMetrics()` |
| `Include/QuantEdge/Core/Structs.mqh` | Added `xgbShadowPredictedProb` field to `SignalData` |
| `Include/QuantEdge/Core/Globals.mqh` | Added `g_xgbShadowProbTP1`, `g_xgbShadowBrierScore`, `g_xgbShadowBrierSamples` |
| `Include/QuantEdge/Core/Config.mqh` | Added `InpEnableXGBShadow` input (shared file — syncs both platforms) |
| `Include/QuantEdge/Display/PanelDrawing.mqh` | Added conditional "Candidate:" Brier line |
| `Include/QuantEdge/Engine/ProbabilityEngine.mqh` | Added 1 additive, gated line (shadow prediction call) — see Scope Decision |
| `QuantEdge_RSI.mq4` / `.mq5` | Added 4 gated shadow call sites each, kept in sync |
| `Document_System/Plans/MASTER_PLAN.md` | Sprint 4 → DONE, dates, AI Training readiness score, changelog |
| `Document_System/Plans/SPRINT_4_XGB_AUTOTRAIN.md` | Populated from stub with tasks/acceptance/files |

**NOT touched:** `Include/QuantEdge/AI/XGBModel.mqh` (champion loader, zero lines changed), `Include/QuantEdge/Engine/SLTP.mqh`, `SLTPOptimizer.mqh`, `Include/QuantEdge/Analysis/Normalize.mqh`, `CombineXGBWithBayesian()`/`XGBIsReady()` logic, EA-facing buffer layout (still 25 buffers), `XGBPredict()` signature.
