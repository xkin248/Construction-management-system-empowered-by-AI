# Trade model archive — v0 (pre CATEGORY_MAP fix)

Archived: 2026-10-29 10:39 UTC
Source: `construction_management_system_Backend/data/` as shipped in commit
`5eef63b` (built 2026-10-27 19:47–19:48 local).

| file | size (bytes) | sha256 |
| --- | ---: | --- |
| `trade_classifier.joblib` | 2952034 | `b13dcf7f6368e7381160bf3adbdfe6d4669a2e4203f942cffde0d834e4b65eba` |
| `trade_matcher.joblib` | 132674 | `8785670d0246376b934ee63798db218f2fae338a1c74b4cc0f657e2f876a905e` |
| `trade_profiles.json` | 16126 | `750168fc694f6d30393203d4725920c1c28efc474a1160a2faa68d85a324c7ce` |

## Why kept

These are the artefacts that produced every number quoted in
`reports/trade_label_expansion_plan.md` (v2). They were trained while
`CATEGORY_MAP` still mapped `Floor Layers / Floor Sanders / Carpet Installers`
to **both** `flooring` and `tiling`, and `Insulation Workers, Floor, Ceiling,
and Wall` to **both** `insulation` and `drywall`. That mapping produced 25 rows
of artificial double labels (18 × flooring+tiling, 7 × drywall+insulation),
which the multi-label experiments in `reports/` report on.

Kept for reproducibility only. Do not serve these files.

## Classifier metadata (as archived)

```
label_mode = single
samples    = 4591
C          = 4.0
algorithm  = tfidf(word 1-2 + char_wb 3-5) + LogisticRegression
trained_at = 2026-10-27 19:47
cooccurring_pairs = null
```
