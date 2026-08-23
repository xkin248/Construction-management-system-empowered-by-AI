import os
import json
import re
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
from app.models import Worker, Task, TaskWorker, AttendanceLog, Project, DailyReport, Issue, PredictionHistory
from app.worker_pool import get_project_workers

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")

if GEMINI_AVAILABLE and GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)


SYSTEM_PROMPT = """你是一个专业的建筑工程管理助手，名为 BuildSmart AI。你的职责是帮助施工管理人员高效地管理工程项目。

你的专业领域包括：
1. 施工任务分配与人员调度
2. 安全管理与风险评估
3. 进度跟踪与报告
4. 材料与设备管理建议
5. 成本控制建议

请用简洁、专业、实用的语言回答问题。如果涉及具体数据，请基于提供的上下文信息进行分析。"""


# Trade synonyms: canonical group -> keywords matched against worker trade strings.
# Used ONLY for mapping a worker's stored trade label to a canonical group.
# (Task text detection uses TASK_KEYWORDS below — narrower, avoids false positives
# like "wall"/"water"/"floor" matching the wrong trade.)
TRADE_ALIASES: Dict[str, List[str]] = {
    "carpenter": ["carpenter", "carpentry", "cabinet", "joinery", "timber", "wood", "formwork", "framework", "木工", "橱柜", "木", "tukang kayu", "pertukangan", "kabinet", "bingkai"],
    "electrical": ["electrical", "electric", "electrician", "wiring", "cable", "lighting", "db panel", "电工", "电线", "电缆", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel"],
    "plumbing": ["plumbing", "plumber", "pipe", "water", "sanitary", "chiller", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang"],
    "masonry": ["masonry", "mason", "brick", "block", "wall", "concrete", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit"],
    "painting": ["painting", "paint", "plaster", "emulsion", "primer", "varnish", "stain", "lacquer", "sealer", "topcoat", "polyurethane", "gloss", "油漆", "粉刷", "涂料", "mengecat", "pengecat", "cat dinding"],
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
    "carpenter": ["carpenter", "carpentry", "cabinet", "joinery", "timber", "formwork", "framework", "hinge", "door lock", "wooden", "plywood", "木工", "橱柜", "tukang kayu", "pertukangan", "kabinet", "bingkai"],
    "electrical": ["electrical", "electrician", "wiring", "cable", "lighting", "db panel", "cctv", "camera", "network cable", "socket", "breaker", "conduit", "switch", "ceiling fan", "电工", "电线", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel"],
    "plumbing": ["plumbing", "plumber", "pipe", "water pipe", "sanitary", "chiller", "flush", "valve", "mixer", "tap", "shower", "faucet", "toilet", "drain", "sewer", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang"],
    "masonry": ["masonry", "mason", "brick", "block", "concrete", "rebar", "stucco", "plaster", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit"],
    "painting": ["painting", "paint", "emulsion", "primer", "coat", "varnish", "油漆", "粉刷", "涂料", "mengecat", "pengecat"],
    "welding": ["welding", "weld", "steel", "metal", "ironworker", "railing", "column", "erect", "焊接", "钢结构", "kimpal", "pengimpal", "keluli"],
    "hvac": ["hvac", "air conditioning", "aircon", "cooling", "ventilation", "ahu", "duct", "refrigerant", "vent", "air vent", "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan"],
    "roofing": ["roofing", "roofer", "roof", "shingle", "membrane", "waterproof", "bitumen", "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tiling", "tile", "tiler", "terrazzo", "ceramic", "grout", "backsplash", "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "sheetrock", "gypsum", "taper", "partition", "ceiling board", "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazing", "glazier", "glass", "window", "玻璃", "门窗", "kaca", "tingkap"],
    "flooring": ["flooring", "floor", "linoleum", "carpet", "vinyl", "laminate", "epoxy", "wooden floor", "grind", "grinding", "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["equipment", "operator", "excavator", "bulldozer", "backhoe", "crane", "grader", "shovel", "dozer", "pile", "forklift", "concrete pump", "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft", "clean", "debris", "scaffold", "scaffolding", "barrier", "demolish", "demolition", "carry", "haul", "unload", "jackhammer", "signage", "sign", "breaking", "chipping", "rubble", "sweep", "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu", "perancah", "perobohan"],
    "insulation": ["insulation", "insulator", "insulate", "rockwool", "fiberglass", "foam", "cavity", "保温", "隔热", "penebat", "penebat haba", "busa", "gentian kaca"],
    "supervision": ["superintendent", "supervisor", "foreman", "coordinator", "manager", "inspection", "inspector", "inspect", "fire extinguisher", "compliance", "sampling", "监工", "巡查", "penyelia", "penyelia tapak", "pemeriksa", "pemantauan", "mandor"],
}

# Seed keywords used by the dataset-trained semantic matcher (mirror of build_trade_matcher.py).
SEED_KEYWORDS: Dict[str, List[str]] = {
    "carpenter": ["carpenter", "cabinet", "joinery", "timber", "wood", "wooden", "plywood", "formwork", "framework", "carpentry", "hinge", "door lock", "partition wall", "sheathing", "stud", "木工", "橱柜", "tukang kayu", "pertukangan", "kabinet", "bingkai"],
    "electrical": ["electrician", "electrical", "electric", "wiring", "cable", "lighting", "db panel", "cctv", "camera", "network cable", "socket", "breaker", "conduit", "switch", "ceiling fan", "电工", "电线", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel"],
    "plumbing": ["plumber", "plumbing", "pipe", "water pipe", "sanitary", "chiller", "flush", "valve", "mixer", "tap", "shower", "faucet", "toilet", "drain", "sewer", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang"],
    "masonry": ["mason", "masonry", "brick", "block", "concrete", "rebar", "stucco", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit"],
    "painting": ["painter", "painting", "paint", "emulsion", "primer", "coat", "varnish", "stain", "lacquer", "sealer", "topcoat", "polyurethane", "stair rail", "handrail", "furniture", "trim", "油漆", "粉刷", "涂料", "mengecat", "pengecat", "cat dinding"],
    "welding": ["welder", "welding", "weld", "steel", "metal", "ironworker", "railing", "column", "erect", "焊接", "钢结构", "kimpal", "pengimpal", "keluli"],
    "hvac": ["hvac", "air conditioning", "aircon", "cooling", "ventilation", "ahu", "duct", "refrigerant", "vent", "air vent", "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan"],
    "roofing": ["roofer", "roofing", "roof", "shingle", "membrane", "waterproof", "bitumen", "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tile", "tiler", "tiling", "terrazzo", "ceramic", "grout", "backsplash", "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "sheetrock", "gypsum", "taper", "partition", "ceiling board", "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazier", "glass", "window", "glazing", "玻璃", "门窗安装", "kaca", "tingkap"],
    "flooring": ["floor", "flooring", "linoleum", "carpet", "vinyl", "laminate", "epoxy", "wooden floor", "grind", "grinding", "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["operator", "excavator", "bulldozer", "backhoe", "crane", "grader", "shovel", "dozer", "pile", "forklift", "concrete pump", "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft", "clean", "debris", "scaffold", "scaffolding", "barrier", "demolish", "demolition", "carry", "haul", "unload", "jackhammer", "signage", "sign", "breaking", "chipping", "rubble", "sweep", "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu", "perancah", "perobohan"],
    "insulation": ["insulation", "insulator", "insulate", "rockwool", "fiberglass", "foam", "cavity", "保温", "隔热", "penebat", "penebat haba", "busa", "gentian kaca"],
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


def _clean_text(text: str) -> str:
    t = re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff ]+", " ", str(text).lower())
    return re.sub(r"\s+", " ", t).strip()


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


def _resolve_detected_trades(task_text: str, detected: set, semantic_scores: Dict[str, float]) -> set:
    """Resolve ambiguous multi-hit keyword detection with the semantic matcher.

    When several trades match task keywords (e.g. "tile bathroom floor with
    ceramic" hits both tiling and flooring), prefer the trade with the highest
    semantic score so we do not fall back to alphabetical order. If the semantic
    matcher is unavailable or gives no strong preference, keep all hits.
    """
    if len(detected) <= 1 or not semantic_scores:
        return detected
    best = max(detected, key=lambda g: semantic_scores.get(g, 0.0))
    best_score = semantic_scores.get(best, 0.0)
    runner_up = sorted((semantic_scores.get(g, 0.0) for g in detected), reverse=True)
    runner_up = runner_up[1] if len(runner_up) > 1 else 0.0
    if best_score >= 0.55 and (best_score - runner_up) >= 0.10:
        return {best}
    return detected


def _worker_trade_group(trade: str) -> Optional[str]:
    """Map a worker trade string to its canonical group, if any."""
    if not trade:
        return None
    t = trade.lower().strip()
    for group, keywords in TRADE_ALIASES.items():
        if t in keywords or t == group:
            return group
    return None


def get_gemini_model():
    if not GEMINI_AVAILABLE or not GEMINI_API_KEY:
        return None
    try:
        return genai.GenerativeModel(GEMINI_MODEL)
    except Exception:
        return None


def analyze_task(
    db,
    task_info: Dict[str, Any],
    project_id: int,
    same_project_only: bool = False,
) -> Dict[str, Any]:
    if same_project_only:
        workers = get_project_workers(db, project_id)
    else:
        workers = db.query(Worker).all()
    project = db.query(Project).filter(Project.project_id == project_id).first()

    task_name = task_info.get("task_name", "")
    description = task_info.get("description", "")

    task_text = f"{task_name} {description}".lower()

    # Trade is no longer accepted from the task form: the required role is
    # decided purely from title + description via keyword & semantic matching.
    semantic_scores = _semantic_trade_scores(task_text)
    # 1. Keyword detection first (TASK_KEYWORDS substring match — reliable, no false positives).
    detected_trades = _detect_trade_groups(task_text)
    # 1b. Ambiguous multi-hit: resolve with semantic scores when possible.
    detected_trades = _resolve_detected_trades(task_text, detected_trades, semantic_scores)
    # 2. Semantic detection as a supplement — only when keywords found nothing AND
    #    the semantic model has a clear winner (score >= 0.6 & gap >= 0.15 from runner-up).
    #    This prevents the old bug where "electric" scored 0.35 for ALL trades and
    #    max() picked the alphabetically-first 'carpenter', mis-assigning electrical tasks.
    if not detected_trades:
        if semantic_scores:
            best_trade, best_score = max(semantic_scores.items(), key=lambda x: x[1])
            sorted_scores = sorted(semantic_scores.values(), reverse=True)
            gap = best_score - (sorted_scores[1] if len(sorted_scores) > 1 else 0.0)
            if best_score >= 0.6 and gap >= 0.15:
                detected_trades = {best_trade}
    else:
        semantic_scores = {canonical: 1.0 for canonical in detected_trades}

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
            reasons.append("工种语义匹配：{}（匹配度 {:.0%}）".format(worker.trade, strength))
        elif wgroup:
            score -= 15
            reasons.append("工种不符任务需求：{}".format(worker.trade))
        elif worker.trade:
            score += 5
            reasons.append("可用工种：{}".format(worker.trade))

        attendance_today = db.query(AttendanceLog).filter(
            AttendanceLog.worker_id == worker.worker_id,
            AttendanceLog.check_in_time >= date.today()
        ).first()

        if attendance_today and attendance_today.status in ("checked_in", "checked_out"):
            score += 15
            reasons.append("今日已到岗")

        if worker.has_safety_training:
            score += 3
            reasons.append("已接受安全培训")
        if worker.is_safety_officer:
            score += 2
            reasons.append("是安全员")

        suggested_workers.append({
            "worker_id": worker.worker_id,
            "name": worker.name,
            "trade": worker.trade or "通用",
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
        duration_estimate = "根据任务类型（{}）的行业标准工时，预计需要 {:.0f}-{:.0f} 天".format(
            "/".join(sorted(detected_trades)), max(1, est_days - 0.5), est_days + 1
        )
    else:
        duration_estimate = "根据任务复杂度，预计需要 1-3 天"

    return {
        "suggested_workers": suggested_workers[:5],
        "estimated_duration": duration_estimate,
        "priority_suggestion": priority,
        "safety_notes": "请确保施工人员佩戴必要的安全防护装备，并遵守现场安全规定。",
        "matched_trades": sorted(detected_trades),
        "trade_source": "semantic",
        "semantic_used": bool(semantic_scores),
        "notice": "" if matched_any or not detected_trades else "项目中暂无匹配工种（{}）的工人，以下为其他工种候选".format(
            "/".join(sorted(detected_trades))
        ),
    }


def generate_daily_report(db, project_id: int, report_date: date) -> str:
    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return "项目不存在"

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

    report = f"""# {project.project_name} - {report_date.strftime('%Y年%m月%d日')} 工作日报

## 人员出勤
- 总人数：{len(workers)} 人
- 今日出勤：{present_count} 人
- 缺勤：{len(workers) - present_count} 人

## 任务进度
- 已完成：{completed_tasks} 项
- 进行中：{in_progress_tasks} 项
- 待开始：{pending_tasks} 项

## 待处理问题
- 开放问题：{len(issues)} 个
"""

    if issues:
        report += "\n问题列表：\n"
        for issue in issues:
            report += f"- {issue.title}\n"

    report += "\n注：此报告由 AI 自动生成，请根据实际情况进行调整和补充。"

    return report


def analyze_safety_risk(description: str) -> str:
    model = get_gemini_model()
    if not model:
        return "AI 服务不可用，无法进行安全分析。"

    prompt = f"""请分析以下施工安全事件描述，评估风险等级并提供建议：

事件描述：{description}

请按以下格式回答：
风险等级：[高/中/低]
风险分析：[简要分析]
处理建议：[建议措施]
"""

    try:
        response = model.generate_content(prompt)
        return response.text
    except Exception:
        return "安全分析暂时不可用，请人工评估。"


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


def recommend_workers_for_task(db, task_info: Dict[str, Any], project_id: int, top_k: int = 5, same_project_only: bool = False) -> Dict[str, Any]:
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
                "请基于以下JSON输入，推荐最适合执行该任务的工人(最多{}个)。只输出JSON，不要输出多余文字。\n\n{}".format(
                    top_k, json.dumps(prompt, ensure_ascii=False)
                )
            )
            parsed = _extract_json(getattr(resp, "text", "") or "")
            base_for_trades = analyze_task(db, task_info, project_id, same_project_only=same_project_only)
            if isinstance(parsed, dict) and isinstance(parsed.get("suggested_workers"), list):
                out = parsed
                out["suggested_workers"] = out["suggested_workers"][:top_k]
                out["semantic_used"] = True
                out["matched_trades"] = base_for_trades.get("matched_trades") or []
                return out
            if isinstance(parsed, list):
                return {"suggested_workers": parsed[:top_k], "semantic_used": True,
                        "matched_trades": base_for_trades.get("matched_trades") or []}
        except Exception:
            pass

    base = analyze_task(db, task_info, project_id, same_project_only=same_project_only)
    base["suggested_workers"] = (base.get("suggested_workers") or [])[:top_k]
    return base


def auto_assign_tasks(
    db,
    project_id: int,
    task_ids: Optional[List[int]] = None,
    dry_run: bool = True,
    top_k: int = 3
) -> Dict[str, Any]:
    q = db.query(Task).filter(Task.project_id == project_id)
    if task_ids:
        q = q.filter(Task.task_id.in_(task_ids))
    q = q.filter(Task.status != "completed")
    tasks = q.order_by(Task.due_date.is_(None), Task.due_date.asc(), Task.task_id.asc()).all()

    # Auto-assign matches against the whole worker pool (same as the analyze
    # screen default) so tasks in projects without bound workers can still get
    # matched. The trade matching itself guarantees the right trade wins.
    workers = db.query(Worker).all()
    worker_ids = {w.worker_id for w in workers}

    assignments = []
    for t in tasks:
        task_info = {"task_name": t.task_name, "description": t.description or ""}
        rec = recommend_workers_for_task(db, task_info, project_id, top_k=max(1, top_k), same_project_only=False)
        suggested = rec.get("suggested_workers") or []
        matched_trades = set(rec.get("matched_trades") or [])

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
        })

    if not dry_run:
        db.commit()

    return {
        "project_id": project_id,
        "dry_run": dry_run,
        "assignments": assignments
    }


# ──────────────────────────────────────────────────────────────
#  Real-time AI Progress Dashboard
# ──────────────────────────────────────────────────────────────

def compute_project_progress(db, project_id: int) -> Dict[str, Any]:
    """
    Computes a real-time AI-powered project health score (0-100) with insights.
    Factors: task completion, attendance rate, overdue tasks, worker workload balance.
    Falls back gracefully if Gemini is unavailable.
    """
    today = date.today()
    since_30 = datetime.combine(today - timedelta(days=30), datetime.min.time())

    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return {"error": "Project not found"}

    # ── Task metrics ──
    all_tasks = db.query(Task).filter(Task.project_id == project_id).all()
    total_tasks = len(all_tasks)
    completed = sum(1 for t in all_tasks if t.status == "completed")
    in_progress = sum(1 for t in all_tasks if t.status == "in_progress")
    pending = sum(1 for t in all_tasks if t.status == "pending")
    overdue = sum(1 for t in all_tasks if t.due_date and t.due_date < today and t.status != "completed")
    unassigned = sum(1 for t in all_tasks if not t.assigned_worker_id and t.status != "completed")
    task_completion_pct = round(completed / total_tasks * 100) if total_tasks > 0 else 0

    # ── Attendance metrics ──
    workers = get_project_workers(db, project_id)
    total_workers = len(workers)
    today_att = db.query(AttendanceLog).filter(
        AttendanceLog.project_id == project_id,
        AttendanceLog.check_in_time >= datetime.combine(today, datetime.min.time()),
        AttendanceLog.status.in_(("checked_in", "checked_out"))
    ).count()
    attendance_pct = round(today_att / total_workers * 100) if total_workers > 0 else 0

    # ── Per-task details ──
    task_details = []
    for t in sorted(all_tasks, key=lambda x: (x.status != "in_progress", x.status != "pending", x.due_date is None)):
        is_overdue = bool(t.due_date and t.due_date < today and t.status != "completed")
        task_details.append({
            "task_id": t.task_id,
            "task_name": t.task_name,
            "status": t.status or "pending",
            "priority": t.priority or "medium",
            "progress": float(t.progress or 0),
            "due_date": t.due_date.isoformat() if t.due_date else None,
            "is_overdue": is_overdue,
            "assigned_worker": t.assigned_worker.name if t.assigned_worker else None,
        })

    # ── Worker performance ──
    worker_metrics = []
    for w in workers:
        tasks_assigned = [t for t in all_tasks if t.assigned_worker_id == w.worker_id]
        completed_tasks = sum(1 for t in tasks_assigned if t.status == "completed")
        active_tasks = sum(1 for t in tasks_assigned if t.status in ("in_progress", "pending"))
        att_30 = db.query(AttendanceLog).filter(
            AttendanceLog.worker_id == w.worker_id,
            AttendanceLog.check_in_time >= since_30,
            AttendanceLog.status.in_(("checked_in", "checked_out"))
        ).count()
        worker_metrics.append({
            "worker_id": w.worker_id,
            "name": w.name,
            "trade": w.trade or "General",
            "completed_tasks": completed_tasks,
            "active_tasks": active_tasks,
            "attendance_days_30": att_30,
        })
    worker_metrics.sort(key=lambda x: x["completed_tasks"], reverse=True)

    # ── AI scoring & insights ──
    model = get_gemini_model()
    ai_insights = ""
    recommendations = []
    risk_level = "low"
    health_score = 0

    # Rule-based base score (used as fallback and AI anchor)
    base_score = 0
    base_score += min(40, task_completion_pct * 0.4)   # up to 40pts
    base_score += min(30, attendance_pct * 0.3)         # up to 30pts
    overdue_penalty = min(20, overdue * 5)
    base_score += max(0, 20 - overdue_penalty)           # up to 20pts
    assigned_pct = ((total_tasks - unassigned) / total_tasks * 100) if total_tasks > 0 else 100
    base_score += min(10, assigned_pct * 0.1)            # up to 10pts
    base_score = round(min(100, base_score))

    if model:
        prompt_data = {
            "project": project.project_name,
            "total_tasks": total_tasks,
            "completed": completed,
            "in_progress": in_progress,
            "pending": pending,
            "overdue": overdue,
            "unassigned": unassigned,
            "task_completion_pct": task_completion_pct,
            "total_workers": total_workers,
            "workers_on_site_today": today_att,
            "attendance_pct": attendance_pct,
            "base_score": base_score,
        }
        prompt = f"""You are a construction project analyst. Analyse this project data and respond ONLY with valid JSON, no markdown fences.

Input:
{json.dumps(prompt_data, ensure_ascii=False)}

Output format (strict JSON):
{{
  "health_score": <integer 0-100, refine from base_score>,
  "risk_level": "<low|medium|high|critical>",
  "ai_insights": "<2-3 sentence summary of project health in English>",
  "recommendations": ["<action 1>", "<action 2>", "<action 3>"]
}}"""
        try:
            resp = model.generate_content(prompt)
            parsed = _extract_json(getattr(resp, "text", "") or "")
            if isinstance(parsed, dict):
                health_score = int(parsed.get("health_score", base_score))
                risk_level = str(parsed.get("risk_level", "medium")).lower()
                ai_insights = str(parsed.get("ai_insights", ""))
                recommendations = list(parsed.get("recommendations", []))
        except Exception:
            pass

    if not health_score:
        health_score = base_score
    if not ai_insights:
        if overdue > 0:
            ai_insights = f"Project has {overdue} overdue task(s). Task completion is at {task_completion_pct}% with {today_att}/{total_workers} workers on site today."
        else:
            ai_insights = f"Project is progressing well. Task completion at {task_completion_pct}%, attendance {attendance_pct}%."
    if not recommendations:
        if overdue > 0:
            recommendations.append(f"Address {overdue} overdue task(s) immediately")
        if unassigned > 0:
            recommendations.append(f"Use AI Auto-Assign to fill {unassigned} unassigned task(s)")
        if attendance_pct < 70:
            recommendations.append("Low attendance today — check worker check-in status")

    if not risk_level:
        if health_score >= 80:
            risk_level = "low"
        elif health_score >= 60:
            risk_level = "medium"
        elif health_score >= 40:
            risk_level = "high"
        else:
            risk_level = "critical"

    return {
        "project_id": project_id,
        "project_name": project.project_name,
        "generated_at": datetime.utcnow().isoformat(),
        "health_score": health_score,
        "risk_level": risk_level,
        "ai_insights": ai_insights,
        "recommendations": recommendations,
        "metrics": {
            "task_completion_pct": task_completion_pct,
            "attendance_pct": attendance_pct,
            "total_tasks": total_tasks,
            "completed": completed,
            "in_progress": in_progress,
            "pending": pending,
            "overdue": overdue,
            "unassigned": unassigned,
            "total_workers": total_workers,
            "on_site_today": today_att,
        },
        "tasks": task_details[:20],      # top 20
        "worker_metrics": worker_metrics[:10],  # top 10
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
