"""Single source of truth for the worker trade / skill level.

Site workers are classified into four skill levels (Malaysian construction
practice). Those four strings are the ONLY values that may be stored in
``workers.trade`` and ``tasks.trade`` from now on; the legacy 16 fine-grained
trades (carpenter / electrical / plumbing / ...) are retired from the stored
value space.

The fine-grained vocabulary is deliberately kept *inside this module* as an
input layer, because it is still needed twice:

* historical rows written before the change must stay readable and migratable
  (``MIGRATION_MAP`` below is what the migration script generates UPDATEs from);
* the AI text pipeline carries most of its signal at the fine grain (a task
  description says "rewire the DB panel", not "skilled worker"), so it reasons
  at the fine grain and collapses its verdict to one of the four levels at the
  end (see ``ai_service._collapse_to_levels``).

Import direction is one-way: ``ai_service`` imports this module, never the
other way around, so there is no import cycle.
"""

from typing import Dict, List, Optional

# 1. The four stored levels -------------------------------------------------

GENERAL_WORKER = "general worker"
SEMI_SKILLED_WORKER = "semi skilled worker"
SKILLED_WORKER = "skilled worker"
FOREMAN = "foreman"

TRADE_LEVELS: List[str] = [
    GENERAL_WORKER,
    SEMI_SKILLED_WORKER,
    SKILLED_WORKER,
    FOREMAN,
]
TRADE_LEVELS_SET = frozenset(TRADE_LEVELS)

# Display labels for UI / PDF / Excel export. The stored value stays lowercase.
TRADE_LEVEL_LABELS: Dict[str, str] = {
    GENERAL_WORKER: "General Worker",
    SEMI_SKILLED_WORKER: "Semi Skilled Worker",
    SKILLED_WORKER: "Skilled Worker",
    FOREMAN: "Foreman",
}

# Seniority rank. Higher ranks can cover a lower-ranked task requirement;
# the reverse is not allowed (a general worker is not a substitute for a
# skilled worker).
TRADE_LEVEL_RANK: Dict[str, int] = {
    GENERAL_WORKER: 1,
    SEMI_SKILLED_WORKER: 2,
    SKILLED_WORKER: 3,
    FOREMAN: 4,
}

# Estimated standard duration (workdays) per level. Used by the progress
# estimator when the required trade is only known at level granularity.
TRADE_LEVEL_DURATION: Dict[str, float] = {
    GENERAL_WORKER: 1.0,
    SEMI_SKILLED_WORKER: 1.5,
    SKILLED_WORKER: 2.0,
    FOREMAN: 0.5,
}

# Default section / instruction template key when a worker has no trade set.
DEFAULT_LEVEL = GENERAL_WORKER


# 2. Legacy fine-grained trades -> level ------------------------------------
#
# Mapping rationale (keep it explicit, this drives the historical data
# migration and is reviewed by the site managers):
#   * craft trades that require certification -> skilled worker
#   * helper / finishing trades that are learned on the job -> semi skilled
#   * general labour -> general worker
#   * supervision -> foreman (the only level that may direct other workers)
MIGRATION_MAP: Dict[str, str] = {
    "carpenter": SKILLED_WORKER,
    "electrical": SKILLED_WORKER,
    # "electrician" showed up in production data as a free-text variant of the
    # electrical trade (2 workers), so it is mapped here rather than rejected.
    "electrician": SKILLED_WORKER,
    "plumbing": SKILLED_WORKER,
    "masonry": SKILLED_WORKER,
    "painting": SKILLED_WORKER,
    "welding": SKILLED_WORKER,
    # "welder" is the person, "welding" the trade; both map to the same level.
    "welder": SKILLED_WORKER,
    "hvac": SKILLED_WORKER,
    "roofing": SKILLED_WORKER,
    "tiling": SKILLED_WORKER,
    "glazing": SKILLED_WORKER,
    "flooring": SKILLED_WORKER,
    "equipment": SKILLED_WORKER,
    # Scaffolding is erected under supervision and does not require a trade
    # certificate in Malaysian practice, so it sits one level below the crafts.
    "scaffolder": SEMI_SKILLED_WORKER,
    "drywall": SEMI_SKILLED_WORKER,
    "insulation": SEMI_SKILLED_WORKER,
    "laborer": GENERAL_WORKER,
    "supervision": FOREMAN,
}

# Values seen in production that are not trades at all (typed digits, typos)
# and therefore have no honest mapping. The migration generator lists them for
# manual review instead of silently forcing them into a level.
MANUAL_REVIEW_VALUES: List[str] = [
    "426788",
]


# 3. Accepted spellings per level ------------------------------------------
#
# Free-text trade input still arrives from older clients (the register page used
# to send "Carpenter", the supervisor "add worker" sheet sent raw text). Those
# values are normalised instead of rejected, so an app build that predates the
# four-level switch keeps working while the database only ever sees a level.
LEVEL_ALIASES: Dict[str, List[str]] = {
    GENERAL_WORKER: [
        "general", "general worker", "general labourer", "general laborer",
        "general worker (unskilled)", "unskilled", "unskilled worker",
        "labourer", "laborer", "helper", "site helper", "pekerja am",
        "buruh", "pekerja kasar", "pembantu", "普工", "杂工", "普通工人",
    ],
    SEMI_SKILLED_WORKER: [
        "semi skilled", "semi-skilled", "semi skilled worker",
        "semiskilled", "semi-skilled worker", "semi skilled labourer",
        "pekerja separa mahir", "separa mahir", "半熟练工", "半熟练工人",
    ],
    SKILLED_WORKER: [
        "skilled", "skilled worker", "skilled labourer", "skilled laborer",
        "tradesman", "craftsman", "certified worker", "pekerja mahir",
        "mahir", "tukang", "熟练工", "熟练工人", "技工",
    ],
    FOREMAN: [
        "foreman", "site foreman", "general foreman", "mandor",
        "ketua pekerja", "工头", "领班", "班组长",
    ],
}


# 3b. Legacy fine-grained trades (the abolished 16-group taxonomy) -----------
# The 16 groups are no longer accepted on write, but every alias that used to
# identify them must keep resolving on read: historical rows hold values such
# as "Carpenter" / "tukang kayu" / "水管", and the AI keyword matcher still emits
# the 16 group names. Each group is collapsed to one of the four levels through
# ``MIGRATION_MAP`` below, so this table is the only place the old vocabulary
# survives. ``ai_service.TRADE_ALIASES`` re-uses this dict instead of keeping a
# second copy.
LEGACY_FINE_ALIASES: Dict[str, List[str]] = {
    "carpenter": ["carpenter", "carpentry", "cabinet", "joinery", "timber", "wood",
                  "formwork", "framework", "木工", "橱柜", "木",
                  "tukang kayu", "pertukangan", "kabinet", "bingkai"],
    "electrical": ["electrical", "electric", "electrician", "wiring", "cable",
                   "lighting", "db panel", "电工", "电线", "电缆", "照明",
                   "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel"],
    "plumbing": ["plumbing", "plumber", "pipe", "water", "sanitary", "chiller",
                 "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang"],
    "masonry": ["masonry", "mason", "brick", "block", "wall", "concrete",
                "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit", "simen",
                "bancuh", "asas"],
    "painting": ["painting", "paint", "painter", "painters", "plaster", "plasterer",
                 "emulsion", "primer", "varnish", "stain", "lacquer", "sealer",
                 "topcoat", "polyurethane", "gloss", "油漆", "粉刷", "涂料",
                 "mengecat", "pengecat", "cat dinding", "wallpaper", "wallpapering",
                 "decorator"],
    "welding": ["welding", "weld", "welder", "welders", "steel", "metal", "ironworker",
                "焊接", "钢结构", "金属", "kimpal", "pengimpal", "keluli", "besi",
                "jurukimpal"],
    "hvac": ["hvac", "air balance", "ahu", "ventilation", "air conditioning",
             "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan"],
    "roofing": ["roofing", "roofer", "roof", "shingle",
                "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tiling", "tile", "tiler", "terrazzo", "ceramic", "tilesetter",
               "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "drywaller", "sheetrock", "gypsum", "taper",
                "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazing", "glazier", "glass", "window",
                "玻璃", "门窗", "kaca", "tingkap"],
    "flooring": ["flooring", "floor", "floorer", "linoleum", "carpet",
                 "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["equipment", "operator", "excavator", "bulldozer", "backhoe",
                  "crane", "grader", "shovel", "dozer", "pile",
                  "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft",
                "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu",
                "perancah", "perobohan"],
    "insulation": ["insulation", "insulator", "insulate", "保温", "隔热",
                   "penebat", "penebat haba", "busa", "gentian kaca"],
    "supervision": ["superintendent", "supervisor", "foreman", "coordinator",
                    "manager", "inspection", "inspector", "监工", "巡查",
                    "penyelia", "penyelia tapak", "pemeriksa", "pemantauan", "mandor"],
}


# 4. Normalisation helpers --------------------------------------------------

def _clean(value: Optional[str]) -> str:
    """Lowercase and squeeze whitespace / separators so "Semi-Skilled  Worker"
    and "semi skilled worker" compare equal."""
    if not value:
        return ""
    text = str(value).strip().lower()
    for ch in ("-", "_", "/", "\\", ".", ","):
        text = text.replace(ch, " ")
    return " ".join(text.split())


_ALIAS_INDEX: Dict[str, str] = {}
for _level, _aliases in LEVEL_ALIASES.items():
    _ALIAS_INDEX[_level] = _level
    for _alias in _aliases:
        _ALIAS_INDEX[_clean(_alias)] = _level

# Every fine-grained alias collapses to its level through MIGRATION_MAP, so
# "Carpenter", "tukang kayu" and "木工" keep resolving even though the 16 groups
# are no longer writable. Level keywords are applied last and win on overlap.
_FINE_ALIAS_INDEX: Dict[str, str] = {}
for _fine, _aliases in LEGACY_FINE_ALIASES.items():
    _fine_level = MIGRATION_MAP.get(_fine)
    if not _fine_level:
        continue
    _FINE_ALIAS_INDEX[_clean(_fine)] = _fine_level
    for _alias in _aliases:
        _FINE_ALIAS_INDEX.setdefault(_clean(_alias), _fine_level)
_FINE_ALIAS_INDEX.update(_ALIAS_INDEX)

# Bahasa Melayu trade nouns that may precede the craft word ("tukang kayu" =
# carpenter, "pemasang paip" = plumber). They carry no level on their own.
_TRADE_PREFIXES = ("pemasang ", "tukang ", "pengendali ", "jurukimpal ", "pekerja ")


def _lookup(text: str, allow_prefix: bool = True) -> Optional[str]:
    if text in _FINE_ALIAS_INDEX:
        return _FINE_ALIAS_INDEX[text]
    if text in MIGRATION_MAP:
        return MIGRATION_MAP[text]
    if allow_prefix:
        for prefix in _TRADE_PREFIXES:
            if text.startswith(prefix):
                stripped = text[len(prefix):].strip()
                if stripped:
                    found = _lookup(stripped, allow_prefix=False)
                    if found:
                        return found
    return None


def trade_level(value: Optional[str]) -> Optional[str]:
    """Return the four-level value for *value*, or None when it is unknown.

    Accepts, in order: an exact level, a level alias, a legacy fine-grained
    trade (English / Chinese / Bahasa Melayu), or a legacy value carrying a
    Bahasa Melayu installer/operator prefix ("tukang ", "pemasang ",
    "pengendali ", "jurukimpal ", "pekerja ").
    """
    text = _clean(value)
    if not text:
        return None
    return _lookup(text)


def is_trade_level(value: Optional[str]) -> bool:
    """True only for an exact four-level value (no aliasing, no legacy trade)."""
    return _clean(value) in TRADE_LEVELS_SET


def normalise_trade(value: Optional[str]) -> Optional[str]:
    """Canonical value used by every write path.

    ``None`` / empty stays ``None`` (trade is optional on the worker record);
    anything else must resolve to one of the four levels, otherwise ValueError
    is raised so the API rejects the request with a readable message instead of
    silently storing a value the AI matcher cannot use.
    """
    if value is None:
        return None
    if isinstance(value, str) and not value.strip():
        return None
    level = trade_level(value)
    if level is None:
        raise ValueError(
            "trade must be one of: " + ", ".join(TRADE_LEVELS)
        )
    return level


def level_rank(value: Optional[str]) -> int:
    """Seniority rank of a trade value (0 when unknown)."""
    level = trade_level(value)
    return TRADE_LEVEL_RANK.get(level, 0) if level else 0


def level_label(value: Optional[str]) -> str:
    """Human-readable label of a trade value, falling back to the raw text."""
    level = trade_level(value)
    if level:
        return TRADE_LEVEL_LABELS[level]
    return (value or "").strip()


def level_duration(value: Optional[str], default: float = 1.5) -> float:
    level = trade_level(value)
    return TRADE_LEVEL_DURATION.get(level, default) if level else default
