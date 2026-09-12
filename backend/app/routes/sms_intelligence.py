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
)

router = APIRouter()


class SmsAnalyzeRequest(BaseModel):
    user_id: int
    messages: List[dict]  # List of MessageModel.toJson() dicts


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