from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

from app.database import get_db
from app.models.user import User
from app.models.task import Task
from app.services.email_intelligence_service import (
    analyze_email,
    is_duplicate,
    create_task_from_email,
    SUGGEST_THRESHOLD,
)

router = APIRouter()


# ── Request models ─────────────────────────────────────────────────

class EmailAnalyzeRequest(BaseModel):
    user_id: int
    emails: List[dict]   # List of EmailModel.toJson() dicts


class EmailConfirmRequest(BaseModel):
    user_id: int
    candidate: dict      # The full candidate dict from /analyze


# ── Endpoints ──────────────────────────────────────────────────────

@router.post("/analyze")
async def analyze_emails_for_tasks(
    req: EmailAnalyzeRequest,
    db: Session = Depends(get_db),
):
    """
    Analyze a list of emails and return task candidates.

    Flow:
      1. Validate user exists
      2. For each email: check duplicate, then run AI analysis
      3. Return only actionable candidates above confidence threshold
      4. Does NOT create any tasks — that requires /confirm

    Emails are received as metadata-only dicts from Flutter
    (same format as agentChatWithContext emails[] payload).
    """
    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not req.emails:
        return {"candidates": [], "analyzed": 0, "skipped_duplicates": 0}

    now = datetime.now()
    candidates = []
    skipped = 0

    for email_data in req.emails:
        email_id = email_data.get('id', '')

        # Skip if already processed for this user
        if email_id and is_duplicate(req.user_id, email_id, db):
            skipped += 1
            continue

        # AI analysis
        result = await analyze_email(email_data, now)

        # Only return actionable results above suggestion threshold
        if (
            result.get('is_actionable')
            and result.get('confidence', 0) >= SUGGEST_THRESHOLD
        ):
            candidates.append(result)

    return {
        "candidates": candidates,
        "analyzed": len(req.emails),
        "skipped_duplicates": skipped,
        "suggestion_threshold": SUGGEST_THRESHOLD,
    }


@router.post("/confirm")
def confirm_email_task(
    req: EmailConfirmRequest,
    db: Session = Depends(get_db),
):
    """
    Create a task from a confirmed email candidate.

    Flow:
      1. Validate user
      2. Final duplicate check (race condition safety)
      3. Create task using existing Task model
      4. Task enters existing intelligence/focus system automatically

    Called ONLY after explicit user confirmation in Flutter.
    """
    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    candidate = req.candidate
    email_id = candidate.get('email_id', '')

    # Final safety check for duplicates
    if email_id and is_duplicate(req.user_id, email_id, db):
        return {
            "status": "duplicate",
            "message": "A task from this email already exists.",
            "task_id": None,
        }

    # Validate minimum required fields
    task_description = candidate.get('task', '').strip()
    if not task_description:
        raise HTTPException(
            status_code=400,
            detail="Task description is missing from candidate"
        )

    # Create using existing Task model
    task = create_task_from_email(req.user_id, candidate, db)

    return {
        "status": "created",
        "task_id": task.id,
        "description": task.description,
        "priority": task.priority,
        "deadline": task.deadline.isoformat() if task.deadline else None,
        "source": task.source,
        "message": f"Task '{task.description}' created from email.",
    }


@router.get("/history/{user_id}")
def get_email_task_history(
    user_id: int,
    db: Session = Depends(get_db),
):
    """
    Return all tasks created from emails for this user.
    Useful for showing which emails have already been processed.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    email_tasks = db.query(Task).filter(
        Task.user_id == user_id,
        Task.source == 'email',
        Task.email_source_id != None,
    ).all()

    return {
        "email_tasks": [
            {
                "task_id": t.id,
                "description": t.description,
                "priority": t.priority,
                "deadline": t.deadline.isoformat()
                    if t.deadline else None,
                "status": t.status,
                "email_source_id": t.email_source_id,
                "created_at": t.created_at.isoformat()
                    if t.created_at else None,
            }
            for t in email_tasks
        ],
        "count": len(email_tasks),
    }