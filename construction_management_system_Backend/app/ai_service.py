import os
import json
import re
import time
from collections import defaultdict
from typing import List, Dict, Any, Optional, Tuple
from datetime import date, datetime, timedelta
from pathlib import Path
from dotenv import load_dotenv

try:
    import google.generativeai as genai
    GEMINI_AVAILABLE = True
except ImportError:
    GEMINI_AVAILABLE = False

try:
    import joblib
    import numpy as np
    from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS
    from sklearn.metrics.pairwise import cosine_similarity
    SEMANTIC_AVAILABLE = True
except ImportError:
    SEMANTIC_AVAILABLE = False

from app.database import get_db
from app.models import (
    Worker, Task, TaskWorker, AttendanceLog, Project, DailyReport, Issue,
    PredictionHistory, AIDecisionLog,
)
from app.worker_pool import get_project_workers

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")

# ── Trade decision thresholds ────────────────────────────────────────────────
# The deterministic pipeline (keyword rules + semantic matcher) is trusted when
# the best candidate scores at least LLM_TRADE_MIN_SCORE and beats the runner-up
# by LLM_TRADE_MIN_GAP. Anything weaker is ambiguous and triggers one Gemini
# verdict; if that verdict is still below SKIP_CONFIDENCE_THRESHOLD the task is
# skipped instead of being assigned to a guessed trade.
LLM_TRADE_MIN_SCORE = 0.5
LLM_TRADE_MIN_GAP = 0.1
SKIP_CONFIDENCE_THRESHOLD = 0.5
# Hard ceiling for the Gemini trade call so a slow API never blocks auto-assign.
LLM_TRADE_TIMEOUT_SECONDS = float(os.getenv("GEMINI_TRADE_TIMEOUT", "8"))

# Forced-JSON prompt for the ambiguous-trade fallback. Kept as one constant so
# tests and future tuning share the same wording.
TRADE_DECISION_PROMPT = """You are a construction trade classifier.
Decide which single trade is required to execute the task below.

Task: {task_text}

Candidate trades: {candidates}

Rules:
- Answer with exactly one trade from the candidate list.
- confidence is a number between 0 and 1 (how sure you are).
- reason is one short English sentence.

Return JSON only, no markdown:
{{"trade": "<candidate>", "confidence": 0.0, "reason": "<short reason>"}}"""

if GEMINI_AVAILABLE and GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)


SYSTEM_PROMPT = """You are BuildSmart AI, a professional construction management assistant. Your role is to help construction managers manage engineering projects efficiently.

Your areas of expertise include:
1. Construction task assignment and workforce scheduling
2. Safety management and risk assessment
3. Progress tracking and reporting
4. Material and equipment management advice
5. Cost control advice

Please respond in concise, professional, and practical language, in English or Malay (English preferred). If specific data is involved, base your analysis on the provided context information."""


# Trade synonyms: canonical group -> keywords matched against worker trade strings.
# Used ONLY for mapping a worker's stored trade label to a canonical group.
# (Task text detection uses TASK_KEYWORDS below — narrower, avoids false positives
# like "wall"/"water"/"floor" matching the wrong trade.)
TRADE_ALIASES: Dict[str, List[str]] = {
    "carpenter": ["carpenter", "carpentry", "cabinet", "joinery", "timber", "wood", "formwork", "framework", "木工", "橱柜", "木", "tukang kayu", "pertukangan", "kabinet", "bingkai"],
    "electrical": ["electrical", "electric", "electrician", "wiring", "cable", "lighting", "db panel", "电工", "电线", "电缆", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel"],
    "plumbing": ["plumbing", "plumber", "pipe", "water", "sanitary", "chiller", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang"],
    "masonry": ["masonry", "mason", "brick", "block", "wall", "concrete", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit", "simen", "bancuh", "asas"],
    "painting": ["painting", "paint", "plaster", "emulsion", "primer", "varnish", "stain", "lacquer", "sealer", "topcoat", "polyurethane", "gloss", "油漆", "粉刷", "涂料", "mengecat", "pengecat", "cat dinding", "wallpaper", "wallpapering", "decorator"],
    "welding": ["welding", "weld", "steel", "metal", "ironworker", "焊接", "钢结构", "金属", "kimpal", "pengimpal", "keluli", "besi"],
    "hvac": ["hvac", "air balance", "ahu", "ventilation", "air conditioning", "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan"],
    "roofing": ["roofing", "roofer", "roof", "shingle", "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tiling", "tile", "tiler", "terrazzo", "ceramic", "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "sheetrock", "gypsum", "taper", "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazing", "glazier", "glass", "window", "玻璃", "门窗", "kaca", "tingkap"],
    "flooring": ["flooring", "floor", "linoleum", "carpet", "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["equipment", "operator", "excavator", "bulldozer", "backhoe", "crane", "grader", "shovel", "dozer", "pile", "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft", "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu", "perancah", "perobohan"],
    "insulation": ["insulation", "insulator", "insulate", "保温", "隔热", "penebat", "penebat haba", "busa", "gentian kaca"],
    "supervision": ["superintendent", "supervisor", "foreman", "coordinator", "manager", "inspection", "inspector", "监工", "巡查", "penyelia", "penyelia tapak", "pemeriksa", "pemantauan", "mandor"],
}

# Strict keywords for TASK text detection (title+description). Deliberately
# narrower than TRADE_ALIASES: generic words like "wall"/"floor"/"water" alone
# must NOT decide a trade, otherwise "paint walls" -> masonry or "tile floor" ->
# flooring. Ambiguous multi-hit cases are resolved by the semantic matcher.
TASK_KEYWORDS: Dict[str, List[str]] = {
    "carpenter": ["carpenter", "carpentry", "cabinet", "joinery", "timber", "formwork", "framework", "hinge", "door lock", "wooden", "plywood", "木工", "橱柜", "tukang kayu", "pertukangan", "kabinet", "bingkai", "marquetry", "inlay", "cabinetmaker"],
    "electrical": ["electrical", "electrician", "wiring", "cable", "lighting", "db panel", "cctv", "camera", "network cable", "socket", "breaker", "conduit", "switch", "ceiling fan", "电工", "电线", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel", "wirer", "wireman"],
    "plumbing": ["plumbing", "plumber", "pipe", "water pipe", "sanitary", "chiller", "flush", "valve", "mixer", "tap", "shower", "faucet", "toilet", "drain", "sewer", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang", "sewage", "septic", "sump"],
    "masonry": ["masonry", "mason", "brick", "block", "concrete", "rebar", "stucco", "plaster", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit", "simen", "bancuh", "asas", "terrazzo", "reinforc", "post tension", "curbstone", "kiln", "cement patcher", "furnace mason", "refractory"],
    "painting": ["painting", "paint", "emulsion", "primer", "coat", "varnish", "油漆", "粉刷", "涂料", "mengecat", "pengecat", "wallpaper", "wallpapering", "decorator"],
    "welding": ["welding", "weld", "steel", "metal", "railing", "column", "erect", "焊接", "钢结构", "kimpal", "pengimpal", "keluli", "solder", "soldering", "brazing", "boilermaker", "sub arc", "arc weld", "spot weld", "boiler installer", "boiler mechanic"],
    "hvac": ["hvac", "air conditioning", "aircon", "cooling", "ventilation", "ahu", "duct", "refrigerant", "vent", "air vent", "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan", "boiler", "furnace", "stoker", "refrigeration", "cold room"],
    "roofing": ["roofing", "roofer", "roof", "shingle", "membrane", "waterproof", "bitumen", "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tiling", "tile", "tiler", "ceramic", "grout", "backsplash", "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "sheetrock", "gypsum", "taper", "partition", "ceiling board", "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazing", "glazier", "glass", "window", "玻璃", "门窗", "kaca", "tingkap"],
    "flooring": ["flooring", "floor", "linoleum", "carpet", "vinyl", "laminate", "epoxy", "wooden floor", "grind", "grinding", "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["equipment", "operator", "excavator", "bulldozer", "backhoe", "crane", "grader", "shovel", "dozer", "pile", "forklift", "concrete pump", "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft", "clean", "debris", "scaffold", "scaffolding", "barrier", "demolish", "demolition", "carry", "haul", "unload", "jackhammer", "signage", "breaking", "chipping", "rubble", "sweep", "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu", "perancah", "perobohan", "detailer", "wash", "washer", "landscap", "shrub", "sod", "planter", "groundskeep", "lawn", "mover", "loader", "sign post", "sign board", "sign installation", "material handler", "cargo handler", "package handler", "freight handler"],
    "insulation": ["insulation", "insulator", "insulate", "rockwool", "fiberglass", "foam", "cavity", "保温", "隔热", "penebat", "penebat haba", "busa", "gentian kaca", "asbestos", "hazardous", "abatement"],
    "supervision": ["superintendent", "supervisor", "foreman", "coordinator", "manager", "inspection", "inspector", "inspect", "fire extinguisher", "compliance", "sampling", "监工", "巡查", "penyelia", "penyelia tapak", "pemeriksa", "pemantauan", "mandor"],
}

# Seed keywords used by the dataset-trained semantic matcher (mirror of build_trade_matcher.py).
SEED_KEYWORDS: Dict[str, List[str]] = {
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

# Standard estimated task duration (workdays) per canonical trade, used by
# dataset-augmented progress prediction.
TRADE_DURATION: Dict[str, float] = {
    "carpenter": 2.0, "electrical": 1.5, "plumbing": 1.5, "masonry": 2.0,
    "painting": 1.5, "welding": 2.0, "hvac": 1.5, "roofing": 2.0,
    "tiling": 1.5, "drywall": 1.5, "glazing": 1.5, "flooring": 1.5,
    "equipment": 1.0, "laborer": 1.0, "insulation": 1.0, "supervision": 0.5,
}

_SEMANTIC_STOP = (
    set("the a an and or for with of to in on at by from into onto under over install installing new fix apply lay test check do make set up build construction project work task done ready please need want using use".split())
    | set("yang dan di ke dari ini itu untuk dengan pada atau adalah tidak saya anda kami pasang memasang baiki membaiki periksa memeriksa kerja bekerja projek tugas siap perlu mahu guna menggunakan buat membuat baru letak meletakkan uji menguji pengujian kawasan bangunan semua akan sudah boleh ada tanpa selepas sebelum antara dalam jadual sila mohon bantu".split())
    | (set(ENGLISH_STOP_WORDS) if SEMANTIC_AVAILABLE else set())
)

_TRADE_MATCHER: Any = None
_TRADE_CLASSIFIER: Any = None

# Supervised classifier settings. The classifier is the primary decision maker;
# the keyword rules stay as a hard prior and the profile matcher as the degraded
# path (older artefact, missing file, unexpected sklearn version, ...).
TRADE_CLASSIFIER_PRIOR_WEIGHT = 0.5   # +50% probability when a rule keyword hits
TRADE_CLASSIFIER_SKIP_PROB = 0.25     # below this with no keyword hit -> "skip"


def _load_trade_matcher():
    """Lazily load the dataset-trained task->trade semantic matcher (joblib)."""
    global _TRADE_MATCHER
    if _TRADE_MATCHER is not None:
        return _TRADE_MATCHER or None
    if not SEMANTIC_AVAILABLE:
        _TRADE_MATCHER = False
        return None
    try:
        p = Path(__file__).resolve().parent.parent / "data" / "trade_matcher.joblib"
        _TRADE_MATCHER = joblib.load(p)
    except Exception:
        _TRADE_MATCHER = False
    return _TRADE_MATCHER or None


def _load_trade_classifier():
    """Lazily load the supervised trade classifier (``data/trade_classifier.joblib``).

    Returns ``None`` (never raises) when the artefact is absent or cannot be
    deserialised, so a missing/old model degrades to the keyword + profile path
    instead of breaking task analysis.
    """
    global _TRADE_CLASSIFIER
    if _TRADE_CLASSIFIER is not None:
        return _TRADE_CLASSIFIER or None
    if not SEMANTIC_AVAILABLE:
        _TRADE_CLASSIFIER = False
        return None
    try:
        p = Path(__file__).resolve().parent.parent / "data" / "trade_classifier.joblib"
        _TRADE_CLASSIFIER = joblib.load(p)
    except Exception:
        _TRADE_CLASSIFIER = False
    return _TRADE_CLASSIFIER or None


def _clean_text(text: str) -> str:
    t = re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff ]+", " ", str(text).lower())
    return re.sub(r"\s+", " ", t).strip()


def _classifier_trade_scores(task_text: str) -> Dict[str, float]:
    """Return {canonical_trade: probability} from the supervised classifier.

    Empty dict when the classifier is unavailable, the text is empty after
    cleaning, or prediction fails - callers must treat that as "degrade".
    """
    bundle = _load_trade_classifier()
    if not bundle:
        return {}
    try:
        text = _clean_text(task_text)
        if not text:
            return {}
        probs = bundle["model"].predict_proba([text])[0]
        return {
            str(cls): float(p)
            for cls, p in zip(bundle["model"].classes_, probs)
        }
    except Exception:
        return {}


def _classifier_trade_decision(
    task_text: str,
    keyword_trades: set,
    trace: Optional[Dict[str, Any]] = None,
) -> Optional[set]:
    """Decide the trade from the supervised classifier.

    Rules (in order):

    * no classifier available -> ``None`` so the caller falls back to the legacy
      keyword + profile pipeline;
    * keyword hits act as a prior (+``TRADE_CLASSIFIER_PRIOR_WEIGHT`` of the
      probability) because the rule layer is hand-checked domain knowledge, but
      they can no longer *own* a trade on their own: a title like
      ``precast concrete ironworker`` hits masonry keywords while the classifier
      knows it is a welding occupation;
    * when the winning probability is below ``TRADE_CLASSIFIER_SKIP_PROB`` and no
      keyword fired, return an empty set ("unassignable"): we prefer the existing
      low-confidence path (LLM worker suggestion) over a coin-flip guess.
    """
    scores = _classifier_trade_scores(task_text)
    if not scores:
        return None
    fused = {
        trade: prob * (1.0 + TRADE_CLASSIFIER_PRIOR_WEIGHT if trade in keyword_trades else 1.0)
        for trade, prob in scores.items()
    }
    best = max(fused, key=lambda t: fused[t])
    best_prob = float(scores.get(best, 0.0))
    if trace is not None:
        trace.clear()
        trace.update({
            "source": "classifier",
            "confidence": best_prob,
            "llm_used": False,
            "llm_reason": None,
            "classifier_top": best,
            "classifier_prob": round(best_prob, 4),
        })
    if not keyword_trades and best_prob < TRADE_CLASSIFIER_SKIP_PROB:
        if trace is not None:
            trace["source"] = "skip"
            trace["confidence"] = 0.0
        return set()
    return {best}


def _semantic_trade_scores(task_text: str) -> Dict[str, float]:
    """Return {canonical_trade: score(0-1)} using the dataset-trained model.
    Score combines TF-IDF cosine similarity (normalised) with direct
    seed/entry keyword hits. Empty dict if the model is unavailable.
    """
    matcher = _load_trade_matcher()
    if not matcher:
        return {}
    try:
        vec = matcher["vectorizer"]
        names = matcher["trade_names"]
        X = matcher["trade_vectors"]
        q_text = _clean_text(task_text)
        q_tokens = set(q_text.split()) - _SEMANTIC_STOP
        if not q_tokens:
            return {}
        q = vec.transform([q_text])
        sims = cosine_similarity(q, X)[0]
        denom = float(sims.max() - sims.min())
        sims_norm = (sims - sims.min()) / denom if denom > 1e-9 else np.zeros_like(sims)
        seed_hits = np.array([
            len(q_tokens & set(_clean_text(" ".join(SEED_KEYWORDS.get(g, []))).split()))
            for g in names
        ])
        # NOTE: previously there was an `entry_hits` term using
        # `q_tokens - seed_tokens`, which is an ANTI-metric that returned the same
        # value for every trade and added a flat 0.35 floor to ALL trades. That
        # destroyed score discrimination: e.g. "electric" scored 0.35 for every
        # trade, and max() then picked the alphabetically-first 'carpenter',
        # mis-assigning electrical tasks to carpenters. The model ships no entry
        # vocab, so we drop that term entirely.
        n = max(len(q_tokens), 1)
        # Score = normalised TF-IDF similarity + seed-hit bonus. The bonus has two
        # parts: a ratio term (proportion of query tokens that hit this trade's
        # seeds) and a flat hit term (at least one seed hit always boosts). The flat
        # term keeps short queries like "electric point" (1 seed hit / 2 tokens =
        # 0.4 ratio) above the 0.5 output floor.
        final = sims_norm + 0.6 * np.minimum(seed_hits / n, 1.0) + 0.4 * np.minimum(seed_hits, 1.0)
        # Drop near-flat scores so a non-discriminating query does not produce a
        # false "best trade". Keep only trades with a meaningful signal.
        return {g: float(s) for g, s in zip(names, final) if s >= 0.5}
    except Exception:
        return {}


def _detect_trade_groups(task_text: str) -> set:
    """Return canonical trade groups whose TASK keywords appear in task text."""
    return {
        group for group, keywords in TASK_KEYWORDS.items()
        if any(kw in task_text for kw in keywords)
    }


# Toggle for the family rules below (kept as a module flag so the evaluation
# scripts can measure the classifier both with and without them).
_STRUCTURED_RULES = True

# Compound title families where the deciding token is the head noun, and where
# bag-of-words similarity is structurally blind. Each entry: (regex, trade).
# Rationale for every family:
#   * boilermaker / boiler installer / boiler mechanic are pressure-vessel
#     fabricators, i.e. the welding group - not HVAC ("boiler operator" is,
#     which is why the rule needs the occupational suffixes);
#   * <cargo|package|freight|material> handler moves goods - a laborer, not an
#     insulator (insulation only owns *hazardous* material handling);
#   * wallpaper hangers are painters (the dataset files them under painting);
#   * a soldering / brazing / arc machine operator is a welding trade even
#     though the word "operator" belongs to the equipment group;
#   * a furnace mason builds refractory brickwork - masonry, not HVAC.
_STRUCTURED_TITLE_RULES: List[tuple] = [
    # (pattern, trade, needs_role_hint)
    (r"\bboiler\s*(?:maker|installer|mechanic|setter|fitter|erector|repairer)", "welding", False),
    (r"\b(?:cargo|package|freight|stock|baggage|luggage|material)\s+handler", "laborer", False),
    (r"\bwallpaper", "painting", False),
    (r"\b(?:soldering|brazing|sub\s*arc|arc\s*weld\w*|spot\s*weld\w*|seam\s*weld\w*)", "welding", True),
    (r"\bfurnace\s+mason", "masonry", False),
]

# Welding processes are only decisive when the title names a machine role
# ("soldering machine setter", "sub arc operator"); a plain "soldering" mention
# must not steal a labouring row.
_ROLE_HINTS = ("operator", "tender", "setter", "setup", "machine")


def _structured_title_trade(task_text: str) -> Optional[str]:
    """Return a trade for the compound title families, or None.

    These families are decided by a head noun ("boiler*", "* handler",
    "wallpaper*") that a similarity model cannot see: the surrounding words
    (installer, machine, material) pull it towards HVAC / equipment /
    insulation instead. Deliberately narrow and literal - a rule that fires
    wrongly is worse than a rule that does not exist, so each pattern pins both
    the head noun and its occupational suffix.
    """
    for pattern, trade, needs_role in _STRUCTURED_TITLE_RULES:
        if not re.search(pattern, task_text):
            continue
        if needs_role and not any(hint in task_text for hint in _ROLE_HINTS):
            continue
        return trade
    return None


def _resolve_detected_trades(
    task_text: str,
    detected: set,
    semantic_scores: Dict[str, float],
    trace: Optional[Dict[str, Any]] = None,
) -> set:
    """Resolve ambiguous multi-hit keyword detection, with a Gemini fallback.

    When several trades match task keywords (e.g. "tile bathroom floor with
    ceramic" hits both tiling and flooring), prefer the trade with the highest
    semantic score so we do not fall back to alphabetical order.

    The deterministic pipeline is trusted only when the best candidate scores at
    least ``LLM_TRADE_MIN_SCORE`` AND beats the runner-up by
    ``LLM_TRADE_MIN_GAP``. Below that the wording is genuinely ambiguous, so one
    forced-JSON Gemini verdict is requested for the candidate set. A missing API
    key, a timeout, an unparsable answer or a trade outside the candidate list
    all degrade to the previous rule/semantic result - the LLM can never block
    or break the pipeline. A verdict whose confidence is still below
    ``SKIP_CONFIDENCE_THRESHOLD`` returns an empty set, i.e. the task stays
    unassignable ("skip") instead of being guessed.

    ``trace`` (optional out-parameter) receives the decision metadata
    (source / confidence / llm_used / llm_reason) used for logging.
    """
    candidates = [g for g in detected]
    scores = {g: float(semantic_scores.get(g, 0.0)) for g in candidates}
    ordered = sorted(scores.values(), reverse=True)
    best_score = ordered[0] if ordered else 0.0
    runner_up = ordered[1] if len(ordered) > 1 else 0.0
    gap = best_score - runner_up
    best = max(candidates, key=lambda g: scores[g]) if candidates else None

    def _fill(**kwargs) -> None:
        if trace is not None:
            trace.update(kwargs)

    # A single (or empty) candidate cannot be ambiguous: nothing to choose from.
    if len(detected) <= 1:
        _fill(
            source="rule" if detected else "skip",
            confidence=(best_score if best_score else (0.9 if detected else 0.0)),
            llm_used=False,
            llm_reason=None,
        )
        return detected

    if best_score >= LLM_TRADE_MIN_SCORE and gap >= LLM_TRADE_MIN_GAP:
        _fill(source="rule", confidence=best_score, llm_used=False, llm_reason=None)
        return {best}

    # Ambiguous: ask the LLM once, then decide.
    llm = _llm_trade_decision(task_text, candidates)
    if llm:
        _fill(
            source="llm",
            confidence=llm["confidence"],
            llm_used=True,
            llm_reason=llm.get("reason") or None,
        )
        if llm["confidence"] >= SKIP_CONFIDENCE_THRESHOLD:
            return {llm["trade"]}
        # Low-confidence LLM verdict: do not guess, keep the task unassignable.
        return set()

    # Degraded path (no key / timeout / parse failure): original behaviour.
    _fill(source="rule", confidence=best_score, llm_used=False, llm_reason=None)
    return detected


def _worker_trade_group(trade: str) -> Optional[str]:
    """Map a worker trade string to its canonical group, if any."""
    if not trade:
        return None
    t = trade.lower().strip()
    for group, keywords in TRADE_ALIASES.items():
        if t in keywords or t == group:
            return group
    # Bahasa Melayu installer/operator prefixes: strip "pemasang ", "tukang ",
    # "pengendali " and re-match against aliases (e.g. "pemasang jubin" -> tiling).
    for prefix in ("pemasang ", "tukang ", "pengendali "):
        if t.startswith(prefix):
            stripped = t[len(prefix):].strip()
            if stripped:
                for group, keywords in TRADE_ALIASES.items():
                    if stripped in keywords or stripped == group:
                        return group
    return None


def get_gemini_model():
    if not GEMINI_AVAILABLE or not GEMINI_API_KEY:
        return None
    try:
        return genai.GenerativeModel(GEMINI_MODEL)
    except Exception:
        return None


# ──────────────────────────────────────────────────────────────
#  AI decision logging (data loop for later hold-out evaluation)
# ──────────────────────────────────────────────────────────────

def _json_field(value: Any) -> Optional[str]:
    """Serialise a small structure for a TEXT column; None when empty."""
    if value is None:
        return None
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    except Exception:
        return None


def record_ai_decision(
    db,
    *,
    stage: str = "trade_resolution",
    task_id: Optional[int] = None,
    project_id: Optional[int] = None,
    task_text: str = "",
    rule_trades: Any = None,
    semantic_scores: Any = None,
    final_trade: Optional[str] = None,
    source: str = "rule",
    confidence: Optional[float] = None,
    elapsed_ms: Optional[int] = None,
    llm_used: bool = False,
    llm_reason: Optional[str] = None,
    skip_reason: Optional[str] = None,
) -> Optional["AIDecisionLog"]:
    """Append one audit row; never raise into the caller.

    The log is the raw material for the future evaluation set, so it must be
    written on every decision - but it is observability only: if the insert
    fails (missing table on an old DB, disk error, ...) the assignment pipeline
    still has to complete. A SAVEPOINT keeps a failed insert from poisoning the
    session that the caller is still using for task writes.
    """
    if db is None:
        return None
    row = AIDecisionLog(
        stage=stage,
        task_id=task_id,
        project_id=project_id,
        task_text=(task_text or "")[:2000] or None,
        rule_trades=_json_field(sorted(rule_trades) if isinstance(rule_trades, (set, list, tuple)) else rule_trades),
        semantic_scores=_json_field(
            {k: round(float(v), 4) for k, v in semantic_scores.items()}
            if isinstance(semantic_scores, dict) else semantic_scores
        ),
        final_trade=final_trade,
        source=source,
        confidence=(round(float(confidence), 4) if confidence is not None else None),
        elapsed_ms=elapsed_ms,
        llm_used=bool(llm_used),
        llm_reason=(llm_reason or None),
        skip_reason=skip_reason,
        was_overridden=False,
    )
    try:
        with db.begin_nested():
            db.add(row)
    except Exception:
        return None
    return row


def mark_decision_overridden(db, task_id: int, override_trade: Optional[str]) -> int:
    """Back-fill ``was_overridden`` when a supervisor hand-edits a task's trade.

    Only the newest ``auto_assign``/``trade_resolution`` row of that task is
    flagged: it is the prediction the supervisor actually reacted to. Returns
    the number of rows updated (0 when no AI decision existed).
    """
    if db is None or task_id is None:
        return 0
    try:
        row = (
            db.query(AIDecisionLog)
            .filter(AIDecisionLog.task_id == task_id)
            .order_by(AIDecisionLog.log_id.desc())
            .first()
        )
        if row is None:
            return 0
        row.was_overridden = True
        row.override_trade = (override_trade or None)
        db.flush()
        return 1
    except Exception:
        return 0


def _llm_trade_decision(task_text: str, candidates: List[str]) -> Optional[Dict[str, Any]]:
    """Ask Gemini for a single forced-JSON trade verdict.

    Returns ``{"trade", "confidence", "reason"}`` or ``None`` when the model is
    unavailable, the call fails/times out, or the payload cannot be parsed. The
    caller treats ``None`` as "keep the rule-based result", so a degraded model
    never changes behaviour.
    """
    model = get_gemini_model()
    if not model or not candidates:
        return None
    prompt = TRADE_DECISION_PROMPT.format(
        task_text=(task_text or "")[:1500],
        candidates=", ".join(sorted(candidates)),
    )
    try:
        try:
            resp = model.generate_content(
                prompt, request_options={"timeout": LLM_TRADE_TIMEOUT_SECONDS}
            )
        except TypeError:
            # Older google-generativeai releases reject request_options; the
            # call then runs without an explicit timeout (still guarded by the
            # try/except below so a failure degrades gracefully).
            resp = model.generate_content(prompt)
        parsed = _extract_json(getattr(resp, "text", "") or "")
    except Exception:
        return None
    if not isinstance(parsed, dict):
        return None

    raw_trade = str(parsed.get("trade") or "").strip().lower()
    trade = next((c for c in sorted(candidates) if c.lower() == raw_trade), None)
    if trade is None:
        return None
    try:
        confidence = float(parsed.get("confidence"))
    except (TypeError, ValueError):
        return None
    return {
        "trade": trade,
        "confidence": max(0.0, min(1.0, confidence)),
        "reason": str(parsed.get("reason") or "")[:500],
    }


def resolve_trade_decision(task_text: str, explicit_trade: str = "") -> Dict[str, Any]:
    """Resolve the required trade for a task text using the production pipeline.

    Order:
      1. explicit trade picked by the user (dropdown) wins outright;
      2. supervised classifier ``_classifier_trade_decision`` (dataset labels,
         keyword hits used as a prior) - this is what fixes the structural
         failures the keyword + centroid layers could not express;
      3. when the classifier is unavailable, OR when it abstains (lowest
         confidence) while keywords did fire: ``_detect_trade_groups`` +
         ``_resolve_detected_trades`` arbitration (semantic scores, optional
         Gemini fallback when configured);
      4. semantic supplement only when keywords found nothing AND the model has a
         clear winner (best >= 0.6 and gap >= 0.15 from runner-up).

    Extracted so the offline holdout evaluation in
    ``scripts/eval_holdout.py`` exercises exactly the same code path instead of a
    copy that can silently drift from production.
    """
    trace: Dict[str, Any] = {}
    keyword_trades: set = set()
    raw_semantic_scores: Dict[str, float] = {}
    classifier_scores: Dict[str, float] = {}

    explicit = (explicit_trade or "").strip().lower()
    explicit_group = _worker_trade_group(explicit) if explicit else None
    if explicit_group:
        detected_trades = {explicit_group}
        semantic_scores: Dict[str, float] = {explicit_group: 1.0}
        trade_source = "explicit"
        trace = {"source": "rule", "confidence": 1.0, "llm_used": False, "llm_reason": None}
    else:
        keyword_trades = _detect_trade_groups(task_text)
        # Compound-title families first (boilermaker / * handler / wallpaper /
        # soldering-machine operator): the deciding token is the head noun, which
        # no similarity model can weigh against the surrounding words.
        structured = _structured_title_trade(task_text) if _STRUCTURED_RULES else None
        classified = None
        if structured:
            detected_trades = {structured}
            semantic_scores = {structured: 1.0}
            trade_source = "title-rule"
            trace = {"source": "rule", "confidence": 0.95, "llm_used": False,
                     "llm_reason": None, "rule": structured}
        else:
            # Classifier next: it is the only layer trained on the row labels, and
            # it is where the plasterer / material-handler / machine-operator
            # families are resolved. ``None`` = no artefact -> legacy path.
            classified = _classifier_trade_decision(task_text, keyword_trades, trace=trace)
            if classified is not None:
                detected_trades = classified
                classifier_scores = _classifier_trade_scores(task_text)
                semantic_scores = raw_semantic_scores = classifier_scores
                trade_source = "classifier"
                # The classifier refused to guess, but the hand-checked keyword
                # layer saw something: let the arbitration (keyword scores +
                # optional LLM) take over rather than dropping the task.
                if not detected_trades and keyword_trades:
                    detected_trades = _resolve_detected_trades(
                        task_text, keyword_trades, dict(_semantic_trade_scores(task_text)),
                        trace=trace,
                    )
                    trade_source = "semantic"
            else:
                raw_semantic_scores = _semantic_trade_scores(task_text)
                semantic_scores = raw_semantic_scores
                detected_trades = _resolve_detected_trades(
                    task_text, keyword_trades, semantic_scores, trace=trace
                )
                trade_source = "semantic"
        if not detected_trades and trace.get("source") != "llm":
            if semantic_scores:
                best_trade, best_score = max(semantic_scores.items(), key=lambda x: x[1])
                sorted_scores = sorted(semantic_scores.values(), reverse=True)
                gap = best_score - (sorted_scores[1] if len(sorted_scores) > 1 else 0.0)
                if best_score >= 0.6 and gap >= 0.15:
                    detected_trades = {best_trade}
                    trace = {"source": "semantic", "confidence": best_score,
                             "llm_used": False, "llm_reason": None}
        elif detected_trades:
            semantic_scores = {canonical: 1.0 for canonical in detected_trades}

    if explicit_group:
        confidence = 1.0
    elif detected_trades:
        confidence = float(trace.get("confidence") or 0.0)
        if confidence <= 0.0:
            confidence = max((raw_semantic_scores.get(g, 0.0) for g in detected_trades), default=0.0)
        if confidence <= 0.0:
            # No semantic model available: a single unambiguous keyword hit is
            # strong evidence, several competing hits are not.
            confidence = 0.9 if len(detected_trades) == 1 else 0.6
    else:
        confidence = 0.0

    low_confidence = explicit_group is None and not detected_trades
    if low_confidence:
        trace.setdefault("source", "skip")
        trace["confidence"] = 0.0

    return {
        "detected_trades": detected_trades,
        "semantic_scores": semantic_scores,
        "raw_semantic_scores": raw_semantic_scores,
        "keyword_trades": keyword_trades,
        "classifier_scores": classifier_scores,
        "trace": trace,
        "confidence": confidence,
        "low_confidence": low_confidence,
        "explicit_group": explicit_group,
        "trade_source": trade_source,
    }


def analyze_task(
    db,
    task_info: Dict[str, Any],
    project_id: int,
    same_project_only: bool = False,
    log_decision: bool = True,
) -> Dict[str, Any]:
    started = time.perf_counter()
    if same_project_only:
        workers = get_project_workers(db, project_id)
    else:
        workers = db.query(Worker).all()
    project = db.query(Project).filter(Project.project_id == project_id).first()

    task_name = task_info.get("task_name", "")
    description = task_info.get("description", "")
    task_text = f"{task_name} {description}".lower()

    # Trade resolution (explicit trade > keyword detection > arbitration > semantic
    # supplement). Extracted into resolve_trade_decision() so the offline holdout
    # evaluation runs the exact same pipeline; see its docstring for the order.
    decision = resolve_trade_decision(task_text, task_info.get("trade") or "")
    detected_trades = decision["detected_trades"]
    semantic_scores = decision["semantic_scores"]
    raw_semantic_scores = decision["raw_semantic_scores"]
    keyword_trades = decision["keyword_trades"]
    trace = decision["trace"]
    confidence = decision["confidence"]
    low_confidence = decision["low_confidence"]
    explicit_group = decision["explicit_group"]
    trade_source = decision["trade_source"]


    suggested_workers = []
    matched_any = False
    for worker in workers:
        score = 50
        reasons = []

        wgroup = _worker_trade_group(worker.trade)
        if wgroup in detected_trades:
            strength = semantic_scores.get(wgroup, 0.5)
            score += int(20 + 30 * strength)
            matched_any = True
            reasons.append("Trade semantic match: {} (confidence {:.0%})".format(worker.trade, strength))
        elif wgroup:
            score -= 15
            reasons.append("Trade does not match task requirement: {}".format(worker.trade))
        elif worker.trade:
            score += 5
            reasons.append("Available trade: {}".format(worker.trade))

        attendance_today = db.query(AttendanceLog).filter(
            AttendanceLog.worker_id == worker.worker_id,
            AttendanceLog.check_in_time >= date.today()
        ).first()

        if attendance_today and attendance_today.status in ("checked_in", "checked_out"):
            score += 15
            reasons.append("Already checked in today")

        if worker.has_safety_training:
            score += 3
            reasons.append("Safety training completed")
        if worker.is_safety_officer:
            score += 2
            reasons.append("Is a safety officer")

        suggested_workers.append({
            "worker_id": worker.worker_id,
            "name": worker.name,
            "trade": worker.trade or "General",
            "score": min(score, 100),
            "reasons": reasons,
            "available_today": attendance_today is not None
        })

    suggested_workers.sort(key=lambda x: x["score"], reverse=True)

    priority = "medium"
    task_text_low = task_text
    if any(keyword in task_text_low for keyword in ["安全", "紧急", "critical", "urgent", "foundation", "结构"]):
        priority = "high"
    elif any(keyword in task_text_low for keyword in ["清洁", "整理", "cleaning"]):
        priority = "low"

    # Dataset-informed duration estimate: sum standard duration of detected trades.
    if detected_trades:
        est_days = max(TRADE_DURATION.get(g, 1.5) for g in detected_trades)
        duration_estimate = "Based on industry standard man-hours for task type ({}), estimated {:.0f}-{:.0f} days".format(
            "/".join(sorted(detected_trades)), max(1, est_days - 0.5), est_days + 1
        )
    else:
        duration_estimate = "Based on task complexity, estimated 1-3 days"

    if low_confidence:
        notice = (
            "Task title/description is too vague to identify a required trade "
            "(e.g. test). Edit the task with a specific title/description or "
            "select an explicit trade — no worker will be auto-assigned."
        )
    elif not matched_any and detected_trades:
        notice = "No workers match the required trade ({}), showing alternative candidates".format(
            "/".join(sorted(detected_trades))
        )
    else:
        notice = ""

    source = str(trace.get("source") or ("rule" if explicit_group else "semantic"))
    if low_confidence:
        source = "skip"
        confidence = 0.0
    elapsed_ms = int((time.perf_counter() - started) * 1000)

    if log_decision:
        record_ai_decision(
            db,
            stage="trade_resolution",
            task_id=task_info.get("task_id"),
            project_id=project_id,
            task_text=task_text,
            rule_trades=sorted(keyword_trades) if keyword_trades else None,
            semantic_scores=raw_semantic_scores or None,
            final_trade=(sorted(detected_trades)[0] if detected_trades else None),
            source=source,
            confidence=confidence,
            elapsed_ms=elapsed_ms,
            llm_used=bool(trace.get("llm_used")),
            llm_reason=trace.get("llm_reason"),
            skip_reason=("no trade identified from task text" if low_confidence else None),
        )

    return {
        "suggested_workers": suggested_workers[:5],
        "estimated_duration": duration_estimate,
        "priority_suggestion": priority,
        "safety_notes": "Please ensure construction workers wear the necessary safety protective equipment and follow on-site safety regulations.",
        "matched_trades": sorted(detected_trades),
        "trade_source": trade_source,
        "semantic_used": bool(semantic_scores),
        "notice": notice,
        "low_confidence": low_confidence,
        "assignable": not low_confidence,
        # Decision metadata (consumed by auto-assign logging; harmless elsewhere).
        "confidence": confidence,
        "decision_source": source,
        "llm_used": bool(trace.get("llm_used")),
        "llm_reason": trace.get("llm_reason"),
        "elapsed_ms": elapsed_ms,
        "keyword_trades": sorted(keyword_trades),
        "semantic_scores": {k: round(float(v), 4) for k, v in (semantic_scores or {}).items()},
    }


def generate_daily_report(db, project_id: int, report_date: date) -> str:
    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return "Project not found"

    workers = get_project_workers(db, project_id)
    tasks = db.query(Task).filter(Task.project_id == project_id).all()
    issues = db.query(Issue).filter(Issue.project_id == project_id, Issue.status != "resolved").all()
    attendance = db.query(AttendanceLog).filter(
        AttendanceLog.project_id == project_id,
        AttendanceLog.check_in_time >= report_date
    ).all()

    present_count = sum(1 for a in attendance if a.status in ("checked_in", "checked_out"))
    completed_tasks = sum(1 for t in tasks if t.status == "completed")
    pending_tasks = sum(1 for t in tasks if t.status == "pending")
    in_progress_tasks = sum(1 for t in tasks if t.status == "in_progress")

    report = f"""# {project.project_name} - {report_date.strftime('%Y-%m-%d')} Daily Work Report

## Attendance
- Total workers: {len(workers)}
- Present today: {present_count}
- Absent: {len(workers) - present_count}

## Task Progress
- Completed: {completed_tasks}
- In progress: {in_progress_tasks}
- Pending: {pending_tasks}

## Open Issues
- Open issues: {len(issues)}
"""

    if issues:
        report += "\nIssue List:\n"
        for issue in issues:
            report += f"- {issue.title}\n"

    report += "\nNote: This report is auto-generated by AI. Please adjust and supplement it based on the actual situation."

    return report


def analyze_safety_risk(description: str) -> str:
    model = get_gemini_model()
    if not model:
        return "AI service unavailable, unable to perform safety analysis."

    prompt = f"""Please analyze the following construction safety incident description, assess the risk level, and provide recommendations:

Incident description: {description}

Please answer in the following format:
Risk level: [High/Medium/Low]
Risk analysis: [Brief analysis]
Recommended actions: [Suggested measures]
"""

    try:
        response = model.generate_content(prompt)
        return response.text
    except Exception:
        return "Safety analysis is temporarily unavailable, please assess manually."


def _worker_metrics(db, worker: Worker) -> Dict[str, Any]:
    today = date.today()
    since_7 = datetime.combine(today - timedelta(days=7), datetime.min.time())
    since_30 = datetime.combine(today - timedelta(days=30), datetime.min.time())

    att = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == worker.worker_id,
        AttendanceLog.check_in_time >= since_7
    ).all()

    present_days = set()
    for a in att:
        try:
            present_days.add(a.check_in_time.date())
        except Exception:
            pass

    tasks = db.query(Task).filter(Task.assigned_worker_id == worker.worker_id).all()
    active_tasks = [t for t in tasks if (t.status or "pending") != "completed"]
    completed_30 = 0
    overdue_active = 0
    for t in tasks:
        if (t.status or "pending") == "completed":
            completed_30 += 1
        else:
            if t.due_date and t.due_date < today:
                overdue_active += 1

    attended_recent = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == worker.worker_id,
        AttendanceLog.check_in_time >= since_30,
        AttendanceLog.status.in_(("checked_in", "checked_out"))
    ).count()

    return {
        "worker_id": worker.worker_id,
        "name": worker.name,
        "trade": worker.trade or "General",
        "active_task_count": len(active_tasks),
        "overdue_active_task_count": overdue_active,
        "present_days_last_7": len(present_days),
        "attendance_logs_last_30": attended_recent,
        "has_safety_training": bool(worker.has_safety_training),
        "is_safety_officer": bool(worker.is_safety_officer),
    }


def _extract_json(text: str) -> Optional[Any]:
    if not text:
        return None
    try:
        return json.loads(text)
    except Exception:
        pass
    m = re.search(r"(\{[\s\S]*\}|\[[\s\S]*\])", text)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except Exception:
        return None


def _copy_decision_meta(target: Dict[str, Any], source: Dict[str, Any]) -> None:
    """Copy trade-decision metadata onto a Gemini-shaped recommendation payload.

    ``recommend_workers_for_task`` may return the model's own dict; the decision
    provenance (and the guard flags) must survive that path or auto-assign would
    log an empty decision and could bypass the low-confidence guard.
    """
    for key in ("low_confidence", "assignable", "matched_trades", "confidence",
                "decision_source", "llm_used", "llm_reason", "elapsed_ms",
                "keyword_trades", "semantic_scores"):
        if key in source:
            target[key] = source[key]


def recommend_workers_for_task(db, task_info: Dict[str, Any], project_id: int, top_k: int = 5, same_project_only: bool = False, log_decision: bool = True) -> Dict[str, Any]:
    if same_project_only:
        workers = get_project_workers(db, project_id)
    else:
        workers = db.query(Worker).all()
    task_name = task_info.get("task_name", "")
    description = task_info.get("description", "")

    model = get_gemini_model()
    if model:
        profiles = [_worker_metrics(db, w) for w in workers]
        prompt = {
            "task": {"task_name": task_name, "description": description, "project_id": project_id},
            "workers": profiles,
            "output_format": {
                "suggested_workers": [
                    {
                        "worker_id": 0,
                        "name": "",
                        "trade": "",
                        "score": 0,
                        "reasons": [""],
                        "available_today": False
                    }
                ]
            }
        }
        try:
            resp = model.generate_content(
                "Based on the following JSON input, recommend the most suitable workers for this task (up to {}). Output JSON only, no extra text.\n\n{}".format(
                    top_k, json.dumps(prompt, ensure_ascii=False)
                )
            )
            parsed = _extract_json(getattr(resp, "text", "") or "")
            base_for_trades = analyze_task(db, task_info, project_id, same_project_only=same_project_only, log_decision=log_decision)
            if isinstance(parsed, dict) and isinstance(parsed.get("suggested_workers"), list):
                out = parsed
                out["suggested_workers"] = out["suggested_workers"][:top_k]
                out["semantic_used"] = True
                out["matched_trades"] = base_for_trades.get("matched_trades") or []
                out["low_confidence"] = base_for_trades.get("low_confidence", False)
                out["assignable"] = base_for_trades.get("assignable", True)
                _copy_decision_meta(out, base_for_trades)
                return out
            if isinstance(parsed, list):
                out = {"suggested_workers": parsed[:top_k], "semantic_used": True,
                       "matched_trades": base_for_trades.get("matched_trades") or [],
                       "low_confidence": base_for_trades.get("low_confidence", False),
                       "assignable": base_for_trades.get("assignable", True)}
                _copy_decision_meta(out, base_for_trades)
                return out
        except Exception:
            pass

    base = analyze_task(db, task_info, project_id, same_project_only=same_project_only, log_decision=log_decision)
    base["suggested_workers"] = (base.get("suggested_workers") or [])[:top_k]
    return base


def auto_assign_tasks(
    db,
    project_id: Optional[int] = None,
    task_ids: Optional[List[int]] = None,
    dry_run: bool = True,
    top_k: int = 3,
    same_project_only: bool = False
) -> Dict[str, Any]:
    q = db.query(Task)
    if project_id is not None:
        q = q.filter(Task.project_id == project_id)
    if task_ids:
        q = q.filter(Task.task_id.in_(task_ids))
    q = q.filter(Task.status != "completed")
    tasks = q.order_by(Task.due_date.is_(None), Task.due_date.asc(), Task.task_id.asc()).all()

    # Auto-assign normally matches against the whole worker pool (same as the
    # analyze screen default) so tasks in projects without bound workers can
    # still get matched. When same_project_only=True the pool is restricted to
    # workers bound to the requested project (requires project_id); the trade
    # matching still guarantees the right trade wins within that pool.
    if same_project_only and project_id is not None:
        workers = get_project_workers(db, project_id)
    else:
        workers = db.query(Worker).all()
    worker_ids = {w.worker_id for w in workers}

    assignments = []
    for t in tasks:
        task_started = time.perf_counter()
        task_info = {
            "task_id": t.task_id,
            "task_name": t.task_name,
            "description": t.description or "",
            "trade": t.trade or "",
        }
        # ``log_decision=False``: auto-assign writes its own single row per task
        # (stage="auto_assign") that also carries the final assignment outcome,
        # so one evaluation sample == one row.
        rec = recommend_workers_for_task(
            db, task_info, project_id, top_k=max(1, top_k),
            same_project_only=same_project_only, log_decision=False,
        )
        suggested = rec.get("suggested_workers") or []
        matched_trades = set(rec.get("matched_trades") or [])

        def _log(task=t, rec=rec, started=task_started, source=None, skip_reason=None,
                 chosen_ids=None, matched=None):
            """Write one auto_assign audit row for this task (best effort).

            Dry runs are pure previews and must not touch the audit table, so
            the row is only written when ``dry_run`` is False.
            """
            if dry_run:
                return
            trades = matched if matched is not None else set(rec.get("matched_trades") or [])
            if skip_reason and not trades and rec.get("low_confidence"):
                decided_source = "skip"
            else:
                decided_source = source or str(rec.get("decision_source") or "rule")
            record_ai_decision(
                db,
                stage="auto_assign",
                task_id=t.task_id,
                project_id=t.project_id,
                task_text=f"{t.task_name} {t.description or ''}".strip(),
                rule_trades=(rec.get("keyword_trades") or None),
                semantic_scores=(rec.get("semantic_scores") or None),
                final_trade=(sorted(trades)[0] if trades else None),
                source=decided_source,
                confidence=float(rec.get("confidence") or 0.0),
                elapsed_ms=int((time.perf_counter() - started) * 1000),
                llm_used=bool(rec.get("llm_used")),
                llm_reason=rec.get("llm_reason"),
                skip_reason=skip_reason,
            )

        # Vague-task guard: text could not identify a required trade and there
        # is no explicit trade -> never auto-assign (prevents e.g. "test/test"
        # being dumped on an arbitrary worker).
        if rec.get("low_confidence"):
            skip_reason = "Task text too vague to identify required trade; set explicit trade or specific description"
            assignments.append({
                "task_id": t.task_id,
                "task_name": t.task_name,
                "assigned_worker_id": None,
                "assigned_worker_ids": [],
                "suggested_workers": [],
                "ai_used": bool(get_gemini_model()) or bool(_load_trade_matcher()),
                "skipped": True,
                "skip_reason": skip_reason,
            })
            _log(skip_reason=skip_reason, source="skip")
            continue

        # Missing-trade guard: the task demands a trade but no worker in the
        # current pool belongs to it -> skip rather than assign a wrong-trade
        # worker (would repeat the old "electric task assigned to carpenter" bug).
        if matched_trades:
            pool_trade_hit = any(_worker_trade_group(w.trade) in matched_trades for w in workers)
            if not pool_trade_hit:
                skip_reason = "No worker with required trade ({}) is available in the worker pool; add a worker with that trade or edit the task".format(
                    "/".join(sorted(matched_trades))
                )
                assignments.append({
                    "task_id": t.task_id,
                    "task_name": t.task_name,
                    "assigned_worker_id": None,
                    "assigned_worker_ids": [],
                    "suggested_workers": [],
                    "ai_used": bool(get_gemini_model()) or bool(_load_trade_matcher()),
                    "skipped": True,
                    "skip_reason": skip_reason,
                })
                _log(skip_reason=skip_reason)
                continue

        # Re-evaluate tasks that already have a full assignment: skip them only
        # when the currently assigned workers actually match the task demand.
        # A pre-existing AI mis-assignment (e.g. "electric" task assigned to a
        # carpenter) must be corrected on the next auto-assign run, otherwise the
        # wrong assignment stays forever. Legacy rows with only assigned_worker_id
        # are always processed to backfill task_workers links.
        if t.assigned_worker_id and t.task_workers:
            current_ok = False
            for tw in t.task_workers:
                w = next((x for x in workers if x.worker_id == tw.worker_id), None)
                if w is None:
                    continue
                wg = _worker_trade_group(w.trade)
                if wg in matched_trades:
                    current_ok = True
                    break
            if current_ok:
                continue

        # Pick up to top_k valid workers, ordered by match score (multi-worker).
        chosen_ids: List[int] = []
        for item in suggested:
            wid = item.get("worker_id") if isinstance(item, dict) else None
            if wid is not None and int(wid) in worker_ids and int(wid) not in chosen_ids:
                chosen_ids.append(int(wid))
            if len(chosen_ids) >= max(1, top_k):
                break

        if not dry_run and chosen_ids:
            # SQLAlchemy flushes INSERTs before DELETEs within the same flush,
            # so replacing the collection directly would re-insert a kept
            # worker id and violate the unique (task_id, worker_id) constraint.
            # Delete existing links first, expire the collection so the next
            # load sees an empty DB, then attach the new ones.
            for tw in list(t.task_workers):
                db.delete(tw)
            db.flush()
            db.expire(t, ["task_workers"])
            t.task_workers = [TaskWorker(worker_id=wid) for wid in chosen_ids]
            t.assigned_worker_id = chosen_ids[0]

        assignments.append({
            "task_id": t.task_id,
            "task_name": t.task_name,
            "assigned_worker_id": chosen_ids[0] if chosen_ids else None,
            "assigned_worker_ids": chosen_ids,
            "suggested_workers": suggested,
            "ai_used": bool(get_gemini_model()) or bool(_load_trade_matcher()),
            "skipped": False,
            "skip_reason": None,
        })
        _log(chosen_ids=chosen_ids)

    if not dry_run:
        db.commit()

    return {
        "project_id": project_id,
        "dry_run": dry_run,
        "assignments": assignments
    }

# ──────────────────────────────────────────────────────────────
#  AI Site Progress Prediction
# ──────────────────────────────────────────────────────────────

def predict_site_progress(db, project_id: int) -> Dict[str, Any]:
    """
    AI-powered site progress prediction.
    Analyses historical task completion trends, attendance, overdue patterns
    and uses Gemini to predict:
      - Estimated completion date
      - Predicted progress at 7/14/30/60/90-day milestones
      - Trend: ahead / on_track / behind / critical
      - Confidence level
      - Risk factors & recommendations
    Falls back to rule-based calculation if Gemini is unavailable.
    """
    today = date.today()
    since_7 = datetime.combine(today - timedelta(days=7), datetime.min.time())
    since_14 = datetime.combine(today - timedelta(days=14), datetime.min.time())
    since_30 = datetime.combine(today - timedelta(days=30), datetime.min.time())

    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return {"error": "Project not found"}

    # ── Core metrics ──
    all_tasks = db.query(Task).filter(Task.project_id == project_id).all()
    total_tasks = len(all_tasks)
    completed = sum(1 for t in all_tasks if t.status == "completed")
    in_progress = sum(1 for t in all_tasks if t.status == "in_progress")
    pending = sum(1 for t in all_tasks if t.status == "pending")
    overdue = sum(1 for t in all_tasks if t.due_date and t.due_date < today and t.status != "completed")
    unassigned = sum(1 for t in all_tasks if not t.assigned_worker_id and t.status != "completed")
    current_progress = round(completed / total_tasks * 100, 1) if total_tasks > 0 else 0.0

    # ── Scheduled progress (linear plan timeline vs actual) ──
    # scheduled_progress = % the project *should* be at today on the planned
    # start_date -> end_date timeline. Fall back to earliest/latest task due_date
    # when the project has no explicit start/end date.
    plan_start = project.start_date
    plan_end = project.end_date
    task_due_dates = [t.due_date for t in all_tasks if t.due_date]
    if plan_start is None and task_due_dates:
        plan_start = min(task_due_dates)
    if plan_end is None and task_due_dates:
        plan_end = max(task_due_dates)

    scheduled_progress = None
    if plan_start and plan_end:
        total_plan_days = (plan_end - plan_start).days
        if total_plan_days > 0:
            elapsed_plan_days = (today - plan_start).days
            if elapsed_plan_days <= 0:
                scheduled_progress = 0.0
            elif elapsed_plan_days >= total_plan_days:
                scheduled_progress = 100.0
            else:
                scheduled_progress = round(elapsed_plan_days / total_plan_days * 100, 1)
    progress_gap = round(current_progress - scheduled_progress, 1) if scheduled_progress is not None else None

    # ── Velocity (tasks completed per week, last 4 weeks) ──
    velocity_data = []
    for weeks_ago in range(4, 0, -1):
        week_start = today - timedelta(weeks=weeks_ago * 7)
        week_end = week_start + timedelta(days=7)
        # Heuristic: tasks marked completed between week_start and week_end
        # Since we don't have completion timestamps, we approximate:
        #   if today - start_date of tasks suggests recent completion
        # For now we use a fallback: divide completed by project lifetime in weeks
        pass

    # Simplified weekly velocity: estimate based on project duration
    if project.start_date:
        project_age_days = max((today - project.start_date).days, 1)
        project_age_weeks = max(project_age_days / 7, 1)
        weekly_velocity = completed / project_age_weeks
    else:
        weekly_velocity = max(completed / 4, 0.5) if completed > 0 else 0.5

    remaining_tasks = total_tasks - completed
    estimated_weeks_remaining = (remaining_tasks / weekly_velocity) if weekly_velocity > 0 else 999

    # Dataset-augmented estimate: standard workdays per trade for remaining tasks,
    # divided by workforce size (5 workdays/week).
    semantic_remaining_days = 0.0
    remaining_trade_mix: Dict[str, int] = defaultdict(int)
    workers_sem = get_project_workers(db, project_id)
    total_workers_sem = len(workers_sem)
    for t in all_tasks:
        if t.status == "completed":
            continue
        tt = f"{t.task_name} {t.description or ''}".lower()
        scores = _semantic_trade_scores(tt)
        trade = max(scores, key=scores.get) if scores else None
        semantic_remaining_days += TRADE_DURATION.get(trade, 1.5)
        if trade:
            remaining_trade_mix[trade] += 1
    if total_workers_sem > 0:
        semantic_weeks = semantic_remaining_days / max(total_workers_sem, 1) / 5.0
    else:
        semantic_weeks = 999.0
    # Blend velocity estimate with semantic workload estimate (50/50) when both sane.
    if estimated_weeks_remaining < 900 and semantic_weeks < 900:
        estimated_weeks_remaining = 0.5 * estimated_weeks_remaining + 0.5 * semantic_weeks
    elif semantic_weeks < 900:
        estimated_weeks_remaining = semantic_weeks
    rule_based_completion_date = today + timedelta(weeks=estimated_weeks_remaining)

    # ── Attendance trend ──
    workers = get_project_workers(db, project_id)
    total_workers = len(workers)

    att_7 = db.query(AttendanceLog).filter(
        AttendanceLog.project_id == project_id,
        AttendanceLog.check_in_time >= since_7,
        AttendanceLog.status.in_(("checked_in", "checked_out"))
    ).count()
    att_14 = db.query(AttendanceLog).filter(
        AttendanceLog.project_id == project_id,
        AttendanceLog.check_in_time >= since_14,
        AttendanceLog.status.in_(("checked_in", "checked_out"))
    ).count()
    att_30 = db.query(AttendanceLog).filter(
        AttendanceLog.project_id == project_id,
        AttendanceLog.check_in_time >= since_30,
        AttendanceLog.status.in_(("checked_in", "checked_out"))
    ).count()

    avg_daily_att_7 = round(att_7 / 7, 1) if att_7 > 0 else 0
    avg_daily_att_14 = round(att_14 / 14, 1) if att_14 > 0 else 0
    avg_daily_att_30 = round(att_30 / 30, 1) if att_30 > 0 else 0

    # ── Issue trend ──
    open_issues = db.query(Issue).filter(
        Issue.project_id == project_id,
        Issue.status.in_(["open", "in_progress"])
    ).count()
    total_issues = db.query(Issue).filter(Issue.project_id == project_id).count()

    # ── Trend detection ──
    overdue_ratio = overdue / total_tasks if total_tasks > 0 else 0
    attendance_declining = avg_daily_att_7 < avg_daily_att_30 * 0.85 if avg_daily_att_30 > 0 else False

    # ── Rule-based trend & predictions ──
    if overdue_ratio > 0.3 or (attendance_declining and current_progress < 30):
        rule_trend = "critical"
    elif overdue_ratio > 0.15:
        rule_trend = "behind"
    elif current_progress > 70 and overdue == 0:
        rule_trend = "ahead"
    else:
        rule_trend = "on_track"

    # Predict progress at future milestones (rule-based)
    daily_velocity_pct = (weekly_velocity / 7 / total_tasks * 100) if total_tasks > 0 else 1.0
    pred_7d = min(100, round(current_progress + daily_velocity_pct * 7, 1))
    pred_14d = min(100, round(current_progress + daily_velocity_pct * 14, 1))
    pred_30d = min(100, round(current_progress + daily_velocity_pct * 30, 1))
    pred_60d = min(100, round(current_progress + daily_velocity_pct * 60, 1))
    pred_90d = min(100, round(current_progress + daily_velocity_pct * 90, 1))

    rule_risk_factors = []
    if overdue > 0:
        rule_risk_factors.append(f"{overdue} overdue task(s) — risk of cascading delays")
    if unassigned > 0:
        rule_risk_factors.append(f"{unassigned} unassigned task(s) — idle resources")
    if attendance_declining:
        rule_risk_factors.append("Declining attendance trend — reduced workforce on site")
    if open_issues > 0:
        rule_risk_factors.append(f"{open_issues} unresolved issues blocking progress")
    if project.end_date and rule_based_completion_date > project.end_date:
        days_late = (rule_based_completion_date - project.end_date).days
        rule_risk_factors.append(f"Predicted {days_late} days past deadline based on current velocity")

    rule_recommendations = []
    if overdue > 0:
        rule_recommendations.append(f"Prioritise {overdue} overdue tasks immediately")
    if unassigned > 0:
        rule_recommendations.append(f"Use AI Auto-Assign to allocate {unassigned} unassigned tasks")
    if attendance_declining:
        rule_recommendations.append("Review attendance policy — workforce declining")
    if daily_velocity_pct < 1.0 and total_tasks > 0:
        rule_recommendations.append("Consider adding shifts or subcontractors to increase velocity")
    if project.end_date and rule_based_completion_date > project.end_date:
        rule_recommendations.append(f"Re-negotiate deadline or fast-track critical-path tasks")

    # ── AI-powered refinement ──
    model = get_gemini_model()
    ai_trend = rule_trend
    ai_confidence = 70.0
    ai_insights = ""
    ai_predicted_date = rule_based_completion_date
    ai_risk_factors = list(rule_risk_factors)
    ai_recommendations = list(rule_recommendations)
    ai_milestones = [
        {"label": "7 days", "predicted_progress": pred_7d},
        {"label": "14 days", "predicted_progress": pred_14d},
        {"label": "30 days", "predicted_progress": pred_30d},
        {"label": "60 days", "predicted_progress": pred_60d},
        {"label": "90 days", "predicted_progress": pred_90d},
    ]

    if model:
        prompt_data = {
            "project_name": project.project_name,
            "current_progress_pct": current_progress,
            "scheduled_progress_pct": scheduled_progress,
            "progress_gap_pct": progress_gap,
            "total_tasks": total_tasks,
            "completed": completed,
            "in_progress": in_progress,
            "pending": pending,
            "overdue": overdue,
            "unassigned": unassigned,
            "weekly_velocity_tasks": round(weekly_velocity, 2),
            "remaining_tasks": remaining_tasks,
            "total_workers": total_workers,
            "avg_daily_attendance_7d": avg_daily_att_7,
            "avg_daily_attendance_14d": avg_daily_att_14,
            "avg_daily_attendance_30d": avg_daily_att_30,
            "open_issues": open_issues,
            "planned_start_date": project.start_date.isoformat() if project.start_date else None,
            "planned_end_date": project.end_date.isoformat() if project.end_date else None,
            "rule_based_completion_date": rule_based_completion_date.isoformat(),
            "rule_trend": rule_trend,
        }
        prompt = f"""You are a construction project analyst. Based on the following project data, predict the site progress trajectory. Respond ONLY with valid JSON, no markdown fences.

Project Data:
{json.dumps(prompt_data, ensure_ascii=False)}

Output format (strict JSON):
{{
  "trend": "<ahead|on_track|behind|critical>",
  "confidence": <integer 50-100, how confident the AI is in this prediction>,
  "predicted_completion_date": "<YYYY-MM-DD>",
  "ai_insights": "<2-3 sentence analysis in English. MUST compare current_progress_pct vs scheduled_progress_pct: state whether the project is ahead/behind the planned timeline and by how much (progress_gap_pct), and whether it can finish by the planned end date at the current pace. If scheduled_progress_pct is null, analyse the trajectory without the plan comparison.>",
  "risk_factors": ["<risk 1>", "<risk 2>", "<risk 3>"],
  "recommendations": ["<action 1>", "<action 2>", "<action 3>"],
  "milestones": [
    {{"label": "7 days", "predicted_progress": <float 0-100>}},
    {{"label": "14 days", "predicted_progress": <float 0-100>}},
    {{"label": "30 days", "predicted_progress": <float 0-100>}},
    {{"label": "60 days", "predicted_progress": <float 0-100>}},
    {{"label": "90 days", "predicted_progress": <float 0-100>}}
  ]
}}"""
        try:
            resp = model.generate_content(prompt)
            parsed = _extract_json(getattr(resp, "text", "") or "")
            if isinstance(parsed, dict):
                ai_trend = str(parsed.get("trend", rule_trend)).lower()
                ai_confidence = float(parsed.get("confidence", 70))
                ai_insights = str(parsed.get("ai_insights", ""))
                predicted_date_str = parsed.get("predicted_completion_date")
                if predicted_date_str:
                    try:
                        ai_predicted_date = date.fromisoformat(str(predicted_date_str))
                    except Exception:
                        pass
                if parsed.get("risk_factors"):
                    ai_risk_factors = [str(r) for r in parsed["risk_factors"]]
                if parsed.get("recommendations"):
                    ai_recommendations = [str(r) for r in parsed["recommendations"]]
                if parsed.get("milestones"):
                    ai_milestones = parsed["milestones"]
        except Exception:
            pass

    if not ai_insights:
        trend_labels = {
            "ahead": f"Project is ahead of schedule at {current_progress}% completion.",
            "on_track": f"Project is progressing steadily at {current_progress}% completion.",
            "behind": f"Project is behind schedule — {overdue} overdue tasks and {current_progress}% completion.",
            "critical": f"Project is at critical risk — {overdue} overdue tasks, only {current_progress}% complete.",
        }
        ai_insights = trend_labels.get(ai_trend, f"Project at {current_progress}% completion.")
        if project.end_date:
            ai_insights += f" Planned end date: {project.end_date.isoformat()}."

    # ── Persist a snapshot for the prediction-accuracy history ──
    db.add(PredictionHistory(
        project_id=project_id,
        predicted_progress=current_progress,
        scheduled_progress=scheduled_progress,
        actual_progress=current_progress,
        predicted_completion_date=ai_predicted_date,
        trend=ai_trend,
        confidence=round(ai_confidence, 1),
    ))
    db.commit()

    return {
        "project_id": project_id,
        "project_name": project.project_name,
        "generated_at": datetime.utcnow().isoformat(),
        "current_progress": current_progress,
        "scheduled_progress": scheduled_progress,
        "progress_gap": progress_gap,
        "estimated_days_remaining": max((ai_predicted_date - today).days, 0),
        "planned_start_date": project.start_date.isoformat() if project.start_date else None,
        "planned_end_date": project.end_date.isoformat() if project.end_date else None,
        "predicted_completion_date": ai_predicted_date.isoformat(),
        "trend": ai_trend,
        "confidence": round(ai_confidence, 1),
        "ai_insights": ai_insights,
        "ai_used": bool(model),
        "velocity": {
            "weekly_tasks_completed": round(weekly_velocity, 2),
            "remaining_tasks": remaining_tasks,
            "estimated_weeks_remaining": round(estimated_weeks_remaining, 1),
            "semantic_remaining_workdays": round(semantic_remaining_days, 1),
            "remaining_trade_mix": dict(remaining_trade_mix),
        },
        "attendance_trend": {
            "avg_daily_7d": avg_daily_att_7,
            "avg_daily_14d": avg_daily_att_14,
            "avg_daily_30d": avg_daily_att_30,
            "declining": attendance_declining,
            "total_workers": total_workers,
        },
        "issues": {
            "open": open_issues,
            "total": total_issues,
        },
        "risk_factors": ai_risk_factors,
        "recommendations": ai_recommendations,
        "milestones": ai_milestones,
    }
