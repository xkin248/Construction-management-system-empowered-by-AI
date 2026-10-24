# Trade Matcher Holdout Evaluation

- Generated: 2026-10-24 18:22
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
| Top-1 accuracy (prediction ∈ expected trades) | **78.8%** | 93.3% |
| Exact trade-set match | 72.1% | 87.5% |
| Macro recall over 16 trades | 81.6% | 94.2% |
| Macro strict recall (primary label) | 74.6% | 88.1% |
| No trade identified (skip) | 7 (6.7%) | 0 (0.0%) |

The shipped model was fitted on the full dataset, so it has already seen every holdout title. It scores 93.3% versus 78.8% for the leak-free model — a +14.4 pp optimism that quantifies how much of the previously reported accuracy came from memorising the training titles rather than generalising.

## 3. Per-trade recall (honest holdout)

`Recall` credits a row when the decision is correct for that trade, i.e. the predicted trade is a member of the expected set; ambiguous categories therefore give credit to every trade they can legitimately map to. `Strict recall` only credits the primary label, so it drops for trades that are usually the secondary side of an ambiguity (e.g. `flooring`, `insulation`).

| Trade | Support (rows where trade is expected) | Recall | Primary support | Strict recall |
| --- | ---: | ---: | ---: | ---: |
| carpenter | 2 | 50.0% | 2 | 50.0% |
| electrical | 13 | 92.3% | 13 | 92.3% |
| plumbing | 3 | 66.7% | 3 | 66.7% |
| masonry | 11 | 36.4% | 11 | 36.4% |
| painting | 4 | 100.0% | 4 | 100.0% |
| welding | 8 | 100.0% | 8 | 100.0% |
| hvac | 7 | 57.1% | 7 | 57.1% |
| roofing | 4 | 100.0% | 4 | 100.0% |
| tiling | 7 | 100.0% | 7 | 14.3% |
| drywall | 5 | 100.0% | 5 | 100.0% |
| glazing | 1 | 100.0% | 1 | 100.0% |
| flooring | 6 | 100.0% | 0 | n/a |
| equipment | 15 | 100.0% | 15 | 100.0% |
| laborer | 17 | 52.9% | 17 | 52.9% |
| insulation | 2 | 50.0% | 2 | 50.0% |
| supervision | 5 | 100.0% | 5 | 100.0% |

## 4. Decision source breakdown (honest holdout)

| Source | Rows | Correct | Accuracy |
| --- | ---: | ---: | ---: |
| rule | 68 | 61 | 89.7% |
| semantic | 29 | 21 | 72.4% |
| skip | 7 | 0 | 0.0% |

## 5. Confusion matrix (honest holdout)

Rows = expected trade (primary label), columns = predicted trade, `skip` = no trade identified. Diagonal cells are correct. Off-diagonal cells are not automatically wrong: when a category maps to several trades (e.g. floor covering → tiling / flooring), the prediction still counts as correct if it matches any expected trade.

| expected \ predicted | carpenter | electrical | plumbing | masonry | painting | welding | hvac | roofing | tiling | drywall | glazing | flooring | equipment | laborer | insulation | supervision | skip |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **carpenter** | **1** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 1 |
| **electrical** | · | **12** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 1 |
| **plumbing** | · | · | **2** | · | · | · | · | · | · | · | · | · | 1 | · | · | · | · |
| **masonry** | 1 | · | · | **4** | · | 1 | · | · | 4 | · | · | · | · | · | · | · | 1 |
| **painting** | · | · | · | · | **4** | · | · | · | · | · | · | · | · | · | · | · | · |
| **welding** | · | · | · | · | · | **8** | · | · | · | · | · | · | · | · | · | · | · |
| **hvac** | · | · | · | · | · | 1 | **4** | · | · | · | · | · | 1 | · | · | · | 1 |
| **roofing** | · | · | · | · | · | · | · | **4** | · | · | · | · | · | · | · | · | · |
| **tiling** | · | · | · | · | · | · | · | · | **1** | · | · | 6 | · | · | · | · | · |
| **drywall** | · | · | · | · | · | · | · | · | · | **5** | · | · | · | · | · | · | · |
| **glazing** | · | · | · | · | · | · | · | · | · | · | **1** | · | · | · | · | · | · |
| **equipment** | · | · | · | · | · | · | · | · | · | · | · | · | **15** | · | · | · | · |
| **laborer** | · | · | · | · | 2 | · | · | · | · | · | 1 | · | 2 | **9** | · | · | 3 |
| **insulation** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | **1** | 1 | · |
| **supervision** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | **5** | · |

## 6. Top failure cases (honest holdout)

`confidence` is the raw pipeline confidence; for semantic decisions it can exceed 1.0 because the score formula adds a seed-hit bonus on top of the normalised cosine similarity. `Top semantic scores` are the highest-scoring trades of the semantic layer.

| # | Task text (as cleaned) | Expected | Predicted | Source | Confidence | Top semantic scores |
| ---: | --- | --- | --- | --- | ---: | --- |
| 1 | car wash attendant | laborer | skip | skip | 0.00 | painting=1.0, laborer=0.8688 |
| 2 | curbstone setter | masonry | skip | skip | 0.00 | welding=1.0, masonry=0.9006 |
| 3 | marquetry worker | carpenter | skip | skip | 0.00 | drywall=1.0, insulation=0.9917, masonry=0.9163 |
| 4 | stoker installer | hvac | skip | skip | 0.00 | tiling=1.0, glazing=0.9183, flooring=0.7457 |
| 5 | shrub planter | laborer | skip | skip | 0.00 | - |
| 6 | house wirer | electrical | skip | skip | 0.00 | carpenter=1.0, electrical=0.8795 |
| 7 | sod layer | laborer | skip | skip | 0.00 | tiling=1.0, masonry=0.9184, plumbing=0.8761 |
| 8 | radiological control and safety technician | insulation | supervision | semantic | 1.00 | supervision=1.0, glazing=0.5509 |
| 9 | marble chip terrazzo worker | masonry | tiling | rule | 1.14 | tiling=1.1396, masonry=1.0 |
| 10 | post tensioning ironworker | masonry | welding | rule | 1.60 | welding=1.6 |
| 11 | sewage screen operator | plumbing | equipment | rule | 1.60 | equipment=1.6, welding=0.7217, hvac=0.5057 |
| 12 | boiler room operator | hvac | equipment | rule | 0.97 | welding=1.0, equipment=0.9655, hvac=0.7937 |
| 13 | pottery kiln builder | masonry | carpenter | semantic | 1.00 | carpenter=1.0, electrical=0.7096, masonry=0.5409 |
| 14 | automobile detailer | laborer | painting | semantic | 1.00 | painting=1.0 |
| 15 | terrazzo installer | masonry | tiling | rule | 1.70 | tiling=1.7, masonry=0.5855 |

7 of the shown cases were **skipped**: no keyword hit and the semantic layer had no decisive winner (either no trade reached 0.5, or the best trade beat the runner-up by less than the 0.15 gap required by the semantic supplement). With only 80% of the titles in training, their wording is out of vocabulary, which is exactly the generalisation gap this evaluation measures.

## 7. Production model status

- Full-data retrain reproduces the shipped artefact: **yes**
- Vocabulary size: shipped 2130, full retrain 2130
- Per-trade profile title counts: shipped 542, full retrain 542
- Prediction agreement on the holdout between shipped and full-retrain model: 100.0%
- Action taken: no refresh needed — shipped artefact already equals a full-data retrain

No per-trade profile differences against the shipped artefact: the shipped model was already trained on the full dataset with the current `CATEGORY_MAP` and seed keywords, so the holdout experiment does not require a production refresh.

## 8. How to read these numbers

- **78.8% is the number to trust** for unseen wording; the previous 93.3%-style figures were measured on text the model had already memorised.
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

