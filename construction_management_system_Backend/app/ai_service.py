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
from app.models import Worker, Task, AttendanceLog, Project, DailyReport, Issue

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


def analyze_task(db, task_info: Dict[str, Any], project_id: int) -> Dict[str, Any]:
    workers = db.query(Worker).filter(Worker.project_id == project_id).all()
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

    workers = db.query(Worker).filter(Worker.project_id == project_id).all()
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
    workers = db.query(Worker).filter(Worker.project_id == project_id).all()
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

    workers = db.query(Worker).filter(Worker.project_id == project_id).all()
    worker_ids = {w.worker_id for w in workers}

    assignments = []
    for t in tasks:
        if t.assigned_worker_id:
            continue
        task_info = {"task_name": t.task_name, "description": t.description or ""}
        rec = recommend_workers_for_task(db, task_info, project_id, top_k=max(1, top_k))
        suggested = rec.get("suggested_workers") or []
        chosen = suggested[0] if suggested else None
        chosen_worker_id = chosen.get("worker_id") if isinstance(chosen, dict) else None
        if chosen_worker_id and chosen_worker_id not in worker_ids:
            chosen_worker_id = None

        if not dry_run and chosen_worker_id:
            t.assigned_worker_id = int(chosen_worker_id)
            db.add(t)

        assignments.append({
            "task_id": t.task_id,
            "task_name": t.task_name,
            "assigned_worker_id": int(chosen_worker_id) if chosen_worker_id else None,
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
