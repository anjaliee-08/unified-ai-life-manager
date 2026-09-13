from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List
from datetime import datetime

from app.database import get_db
from app.models.user import User
from app.services.sms_intelligence_service import (
    analyze_sms_batch,
    SHOW_THRESHOLD,
    is_sms_duplicate,
    create_task_from_sms,
)

router = APIRouter()


class SmsAnalyzeRequest(BaseModel):
    user_id: int
    messages: List[dict]  # List of MessageModel.toJson() dicts

class SmsConfirmRequest(BaseModel):
    user_id: int
    extraction: dict

@router.post("/analyze")
async def analyze_messages(
    req: SmsAnalyzeRequest,
    db: Session = Depends(get_db),
):
    """
    Analyze SMS messages and return structured extractions.

    Phase 5A: INFORMATIONAL ONLY.
    No tasks, events, or calendar entries are created.
    No data is persisted.

    Flow:
      Flutter MessageService fetches SMS → sends here
      → Ollama/Qwen extracts structured info per message
      → Returns extractions for display only
    """
    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not req.messages:
        return {
            "extractions": [],
            "analyzed": 0,
            "message": "No messages provided"
        }

    now = datetime.now()
    extractions = await analyze_sms_batch(req.messages, now)

    return {
        "extractions": extractions,
        "analyzed": len(req.messages),
        "shown": len(extractions),
        "show_threshold": SHOW_THRESHOLD,
        "phase": "5A — informational only, no actions taken",
    }
@router.post("/confirm")
def confirm_sms_task(
    req: SmsConfirmRequest,
    db: Session = Depends(get_db),
):
    """
    Create a task from a confirmed SMS extraction.

    Called only after explicit user confirmation in Flutter.
    """

    # 1. Validate user
    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    extraction = req.extraction
    message_id = extraction.get("message_id", "")

    # 2. Final duplicate check
    if message_id and is_sms_duplicate(
        req.user_id,
        message_id,
        db,
    ):
        return {
            "status": "duplicate",
            "message": "A task from this SMS already exists.",
            "task_id": None,
        }

    # 3. Validate task information
    task_description = (
        extraction.get("title")
        or extraction.get("description")
        or ""
    ).strip()

    if not task_description:
        raise HTTPException(
            status_code=400,
            detail="Task description is missing from extraction",
        )

    # 4. Create task using existing SMS task creation logic
    task = create_task_from_sms(
        req.user_id,
        extraction,
        db,
    )

    return {
        "status": "created",
        "task_id": task.id,
        "description": task.description,
        "priority": task.priority,
        "deadline": (
            task.deadline.isoformat()
            if task.deadline
            else None
        ),
        "source": task.source,
        "message": f"Task '{task.description}' created from SMS.",
    }