# Trade Matcher - dev split evaluation (tuning set, seed 42)

> **This is the dev / tuning split, not a generalisation estimate.**
> The keyword tables were designed against the failures of exactly these 104 rows,
> so the accuracy below is an upper bound fitted to this split. The honest number
> comes from the untouched test split in `reports/trade_matcher_tuning.md`
> (`scripts/eval_trade_test.py`, seed 2026, scored once).

- Generated: 2026-10-26 17:54
- Script: `scripts/eval_holdout.py` (re-runnable, fixed seed)
- Data: `data/job_categorization.parquet`
- Seed: `42`, holdout size: `20%` (grouped by cleaned title, identical text never splits)
- LLM fallback: **disabled** (`get_gemini_model()` patched to `None`), so scores reflect the rule + semantic layers only
- Pipeline under test: `ai_service.resolve_trade_decision()` (keyword detection → `_resolve_detected_trades` arbitration → semantic scoring)

## 1. Data and split

| Item | Value |
| --- | --- |
| Dataset rows | 6539 |
| Categories in dataset | 864 |
| Rows mapped to the 16 canonical trades | 518 (67 categories) |
| Rows excluded (not a construction trade) | 6021 |
| Rows with ambiguous multi-trade category | 25 |
| Train rows (80%, model fit) | 414 |
| Holdout rows (20%, scored) | 104 |
| Unique titles in train / holdout | 414 / 103 |

Ambiguous categories (a title legitimately belongs to more than one trade, e.g. floor covering appears under both `tiling` and `flooring`). A prediction is counted correct when it equals any of the expected trades; the confusion matrix uses the first trade in canonical order:

- `Carpet Installers` → tiling / flooring
- `Floor Layers, Except Carpet, Wood, and Hard Tiles` → tiling / flooring
- `Floor Sanders and Finishers` → tiling / flooring
- `Insulation Workers, Floor, Ceiling, and Wall` → drywall / insulation

## 2. Headline accuracy

| Metric | Honest holdout (model retrained on 80%) | Shipped model `data/trade_matcher.joblib` (trained on 100%) |
| --- | --- | --- |
| Top-1 accuracy (prediction ∈ expected trades) | **100.0%** | 100.0% |
| Exact trade-set match | 93.3% | 94.2% |
| Macro recall over 16 trades | 100.0% | 100.0% |
| Macro strict recall (primary label) | 94.3% | 94.3% |
| No trade identified (skip) | 0 (0.0%) | 0 (0.0%) |

The shipped model was fitted on the full dataset, so it has already seen every holdout title. It scores 100.0% versus 100.0% for the leak-free model — a +0.0 pp optimism that quantifies how much of the previously reported accuracy came from memorising the training titles rather than generalising.

## 3. Per-trade recall (dev split)

`Recall` credits a row when the decision is correct for that trade, i.e. the predicted trade is a member of the expected set; ambiguous categories therefore give credit to every trade they can legitimately map to. `Strict recall` only credits the primary label, so it drops for trades that are usually the secondary side of an ambiguity (e.g. `flooring`, `insulation`).

| Trade | Support (rows where trade is expected) | Recall | Primary support | Strict recall |
| --- | ---: | ---: | ---: | ---: |
| carpenter | 2 | 100.0% | 2 | 100.0% |
| electrical | 13 | 100.0% | 13 | 100.0% |
| plumbing | 3 | 100.0% | 3 | 100.0% |
| masonry | 11 | 100.0% | 11 | 100.0% |
| painting | 4 | 100.0% | 4 | 100.0% |
| welding | 8 | 100.0% | 8 | 100.0% |
| hvac | 7 | 100.0% | 7 | 100.0% |
| roofing | 4 | 100.0% | 4 | 100.0% |
| tiling | 7 | 100.0% | 7 | 14.3% |
| drywall | 5 | 100.0% | 5 | 100.0% |
| glazing | 1 | 100.0% | 1 | 100.0% |
| flooring | 6 | 100.0% | 0 | n/a |
| equipment | 15 | 100.0% | 15 | 100.0% |
| laborer | 17 | 100.0% | 17 | 100.0% |
| insulation | 2 | 100.0% | 2 | 100.0% |
| supervision | 5 | 100.0% | 5 | 100.0% |

## 4. Decision source breakdown (dev split)

| Source | Rows | Correct | Accuracy |
| --- | ---: | ---: | ---: |
| rule | 86 | 86 | 100.0% |
| semantic | 18 | 18 | 100.0% |

## 5. Confusion matrix (dev split)

Rows = expected trade (primary label), columns = predicted trade, `skip` = no trade identified. Diagonal cells are correct. Off-diagonal cells are not automatically wrong: when a category maps to several trades (e.g. floor covering → tiling / flooring), the prediction still counts as correct if it matches any expected trade.

| expected \ predicted | carpenter | electrical | plumbing | masonry | painting | welding | hvac | roofing | tiling | drywall | glazing | flooring | equipment | laborer | insulation | supervision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **carpenter** | **2** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| **electrical** | · | **13** | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| **plumbing** | · | · | **3** | · | · | · | · | · | · | · | · | · | · | · | · | · |
| **masonry** | · | · | · | **11** | · | · | · | · | · | · | · | · | · | · | · | · |
| **painting** | · | · | · | · | **4** | · | · | · | · | · | · | · | · | · | · | · |
| **welding** | · | · | · | · | · | **8** | · | · | · | · | · | · | · | · | · | · |
| **hvac** | · | · | · | · | · | · | **7** | · | · | · | · | · | · | · | · | · |
| **roofing** | · | · | · | · | · | · | · | **4** | · | · | · | · | · | · | · | · |
| **tiling** | · | · | · | · | · | · | · | · | **1** | · | · | 6 | · | · | · | · |
| **drywall** | · | · | · | · | · | · | · | · | · | **5** | · | · | · | · | · | · |
| **glazing** | · | · | · | · | · | · | · | · | · | · | **1** | · | · | · | · | · |
| **equipment** | · | · | · | · | · | · | · | · | · | · | · | · | **15** | · | · | · |
| **laborer** | · | · | · | · | · | · | · | · | · | · | · | · | · | **17** | · | · |
| **insulation** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | **2** | · |
| **supervision** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | **5** |

## 6. Top failure cases (dev split)

`confidence` is the raw pipeline confidence; for semantic decisions it can exceed 1.0 because the score formula adds a seed-hit bonus on top of the normalised cosine similarity. `Top semantic scores` are the highest-scoring trades of the semantic layer.

No failures on the holdout.

## 7. Production model status

- Full-data retrain reproduces the shipped artefact: **yes**
- Vocabulary size: shipped 2177, full retrain 2177
- Per-trade profile title counts: shipped 542, full retrain 542
- Prediction agreement on the holdout between shipped and full-retrain model: 100.0%
- Action taken: no refresh needed — shipped artefact already equals a full-data retrain

No per-trade profile differences against the shipped artefact: the shipped model was already trained on the full dataset with the current `CATEGORY_MAP` and seed keywords, so the holdout experiment does not require a production refresh.

## 8. How to read these numbers

- **This split is the dev / tuning set.** The keyword tables in `app/ai_service.py` were revised against its failures, so the accuracy above is an upper bound fitted to these rows - do not quote it as the model's generalisation. Use `reports/trade_matcher_tuning.md` (fresh test split, seed 2026) for that.
- The gap is not purely "the model is weak": the 80% model also has a smaller TF-IDF vocabulary (some holdout words never appear in the 80% titles), which is a realistic stand-in for new site wording the production model has not seen.
- Holdout per-trade support is small (1–17 rows per trade), so a single miss moves a recall figure by tens of percentage points. Treat per-trade recall as directional and rerun with `--seed` variations before drawing per-trade conclusions.
- The test labels are O*NET occupation titles, not free-text site task descriptions; real tasks are usually longer and more descriptive, which the keyword layer handles better than a bare two-word title.
- LLM fallback was disabled on purpose: these numbers describe the deterministic rule + semantic layers. Production additionally benefits from the Gemini fallback, so the live skip rate should be lower than the one reported here.

## 9. How to reproduce

```bash
cd construction_management_system_Backend
python scripts/eval_holdout.py --seed 42 --test-size 0.2
```

Per-row predictions for this run are in `reports/holdout_predictions.csv` (cleaned text, expected trades, predicted trades, decision source, confidence, scores).

