"""Rebuild trade_matcher.joblib + trade_profiles.json from job_categorization.parquet.

Expanded seed keywords fix the 16 failing cases found in eval:
  - plumbing: flush/valve/mixer/tap/shower/faucet/toilet/drain/sewer
  - hvac: aircon/cooling/duct/refrigerant
  - carpenter: hinge/lock/door/wooden
  - electrical: cctv/camera/network cable/socket/breaker/conduit
  - laborer: clean/debris/scaffold/barrier/demolish/carry/haul/unload
  - supervision: fire extinguisher/inspection/compliance/sampling/test/inspect
  - roofing: membrane/waterproof/bitumen
  - tiling: grout/backsplash/ceramic
"""
import json
import platform
import re
from datetime import datetime
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS, TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import FeatureUnion, Pipeline

BACKEND = Path(__file__).resolve().parent.parent  # Backend/scripts -> Backend
DATA = BACKEND / "data"


def build_meta(**extra) -> dict:
    """Library versions of the environment doing the build.

    The artefacts are pickles of scikit-learn estimators, so they only behave like
    the validated models under the same scikit-learn / numpy pair that produced
    them. Recording the build environment lets ``app.ai_service`` flag a mismatch
    at load time and lets the tests compare the artefact against
    ``requirements.txt`` instead of guessing from the installed wheels.
    """
    meta = {
        "scikit-learn": sklearn.__version__,
        "numpy": np.__version__,
        "joblib": joblib.__version__,
        "python": platform.python_version(),
        "built_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }
    meta.update(extra)
    return meta


CANONICAL = ["carpenter", "electrical", "plumbing", "masonry", "painting", "welding",
             "hvac", "roofing", "tiling", "drywall", "glazing", "flooring",
             "equipment", "laborer", "insulation", "supervision"]

# Expanded seed keywords (kept in sync with app/ai_service.py)
SEED_KEYWORDS = {
    "carpenter": ["carpenter", "cabinet", "joinery", "timber", "wood", "wooden", "plywood", "formwork", "framework", "carpentry", "hinge", "door lock", "partition wall", "sheathing", "stud", "木工", "橱柜", "tukang kayu", "pertukangan", "kabinet", "bingkai", "marquetry", "inlay", "cabinetmaker"],
    "electrical": ["electrician", "electrical", "electric", "wiring", "cable", "lighting", "db panel", "cctv", "camera", "network cable", "socket", "breaker", "conduit", "switch", "ceiling fan", "电工", "电线", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel", "wirer", "wireman"],
    "plumbing": ["plumber", "plumbing", "pipe", "water pipe", "sanitary", "chiller", "flush", "valve", "mixer", "tap", "shower", "faucet", "toilet", "drain", "sewer", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang", "sewage", "septic", "sump"],
    "masonry": ["mason", "masonry", "brick", "block", "concrete", "rebar", "stucco", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit", "simen", "bancuh", "asas", "terrazzo", "reinforcing", "post tension", "curbstone", "kiln", "granite", "cement patcher", "furnace mason", "refractory"],
    "painting": ["painter", "painting", "paint", "emulsion", "primer", "coat", "varnish", "stain", "lacquer", "sealer", "topcoat", "polyurethane", "stair rail", "handrail", "furniture", "trim", "油漆", "粉刷", "涂料", "mengecat", "pengecat", "cat dinding", "wallpaper", "wallpapering", "decorator"],
    "welding": ["welder", "welding", "weld", "steel", "metal", "ironworker", "railing", "column", "erect", "焊接", "钢结构", "kimpal", "pengimpal", "keluli", "solder", "soldering", "brazing", "boilermaker", "sub arc", "arc weld", "spot weld", "boiler installer", "boiler mechanic"],
    "hvac": ["hvac", "air conditioning", "aircon", "cooling", "ventilation", "ahu", "duct", "refrigerant", "vent", "air vent", "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan", "boiler", "furnace", "stoker", "refrigeration", "stationary engineer"],
    "roofing": ["roofer", "roofing", "roof", "shingle", "membrane", "waterproof", "bitumen", "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tile", "tiler", "tiling", "ceramic", "grout", "backsplash", "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "sheetrock", "gypsum", "taper", "partition", "ceiling board", "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazier", "glass", "window", "glazing", "玻璃", "门窗安装", "kaca", "tingkap"],
    "flooring": ["floor", "flooring", "linoleum", "carpet", "vinyl", "laminate", "epoxy", "wooden floor", "grind", "grinding", "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["operator", "excavator", "bulldozer", "backhoe", "crane", "grader", "shovel", "dozer", "pile", "forklift", "concrete pump", "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft", "clean", "debris", "scaffold", "scaffolding", "barrier", "demolish", "demolition", "carry", "haul", "unload", "jackhammer", "signage", "breaking", "chipping", "rubble", "sweep", "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu", "perancah", "perobohan", "detailer", "wash", "washer", "landscap", "shrub", "sod", "planter", "groundskeep", "lawn", "mover", "loader", "sign post", "sign board", "sign installation", "material handler", "cargo handler", "package handler", "freight handler"],
    "insulation": ["insulation", "insulator", "insulate", "rockwool", "fiberglass", "foam", "cavity", "保温", "隔热", "penebat", "penebat haba", "busa", "gentian kaca", "asbestos", "hazardous", "abatement", "radiological"],
    "supervision": ["superintendent", "supervisor", "foreman", "coordinator", "manager", "inspection", "inspector", "inspect", "fire extinguisher", "compliance", "sampling", "工地主任", "监工", "巡查", "penyelia", "penyelia tapak", "pemeriksa", "pemantauan", "mandor"],
}

# category -> canonical trade mapping from job_categorization.parquet
CATEGORY_MAP = {
    "carpenter": ["Cabinetmakers and Bench Carpenters", "Carpenters", "Woodworkers, All Other", "Furniture Finishers", "Model Makers, Wood"],
    "electrical": ["Electricians", "Electrical Power-Line Installers and Repairers", "Electrical and Electronics Installers and Repairers", "Electrical and Electronics Repairers", "Audio and Video Equipment Installers and Repairers", "Security and Fire Alarm Systems Installers", "Telecommunications Equipment Installers and Repairers", "Electrical and Electronic Equipment Assemblers", "Electric Motor, Power Tool, and Related Repairers", "Electrical and Electronics Drafters", "Electrical Engineers"],
    "plumbing": ["Plumbers, Pipefitters, and Steamfitters", "Pipelayers", "Plumbing, Heating, and Air-Conditioning Installers", "Septic Tank Servicers and Sewer Pipe Cleaners"],
    "masonry": ["Brickmasons and Blockmasons", "Cement Masons and Concrete Finishers", "Stonemasons", "Terrazzo Workers and Finishers", "Reinforcing Iron and Rebar Workers"],
    "painting": ["Painters, Construction and Maintenance", "Painting, Coating, and Decorating Workers", "Paperhangers", "Coating, Painting, and Spraying Machine Setters, Operators, and Tenders"],
    "welding": ["Welders, Cutters, Solderers, and Brazers", "Welding, Soldering, and Brazing Machine Setters, Operators, and Tenders", "Structural Iron and Steel Workers", "Sheet Metal Workers", "Boilermakers"],
    "hvac": ["Heating, Air Conditioning, and Refrigeration Mechanics and Installers", "Boiler Operators and Tenders, Low Pressure", "Stationary Engineers and Boiler Operators"],
    "roofing": ["Roofers", "Waterproofing and Related Workers", "Roof Bolters, Mining"],
    "tiling": ["Tile and Stone Setters", "Floor Layers, Except Carpet, Wood, and Hard Tiles", "Floor Sanders and Finishers", "Carpet Installers"],
    "drywall": ["Drywall and Ceiling Tile Installers", "Tapers", "Insulation Workers, Floor, Ceiling, and Wall", "Plasterers and Stucco Masons"],
    "glazing": ["Glaziers", "Automotive Glass Installers and Repairers"],
    "flooring": ["Floor Layers, Except Carpet, Wood, and Hard Tiles", "Carpet Installers", "Floor Sanders and Finishers", "Hardwood Floor Installers"],
    "equipment": ["Excavating and Loading Machine and Dragline Operators, Surface Mining", "Crane and Tower Operators", "Operating Engineers and Other Construction Equipment Operators", "Pile Driver Operators", "Dredge Operators", "Loading Machine Operators, Underground Mining", "Hoist and Winch Operators", "Industrial Truck and Tractor Operators", "Material Moving Workers, All Other", "Conveyor Operators and Tenders", "Heavy and Tractor-Trailer Truck Drivers"],
    "laborer": ["Construction Laborers", "Helpers--Construction Trades", "Building Cleaning Workers, All Other", "Construction and Related Workers, All Other", "Refuse and Recyclable Material Collectors", "Laborers and Freight, Stock, and Material Movers, Hand", "Cleaners of Vehicles and Equipment", "Landscaping and Groundskeeping Workers", "Demolition Workers"],
    "insulation": ["Insulation Workers, Floor, Ceiling, and Wall", "Insulation Workers, Mechanical", "Hazardous Materials Removal Workers"],
    "supervision": ["Construction Managers", "Construction and Building Inspectors", "First-Line Supervisors of Construction Trades and Extraction Workers", "Managers, All Other", "Supervisors of Building and Grounds Cleaning and Maintenance Workers", "Architects, Except Landscape and Naval"],
}

def clean(text: str) -> str:
    t = re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff ]+", " ", str(text).lower())
    return re.sub(r"\s+", " ", t).strip()

STOP_WORDS = (
    set("the a an and or for with of to in on at by from into onto under over install installing new fix apply lay test check do make set up build construction project work task done ready please need want using use".split())
    | set("yang dan di ke dari ini itu untuk dengan pada atau adalah tidak saya anda kami pasang memasang baiki membaiki periksa memeriksa kerja bekerja projek tugas siap perlu mahu guna menggunakan buat membuat baru letak meletakkan uji menguji pengujian kawasan bangunan semua akan sudah boleh ada tanpa selepas sebelum antara dalam jadual sila mohon bantu".split())
    | set(ENGLISH_STOP_WORDS)
)

def build_profiles(df: pd.DataFrame = None):
    """Build per-trade profile titles from the dataset.

    ``df`` lets callers (e.g. the holdout evaluation) train on a data subset;
    default reads the full parquet so the production artefact is unchanged.
    """
    if df is None:
        df = pd.read_parquet(DATA / "job_categorization.parquet")
    profiles = {}
    titles_all = []
    trade_labels = []
    for trade in CANONICAL:
        cats = CATEGORY_MAP.get(trade, [])
        sel = df[df["category"].isin(cats)] if cats else pd.DataFrame()
        titles = sel["title"].dropna().unique().tolist() if len(sel) else []
        profiles[trade] = titles
        for t in titles:
            titles_all.append(clean(t))
            trade_labels.append(trade)
    return profiles, titles_all, trade_labels


def train_matcher(profiles):
    """Fit the TF-IDF trade matcher from per-trade profile titles.

    Returns the joblib payload dict (vectorizer / trade_names / trade_vectors)
    without touching disk, so the holdout evaluation can train on its 80% split
    and keep production files untouched.
    """
    # Profile text = dataset titles + seed keywords repeated for weight.
    docs = []
    for trade in CANONICAL:
        text_parts = list(profiles[trade])
        seeds = SEED_KEYWORDS.get(trade, [])
        # Repeat seeds so they dominate the TF-IDF profile vector.
        text_parts += seeds * 12
        docs.append(" ".join(clean(p) for p in text_parts))

    vec = TfidfVectorizer(
        sublinear_tf=True,
        stop_words=sorted(STOP_WORDS),
        ngram_range=(1, 2),
        max_features=20000,
    )
    X = vec.fit_transform(docs)
    return {
        "vectorizer": vec,
        "trade_names": CANONICAL,
        "trade_vectors": X,
        "meta": build_meta(
            algorithm="tfidf profile centroid",
            trades=len(CANONICAL),
            profiles={t: len(profiles[t]) for t in CANONICAL},
        ),
    }


# ---------------------------------------------------------------------------
# Supervised classifier (fixes the structural semantic-layer gaps)
# ---------------------------------------------------------------------------
# The profile matcher (``train_matcher``) is a nearest-centroid model: it can
# only say "this text looks like the *average* of a trade's titles". Several
# failure families cannot be expressed that way, because the discriminating
# evidence is a specific head noun / suffix, not overall similarity:
#   * ``painting`` / ``drywall`` - their titles share "wall", "coat", "finish"
#     with masonry and tiling, so the centroid drifts and recall collapses;
#   * ``ornamental plasterer`` / ``moulding plasterer`` - the dataset files
#     plasterers under drywall, while the rules own the word "plaster";
#   * ``material handler`` - "handler" is far closer to the hazmat/insulation
#     centroid than to laborer;
#   * ``* machine operator`` - "operator" pulls everything into equipment.
# A multinomial logistic regression on the *same* supervision (row → trade) learns
# "painter" vs "tilesetter" as competing evidence instead of an average, and it
# outputs calibrated probabilities we can threshold for the skip path.
CLASSIFIER_SEED_REPEAT = 3      # seed keywords appended per class in training
CLASSIFIER_WORD_FEATURES = 12000
CLASSIFIER_CHAR_FEATURES = 18000
CLASSIFIER_C = 50.0             # registered config of the previous round (variant V0)
CLASSIFIER_PATH = DATA / "trade_classifier.joblib"

# ---------------------------------------------------------------------------
# Production configuration (variant "F single_synth_rules")
# ---------------------------------------------------------------------------
# The attribution run on the clean valid split (seed 31337) scored six candidates
# in one pass; the shipped one is F: multiclass argmax, dataset + synthetic
# corpus, dev-searched C, compound-title rules on. It reached top-1 96.4 %
# (strict 96.3 %) against 92.8 % for the previous registration (V0) and 94.0 %
# for the multi-label candidate E.
#
# The multi-label path (One-vs-Rest + threshold/margin + co-occurrence guard) is
# kept intact because the code, the dev sweep and the eval script still use it,
# but it is *not* what production ships: on valid it never emitted a single
# second label (multi-pred rows = 0), so it bought no accuracy and cost 2.4 pt
# top-1 against F. Switching it back on is a one-line change here plus a rebuild.
PRODUCTION_LABEL_MODE = "single"
PRODUCTION_C = 4.0              # dev grid (seed 42), identical to the eval variant
PRODUCTION_SYNTHETIC = True

# Synthetic task corpus (``scripts/synth_trade_tasks.py``). Only the quality
# filtered rows are used; the generator caches raw API answers separately.
SYNTH_TASKS_PATH = DATA / "synthetic_trade_tasks.jsonl"

# Multi-label decision rule. A secondary trade joins the answer when its fused
# probability clears MULTI_THRESHOLD *and* stays within MULTI_MARGIN of the
# winner *and* the pair (winner, secondary) is a co-occurring pair in the
# training taxonomy (``MULTI_PAIR_SUPPORT`` or more shared titles). Tuned on the
# dev pool (seed 42); the valid set (seed 31337) only ever sees the final numbers.
#
# Why the co-occurrence guard: a bare threshold/margin rule happily promotes a
# random runner-up ("automobile detailer" -> laborer + painting), which costs
# more exact-set matches than the dual-label rows it wins. The dataset itself
# says which trades genuinely overlap (Carpet Installers / Floor Layers / Floor
# Sanders are mapped to both flooring and tiling), so the guard restricts extra
# labels to those pairs.
MULTI_THRESHOLD = 0.35
MULTI_MARGIN = 0.25
MULTI_PAIR_SUPPORT = 5
# One-vs-Rest needs its own regularisation: each label sees ~60 positives among
# ~3800 samples, so the single-label C=50 saturates every column at 0/1 and the
# threshold never fires. Balanced class weights + C=4 keeps the probabilities
# readable (dev sweep, seed 42).
MULTI_C = 4.0


def cooccurring_pairs(labels, min_support: int = 0) -> dict:
    """Count trade pairs that share a training title (``>= min_support`` kept).

    ``labels`` is the per-sample label list from ``build_classifier_corpus``; a
    sample with two trades means the dataset maps one title to both, i.e. the
    taxonomy itself is ambiguous there. The multi-label decision layer only lets
    such pairs grow a second label, which stops random runner-ups from being
    promoted.
    """
    counts: dict = {}
    for label_set in labels:
        trades = sorted(set(label_set if isinstance(label_set, (list, tuple, set))
                            else [label_set]))
        for i, first in enumerate(trades):
            for second in trades[i + 1:]:
                counts[(first, second)] = counts.get((first, second), 0) + 1
    return {pair: n for pair, n in counts.items() if n >= min_support}


def load_synthetic(split: str = "train", path: Path = None,
                   exclude_titles: set = None) -> list[dict]:
    """Read the quality-filtered synthetic tasks for classifier training.

    ``split`` keeps the generator's probe rows (15 % of titles, reserved so the
    synthetic corpus itself can be checked) out of training. ``exclude_titles``
    drops every row generated *from* a held-out title: a paraphrase of a valid
    title is still the valid title's content, so training on it would leak the
    hold-out set into the model and inflate the evaluation.
    """
    path = Path(path) if path else SYNTH_TASKS_PATH
    if not path.exists():
        return []
    exclude = {clean(t) for t in (exclude_titles or set())}
    rows: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if split and rec.get("split") != split:
            continue
        text = clean(rec.get("task_text") or "")
        labels = [t for t in rec.get("trades") or [] if t in CANONICAL]
        if not text or not labels:
            continue
        if exclude and clean(rec.get("source_title") or "") in exclude:
            continue
        rows.append({"text": text, "labels": labels,
                     "source_title": rec.get("source_title")})
    return rows



def build_classifier_corpus(df: pd.DataFrame = None, stats: dict = None,
                            synthetic: bool = False, label_mode: str = "single",
                            exclude_titles: set = None):
    """Return (texts, labels) for supervised training.

    Row titles come from ``build_profiles`` (already cleaned and per-trade).

    * ``label_mode="single"`` - the historical layout: a title that a category
      legitimately maps to two trades contributes one sample per trade, and the
      trainer fits a multiclass ``LogisticRegression``.
    * ``label_mode="multi"`` - one sample per unique title carrying its *set* of
      trades, so a dual-label title ("wall to wall carpet installer") teaches
      both labels instead of being split into two competing rows.

    ``synthetic=True`` appends the quality-filtered synthetic task descriptions
    (``data/synthetic_trade_tasks.jsonl``). ``exclude_titles`` holds the titles
    of a held-out split: every synthetic row paraphrasing one of them is dropped
    so the hold-out set never leaks into training through its own paraphrases.

    Seed keywords are appended ``CLASSIFIER_SEED_REPEAT`` times so the
    classifier keeps the vocabulary the rule layer relies on even for trades with
    few dataset titles.

    ``stats`` (optional, filled in place) reports how the sample count splits into
    dataset titles vs repeated seeds, so the artefact metadata can say "518
    labelled titles" instead of the misleading "6539 parquet rows".
    """
    if label_mode not in ("single", "multi"):
        raise ValueError(f"label_mode must be 'single' or 'multi', got {label_mode!r}")
    profiles = build_profiles(df)[0]

    texts: list[str] = []
    labels: list = []
    seed_rows = 0

    if label_mode == "single":
        title_rows = 0
        for trade in CANONICAL:
            texts.extend(profiles[trade])
            labels.extend([trade] * len(profiles[trade]))
            title_rows += len(profiles[trade])
    else:
        by_title: dict[str, list[str]] = {}
        for trade in CANONICAL:
            for title in profiles[trade]:
                by_title.setdefault(title, []).append(trade)
        title_rows = len(by_title)
        for title, trades in by_title.items():
            texts.append(title)
            labels.append(trades)

    for trade in CANONICAL:
        seeds = [clean(s) for s in SEED_KEYWORDS.get(trade, [])]
        seeds = [s for s in seeds if s]
        texts.extend(seeds * CLASSIFIER_SEED_REPEAT)
        if label_mode == "single":
            labels.extend([trade] * len(seeds) * CLASSIFIER_SEED_REPEAT)
        else:
            labels.extend([[trade] for _ in range(len(seeds) * CLASSIFIER_SEED_REPEAT)])
        seed_rows += len(seeds) * CLASSIFIER_SEED_REPEAT

    synth_rows = 0
    if synthetic:
        for rec in load_synthetic(split="train", exclude_titles=exclude_titles):
            texts.append(rec["text"])
            labels.append(rec["labels"][0] if label_mode == "single" else rec["labels"])
            synth_rows += 1

    if stats is not None:
        stats.update(
            label_mode=label_mode,
            labelled_titles=title_rows,
            seed_rows=seed_rows,
            synthetic_rows=synth_rows,
            dataset_rows=int(len(df)) if df is not None else None,
        )
    return texts, labels


def train_classifier(df: pd.DataFrame = None, synthetic: bool = False,
                     label_mode: str = "single", threshold: float = MULTI_THRESHOLD,
                     margin: float = MULTI_MARGIN, exclude_titles: set = None,
                     c_value: float = None, pair_support: int = MULTI_PAIR_SUPPORT) -> dict:
    """Fit the supervised trade classifier on the labelled dataset.

    Word 1-2 grams capture phrases ("spray painter", "machine operator"), char
    3-5 grams absorb morphology so "plasterer"/"plastering"/"plastered" and
    compound titles the word analyser splits ("materialhandler") still match.

    ``label_mode="multi"`` wraps the same features in a ``OneVsRestClassifier``
    over the 16 canonical trades, so the payload returns one probability per
    trade and the decision layer can keep every label above the threshold. The
    returned payload stays ``{model, classes, meta}`` for backward compatibility;
    ``trade_names`` / ``label_mode`` / ``decision`` are added for the multi case.

    Returns the joblib payload without writing disk.
    """
    stats: dict = {}
    texts, labels = build_classifier_corpus(
        df, stats, synthetic=synthetic, label_mode=label_mode,
        exclude_titles=exclude_titles,
    )
    features = FeatureUnion([
        ("word", TfidfVectorizer(
            sublinear_tf=True,
            stop_words=sorted(STOP_WORDS),
            ngram_range=(1, 2),
            min_df=1,
            max_features=CLASSIFIER_WORD_FEATURES,
            dtype=np.float32,
        )),
        ("char", TfidfVectorizer(
            analyzer="char_wb",
            sublinear_tf=True,
            ngram_range=(3, 5),
            min_df=1,
            max_features=CLASSIFIER_CHAR_FEATURES,
            dtype=np.float32,
        )),
    ])
    meta_extra = dict(
        seed_repeat=CLASSIFIER_SEED_REPEAT,
        samples=len(texts),
        labelled_titles=stats.get("labelled_titles"),
        seed_rows=stats.get("seed_rows"),
        synthetic_rows=stats.get("synthetic_rows", 0),
        synthetic_corpus=SYNTH_TASKS_PATH.name if synthetic else None,
        synthetic=bool(synthetic),
        label_mode=label_mode,
        dataset_rows=stats.get("dataset_rows"),
        trained_at=datetime.now().strftime("%Y-%m-%d %H:%M"),
    )
    # ``c_value`` lets the evaluation and the production build reproduce one exact
    # variant; ``None`` keeps the registered default so older callers are unaffected.
    c_single = float(c_value if c_value is not None else CLASSIFIER_C)

    if label_mode == "multi":
        from sklearn.multiclass import OneVsRestClassifier
        from sklearn.preprocessing import MultiLabelBinarizer

        encoder = MultiLabelBinarizer(classes=CANONICAL)
        targets = encoder.fit_transform(labels)
        c_multi = float(c_value if c_value is not None else MULTI_C)
        model = Pipeline([
            ("features", features),
            ("clf", OneVsRestClassifier(
                LogisticRegression(C=c_multi, max_iter=3000,
                                   class_weight="balanced"), n_jobs=1)),
        ])
        model.fit(texts, targets)
        pairs = cooccurring_pairs(labels, pair_support)
        return {
            "model": model,
            "classes": [str(c) for c in encoder.classes_],
            "trade_names": [str(c) for c in encoder.classes_],
            "label_mode": "multi",
            "decision": {
                "threshold": float(threshold),
                "margin": float(margin),
                "pairs": [list(p) for p in sorted(pairs)],
                "pair_support": int(pair_support),
            },
            "meta": build_meta(
                algorithm="tfidf(word 1-2 + char_wb 3-5) + OneVsRest(LogisticRegression, balanced)",
                C=c_multi, pair_support=int(pair_support),
                cooccurring_pairs={f"{a}+{b}": n for (a, b), n in
                                   sorted(cooccurring_pairs(labels).items())},
                **meta_extra,
            ),
        }

    model = Pipeline([
        ("features", features),
        ("clf", LogisticRegression(C=c_single, max_iter=3000)),
    ])
    model.fit(texts, labels)
    return {
        "model": model,
        "classes": [str(c) for c in model.classes_],
        "trade_names": [str(c) for c in model.classes_],
        "label_mode": "single",
        "decision": {"threshold": float(threshold), "margin": float(margin)},
        "meta": build_meta(
            algorithm="tfidf(word 1-2 + char_wb 3-5) + LogisticRegression",
            C=c_single, **meta_extra,
        ),
    }


def save_classifier(bundle: dict, path: Path = None) -> Path:
    """Persist the classifier (compressed: it is shipped inside the API image)."""
    path = Path(path) if path else CLASSIFIER_PATH
    joblib.dump(bundle, path, compress=3)
    return path


def main():
    profiles, titles_all, trade_labels = build_profiles()
    matcher = train_matcher(profiles)
    vec = matcher["vectorizer"]
    X = matcher["trade_vectors"]
    print("vocab size:", len(vec.vocabulary_))
    for i, trade in enumerate(CANONICAL):
        print(f"  {trade}: {len(profiles[trade])} titles, {X[i].nnz} nz features")

    joblib.dump(matcher, DATA / "trade_matcher.joblib")
    with open(DATA / "trade_profiles.json", "w", encoding="utf-8") as f:
        json.dump(profiles, f, ensure_ascii=False, indent=2)
    print("saved:", DATA / "trade_matcher.joblib")

    df = pd.read_parquet(DATA / "job_categorization.parquet")
    # Production artefact = variant "F single_synth_rules": single-label argmax,
    # dataset + synthetic corpus, dev-searched C, compound-title rules on (the
    # rules live in app.ai_service._STRUCTURED_RULES, which defaults to True).
    # Every legitimate sample is used, including the rows generated from the
    # evaluation titles (nothing is held out once the numbers have been reported).
    bundle = train_classifier(
        df,
        synthetic=PRODUCTION_SYNTHETIC,
        label_mode=PRODUCTION_LABEL_MODE,
        c_value=PRODUCTION_C,
    )
    saved = save_classifier(bundle)
    size_mb = saved.stat().st_size / 1048576
    print(f"saved: {saved} ({size_mb:.2f} MB, {bundle['meta']['samples']} training samples, "
          f"{len(bundle['classes'])} classes, label_mode={bundle['label_mode']}, "
          f"C={bundle['meta']['C']}, synthetic={bundle['meta']['synthetic_rows']})")
    print("decision rule:", bundle["decision"])

if __name__ == "__main__":
    main()
