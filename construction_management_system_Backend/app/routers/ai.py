from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload
from typing import List, Dict, Any
from datetime import date

from app.database import get_db
from app.models import (
    Supervisor, AIChatSession, AIChatMessage,
    Task, Worker, Project
)
from app.schemas import (
    AIChatSessionOut, AIChatMessageOut,
    AIChatRequest, AITaskAnalysisRequest, AITaskAnalysisResponse,
    AIDailyReportRequest, AISafetyAnalysisRequest,
    AIAutoAssignRequest, AIAutoAssignResponse,
    SiteProgressPrediction
)
from app.routers.auth import cu, require_site_supervisor
from app.ai_service import (
    chat_with_ai, analyze_task, generate_daily_report, analyze_safety_risk,
    auto_assign_tasks, compute_project_progress, predict_site_progress
)

router = APIRouter(tags=["🤖 AI Services"])


@router.get("/ai/chat/sessions", response_model=List[AIChatSessionOut])
def list_chat_sessions(
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    sessions = db.query(AIChatSession).options(
        joinedload(AIChatSession.messages)
    ).filter(
        AIChatSession.supervisor_id == current_user.supervisor_id
    ).order_by(AIChatSession.updated_at.desc()).all()
    return sessions


@router.get("/ai/chat/sessions/{session_id}", response_model=AIChatSessionOut)
def get_chat_session(
    session_id: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    session = db.query(AIChatSession).options(
        joinedload(AIChatSession.messages)
    ).filter(
        AIChatSession.session_id == session_id,
        AIChatSession.supervisor_id == current_user.supervisor_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


@router.delete("/ai/chat/sessions/{session_id}")
def delete_chat_session(
    session_id: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    session = db.query(AIChatSession).filter(
        AIChatSession.session_id == session_id,
        AIChatSession.supervisor_id == current_user.supervisor_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    db.delete(session)
    db.commit()
    return {"status": "ok", "message": "Session deleted"}


@router.post("/ai/chat", response_model=Dict[str, Any])
def chat(
    request: AIChatRequest,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    session = None
    if request.session_id:
        session = db.query(AIChatSession).options(
            joinedload(AIChatSession.messages)
        ).filter(
            AIChatSession.session_id == request.session_id,
            AIChatSession.supervisor_id == current_user.supervisor_id
        ).first()

    if not session:
        session = AIChatSession(supervisor_id=current_user.supervisor_id)
        db.add(session)
        db.commit()
        db.refresh(session)

    user_msg = AIChatMessage(
        session_id=session.session_id,
        role="user",
        content=request.message
    )
    db.add(user_msg)
    db.flush()

    messages = [
        {"role": m.role, "content": m.content}
        for m in session.messages
    ]

    ai_response, tokens = chat_with_ai(messages)

    ai_msg = AIChatMessage(
        session_id=session.session_id,
        role="assistant",
        content=ai_response,
        tokens_used=tokens
    )
    db.add(ai_msg)
    db.commit()

    db.refresh(session)

    return {
        "session_id": session.session_id,
        "response": ai_response,
        "tokens_used": tokens
    }


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

    result = analyze_task(db, task_info, request.project_id)
    return AITaskAnalysisResponse(**result)


@router.post("/ai/reports/generate")
def generate_report(
    request: AIDailyReportRequest,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    report_content = generate_daily_report(db, request.project_id, request.report_date)
    return {"report": report_content}


@router.post("/ai/safety/analyze")
def safety_analysis(
    request: AISafetyAnalysisRequest,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    analysis = analyze_safety_risk(request.issue_description)
    return {"analysis": analysis}


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
        top_k=request.top_k
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
