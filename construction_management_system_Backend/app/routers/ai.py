from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, joinedload
from typing import List, Dict, Any, Optional
from datetime import date, datetime

from app.database import get_db
from app.models import (
    Supervisor, Task, Worker, Project, PredictionHistory
)
from app.schemas import (
    AITaskAnalysisRequest, AITaskAnalysisResponse,
    AIAutoAssignRequest, AIAutoAssignResponse,
    SiteProgressPrediction, CurrentUser
)
from app.routers.auth import project_for_user, require_site_supervisor
from app.ai_service import (
    analyze_task, auto_assign_tasks, predict_site_progress, llm_status
)
from app.ai_stats import build_decision_stats, empty_stats

router = APIRouter(tags=["🤖 AI Services"])


def _owned_project_ids(db: Session, user: CurrentUser) -> List[int]:
    """Return only projects the current supervisor may use as an AI pool."""
    return [
        int(project_id)
        for (project_id,) in db.query(Project.project_id)
        .filter(Project.supervisor_id == user.id)
        .all()
    ]


@router.post("/ai/tasks/analyze", response_model=AITaskAnalysisResponse)
def task_analysis(
    request: AITaskAnalysisRequest,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(require_site_supervisor),
):
    project_for_user(db, current_user, request.project_id, supervisor_only=True)
    task_info = {}
    if request.task_id:
        task = db.query(Task).options(
            joinedload(Task.project)
        ).filter(
            Task.task_id == request.task_id,
            Task.project_id == request.project_id,
        ).first()
        if task:
            task_info["task_id"] = task.task_id
            task_info["task_name"] = task.task_name
            task_info["description"] = task.description
            task_info["trade"] = task.trade
        else:
            raise HTTPException(status_code=404, detail="Task not found")
    else:
        task_info["task_name"] = request.task_name or ""
        task_info["description"] = request.description or ""
        task_info["trade"] = request.trade or ""

    result = analyze_task(
        db, task_info, request.project_id,
        same_project_only=request.same_project_only,
        allowed_project_ids=_owned_project_ids(db, current_user),
        # Preview clicks are not supervisor-confirmed decisions. Keeping them
        # out of the audit dataset prevents misleading AI accuracy metrics.
        log_decision=False,
    )
    return AITaskAnalysisResponse(**result)


@router.post("/ai/tasks/auto-assign", response_model=AIAutoAssignResponse)
def ai_auto_assign_tasks(
    request: AIAutoAssignRequest,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(require_site_supervisor),
):
    if request.project_id is None:
        raise HTTPException(status_code=400, detail="project_id is required for auto-assign")
    project_for_user(db, current_user, request.project_id, supervisor_only=True)
    if request.task_ids:
        requested_ids = {int(task_id) for task_id in request.task_ids}
        matched_ids = {
            int(task_id)
            for (task_id,) in db.query(Task.task_id).filter(
                Task.project_id == request.project_id,
                Task.task_id.in_(requested_ids),
            ).all()
        }
        if matched_ids != requested_ids:
            # Avoid disclosing whether an id belongs to another supervisor.
            raise HTTPException(status_code=404, detail="One or more tasks were not found in this project")
    return auto_assign_tasks(
        db=db,
        project_id=request.project_id,
        task_ids=request.task_ids,
        dry_run=request.dry_run,
        top_k=request.top_k,
        same_project_only=request.same_project_only,
        allowed_project_ids=_owned_project_ids(db, current_user),
    )


@router.get("/ai/projects/{pid}/progress-prediction", response_model=SiteProgressPrediction)
def get_progress_prediction(
    pid: int,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(require_site_supervisor),
):
    """
    AI-powered site progress prediction for a specific project.
    Analyses historical task completion velocity, attendance trends, overdue patterns
    and uses Gemini AI to predict completion date, future progress milestones,
    risk factors and recommendations.
    """
    project_for_user(db, current_user, pid, supervisor_only=True)
    result = predict_site_progress(db, pid)
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result


@router.get("/ai/projects/{pid}/prediction-history")
def prediction_history(
    pid: int,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(require_site_supervisor),
):
    """
    Recent AI prediction snapshots for a project, oldest -> newest, for
    "predicted vs actual" accuracy comparison on the dashboard.
    """
    project = project_for_user(db, current_user, pid, supervisor_only=True)

    rows = (
        db.query(PredictionHistory)
        .filter(PredictionHistory.project_id == pid)
        .order_by(PredictionHistory.prediction_id.desc())
        .limit(12)
        .all()
    )
    latest_progress = float(project.progress or 0.0)
    out = []
    for r in reversed(rows):
        out.append({
            "prediction_id": r.prediction_id,
            "project_id": r.project_id,
            "predicted_progress": round(float(r.predicted_progress or 0.0), 1),
            "scheduled_progress": round(float(r.scheduled_progress), 1) if r.scheduled_progress is not None else None,
            "actual_progress": round(float(r.actual_progress or 0.0), 1),
            "latest_progress": latest_progress,
            "predicted_completion_date": r.predicted_completion_date.isoformat() if r.predicted_completion_date else None,
            "trend": r.trend,
            "confidence": round(float(r.confidence), 1) if r.confidence is not None else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })
    return out


@router.get("/ai/status")
def ai_layer_status(current_user=Depends(require_site_supervisor)):
    """What the AI layer can actually do right now.

    The app used to expose only the *results* of the AI pipeline, so a deployment
    with a missing key or an exhausted Gemini quota looked identical to a healthy
    one - every answer silently came from the rule layer. This endpoint reports
    the degraded state (``last_error``) so the UI and the report can say honestly
    which layer produced an answer.
    """
    return llm_status()


@router.get("/ai/decision-log/stats")
def decision_log_stats(
    project_id: Optional[int] = Query(None, description="Restrict to one project"),
    start: Optional[datetime] = Query(None, description="Inclusive lower bound on created_at (ISO 8601)"),
    end: Optional[datetime] = Query(None, description="Inclusive upper bound on created_at (ISO 8601)"),
    stage: Optional[str] = Query(None, pattern="^(trade_resolution|auto_assign)$",
                                 description="Restrict to one decision stage"),
    top_n: int = Query(5, ge=1, le=50, description="How many skip reasons / trades to return"),
    low_confidence_threshold: float = Query(0.5, ge=0.0, le=1.0,
                                            description="Confidence below this counts as low confidence"),
    db: Session = Depends(get_db),
    current_user=Depends(require_site_supervisor),
):
    """Read-only statistics over ``ai_decision_log`` (closed-loop observability).

    Everything is computed with SQL aggregates, so the endpoint stays cheap on a
    table that grows by one row per AI decision. Empty table / empty time window
    still returns the full structure with zero counts and ``null`` rates - the
    dashboard never has to special-case "no data yet". Fields:

    * ``total_decisions`` / ``decided`` / ``skip_count`` - volume and coverage.
    * ``by_source`` - which layer decided (rule / classifier / semantic / llm / skip).
    * ``by_final_trade`` - top trades produced, the class balance of the sample.
    * ``skip_reasons`` - why the pipeline refused to guess (top N + total).
    * ``llm`` - fallback triggers, adopted verdicts and the adoption rate; a
      trigger that was thrown away because Gemini was not confident counts as
      ``discarded``.
    * ``overrides`` - how often a supervisor overrode the AI, i.e. the live
      error signal; those rows become labelled training samples.
    * ``elapsed_ms`` - average / min / max decision latency.
    * ``low_confidence`` - predictions below the confidence floor.
    """
    if start and end and start > end:
        raise HTTPException(status_code=400, detail="start must be earlier than end")

    if project_id is None:
        # A global aggregate would expose every supervisor's decision history.
        # The dashboard already renders AI metrics for one selected project.
        raise HTTPException(status_code=400, detail="project_id is required for decision statistics")
    project_for_user(db, current_user, project_id, supervisor_only=True)

    try:
        return build_decision_stats(
            db,
            project_id=project_id,
            start=start,
            end=end,
            stage=stage,
            top_n=top_n,
            low_confidence_threshold=low_confidence_threshold,
        )
    except SQLAlchemyError:
        # Table absent (old deployment that has not migrated yet): answer with an
        # all-zero payload instead of a 500 so the UI still renders.
        db.rollback()
        return empty_stats(project_id=project_id, start=start, end=end, stage=stage,
                           low_confidence_threshold=low_confidence_threshold)
