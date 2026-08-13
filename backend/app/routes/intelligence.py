from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime
from app.database import get_db
from app.services.intelligence_service import (
    build_user_profile,
    get_focus_recommendations,
    analyze_workload,
    estimate_delay_risk,
    score_task,
    detect_category,
)
from app.models.task import Task
from app.models.user import User
from fastapi import HTTPException

router = APIRouter()


@router.get("/focus/{user_id}")
def get_focus(user_id: int, db: Session = Depends(get_db)):
    """
    Returns intelligently ranked task recommendations
    based on scoring + learned user behavior.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    profile = build_user_profile(user_id, db)
    result = get_focus_recommendations(user_id, db, profile)
    return result


@router.get("/workload/{user_id}")
def get_workload(user_id: int, db: Session = Depends(get_db)):
    """
    Returns workload analysis — overload detection,
    deadline clustering, high-priority concentration.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    now = datetime.now()
    result = analyze_workload(user_id, db, now)
    return result


@router.get("/risk/{user_id}")
def get_risk(user_id: int, db: Session = Depends(get_db)):
    """
    Returns delay risk estimate for every pending task.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    now = datetime.now()
    profile = build_user_profile(user_id, db)

    pending = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).all()

    results = []
    for task in pending:
        risk = estimate_delay_risk(task, now, profile)
        results.append({
            "task_id": task.id,
            "description": task.description,
            "priority": task.priority,
            "deadline": task.deadline.isoformat() if task.deadline else None,
            "category": detect_category(task.description),
            **risk,
        })

    return {
        "tasks": results,
        "is_learned": profile.has_sufficient_data,
        "data_points": profile.data_points,
    }


@router.get("/profile/{user_id}")
def get_profile(user_id: int, db: Session = Depends(get_db)):
    """
    Returns user's behavioral profile built from task history.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    profile = build_user_profile(user_id, db)

    return {
        "has_sufficient_data": profile.has_sufficient_data,
        "data_points": profile.data_points,
        "total_completed": profile.total_completed,
        "late_completion_rate": round(profile.late_completion_rate, 2),
        "avg_completion_hours": round(profile.avg_completion_hours, 1)
        if profile.avg_completion_hours else None,
        "category_late_rates": getattr(profile, '_category_late_rates', {}),
        "priority_completion_rates": profile.priority_completion_rates,
        "message": (
            "Profile built from your task history."
            if profile.has_sufficient_data
            else f"Need {5 - profile.data_points} more completed tasks to build your profile."
        )
    }


@router.get("/score/{user_id}")
def get_scores(user_id: int, db: Session = Depends(get_db)):
    """
    Returns intelligence score for every pending task.
    Useful for debugging the scoring system.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    now = datetime.now()
    profile = build_user_profile(user_id, db)

    pending = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).all()

    scored = [score_task(t, now, profile) for t in pending]
    scored.sort(key=lambda x: x["score"], reverse=True)

    return {
        "scored_tasks": scored,
        "is_learned": profile.has_sufficient_data,
        "data_points": profile.data_points,
    }