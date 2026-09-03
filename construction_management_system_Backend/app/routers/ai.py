from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload
from typing import List, Dict, Any
from datetime import date

from app.database import get_db
from app.models import (
    Supervisor, Task, Worker, Project, PredictionHistory
)
from app.schemas import (
    AITaskAnalysisRequest, AITaskAnalysisResponse,
    AIAutoAssignRequest, AIAutoAssignResponse,
    SiteProgressPrediction
)
from app.routers.auth import cu, require_site_supervisor
from app.ai_service import (
    analyze_task, auto_assign_tasks, compute_project_progress, predict_site_progress
)

router = APIRouter(tags=["🤖 AI Services"])


@router.post("/ai/tasks/analyze", response_model=AITaskAnalysisResponse)
def task_analysis(
    request: AITaskAnalysisRequest,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    task_info = {}
    if request.task_id:
        task = db.query(Task).options(
            joinedload(Task.project)
        ).filter(Task.task_id == request.task_id).first()
        if task:
            task_info["task_name"] = task.task_name
            task_info["description"] = task.description
        else:
            raise HTTPException(status_code=404, detail="Task not found")
    else:
        task_info["task_name"] = request.task_name or ""
        task_info["description"] = request.description or ""

    result = analyze_task(
        db, task_info, request.project_id,
        same_project_only=request.same_project_only,
    )
    return AITaskAnalysisResponse(**result)


@router.post("/ai/tasks/auto-assign", response_model=AIAutoAssignResponse)
def ai_auto_assign_tasks(
    request: AIAutoAssignRequest,
    db: Session = Depends(get_db),
    current_user=Depends(require_site_supervisor)
):
    return auto_assign_tasks(
        db=db,
        project_id=request.project_id,
        task_ids=request.task_ids,
        dry_run=request.dry_run,
        top_k=request.top_k,
        same_project_only=request.same_project_only,
    )


@router.get("/ai/projects/{pid}/progress-prediction", response_model=SiteProgressPrediction)
def get_progress_prediction(
    pid: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    """
    AI-powered site progress prediction for a specific project.
    Analyses historical task completion velocity, attendance trends, overdue patterns
    and uses Gemini AI to predict completion date, future progress milestones,
    risk factors and recommendations.
    """
    result = predict_site_progress(db, pid)
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result


@router.get("/ai/projects/{pid}/prediction-history")
def prediction_history(
    pid: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    """
    Recent AI prediction snapshots for a project, oldest -> newest, for
    "predicted vs actual" accuracy comparison on the dashboard.
    """
    project = db.query(Project).filter(Project.project_id == pid).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

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
