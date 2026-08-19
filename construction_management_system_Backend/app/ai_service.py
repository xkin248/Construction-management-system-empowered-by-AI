import os
import json
import re
from typing import List, Dict, Any, Optional, Tuple
from datetime import date, datetime, timedelta
from dotenv import load_dotenv

try:
    import google.generativeai as genai
    GEMINI_AVAILABLE = True
except ImportError:
    GEMINI_AVAILABLE = False

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


def get_gemini_model():
    if not GEMINI_AVAILABLE or not GEMINI_API_KEY:
        return None
    try:
        return genai.GenerativeModel(GEMINI_MODEL)
    except Exception:
        return None


def chat_with_ai(messages: List[Dict[str, str]]) -> Tuple[str, int]:
    model = get_gemini_model()
    if not model:
        return "抱歉，AI 服务当前不可用。请检查 API 配置。", 0

    try:
        conversation = []
        conversation.append({"role": "user", "parts": [SYSTEM_PROMPT]})
        conversation.append({"role": "model", "parts": ["明白了，我会作为 BuildSmart AI 专业助手帮助你。"]})

        for msg in messages:
            role = "user" if msg["role"] == "user" else "model"
            conversation.append({"role": role, "parts": [msg["content"]]})

        response = model.generate_content(conversation)
        return response.text, len(response.text) // 4
    except Exception as e:
        return f"抱歉，发生了错误：{str(e)}", 0


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

    suggested_workers = []
    for worker in workers:
        score = 50
        reasons = []

        if worker.trade:
            trade_lower = worker.trade.lower()
            task_text = f"{task_name} {description}".lower()
            if trade_lower in task_text:
                score += 30
                reasons.append(f"工种匹配：{worker.trade}")
            else:
                score += 10
                reasons.append(f"可用工种：{worker.trade}")

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
    task_text = f"{task_name} {description}".lower()
    if any(keyword in task_text for keyword in ["安全", "紧急", "critical", "urgent", "foundation", "结构"]):
        priority = "high"
    elif any(keyword in task_text for keyword in ["清洁", "整理", "cleaning"]):
        priority = "low"

    return {
        "suggested_workers": suggested_workers[:5],
        "estimated_duration": "根据任务复杂度，预计需要 1-3 天",
        "priority_suggestion": priority,
        "safety_notes": "请确保施工人员佩戴必要的安全防护装备，并遵守现场安全规定。"
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


def recommend_workers_for_task(db, task_info: Dict[str, Any], project_id: int, top_k: int = 5) -> Dict[str, Any]:
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
            if isinstance(parsed, dict) and isinstance(parsed.get("suggested_workers"), list):
                out = parsed
                out["suggested_workers"] = out["suggested_workers"][:top_k]
                return out
            if isinstance(parsed, list):
                return {"suggested_workers": parsed[:top_k]}
        except Exception:
            pass

    base = analyze_task(db, task_info, project_id)
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

    workers = db.query(Worker).all()
    worker_ids = {w.worker_id for w in workers}

    assignments = []
    for t in tasks:
        # Skip tasks that already have a full assignment (legacy single-worker
        # rows with only assigned_worker_id are still processed to backfill links).
        if t.assigned_worker_id and t.task_workers:
            continue
        task_info = {"task_name": t.task_name, "description": t.description or ""}
        rec = recommend_workers_for_task(db, task_info, project_id, top_k=max(1, top_k))
        suggested = rec.get("suggested_workers") or []

        # Pick up to top_k valid workers, ordered by match score (multi-worker).
        chosen_ids: List[int] = []
        for item in suggested:
            wid = item.get("worker_id") if isinstance(item, dict) else None
            if wid is not None and int(wid) in worker_ids and int(wid) not in chosen_ids:
                chosen_ids.append(int(wid))
            if len(chosen_ids) >= max(1, top_k):
                break

        if not dry_run and chosen_ids:
            t.task_workers = [TaskWorker(worker_id=wid) for wid in chosen_ids]
            t.assigned_worker_id = chosen_ids[0]
            db.add(t)

        assignments.append({
            "task_id": t.task_id,
            "task_name": t.task_name,
            "assigned_worker_id": chosen_ids[0] if chosen_ids else None,
            "assigned_worker_ids": chosen_ids,
            "suggested_workers": suggested,
            "ai_used": bool(get_gemini_model()),
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
