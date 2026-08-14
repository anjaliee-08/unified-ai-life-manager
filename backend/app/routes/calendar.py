from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
from app.database import get_db
from app.models.user import User

router = APIRouter()

class CalendarEventIn(BaseModel):
    id: str
    title: str
    start: str
    end: str
    location: Optional[str] = None
    description: Optional[str] = None
    is_all_day: bool = False
    time_string: Optional[str] = None
    is_now: bool = False
    duration_minutes: Optional[int] = None
    calendar_id: str = ""

class CalendarEventsPayload(BaseModel):
    user_id: int
    events: List[CalendarEventIn]
    date_range: str = "today"

@router.post("/sync")
def sync_calendar_events(
    payload: CalendarEventsPayload,
    db: Session = Depends(get_db)
):
    """
    Receive calendar events from Flutter.
    We don't store them in DB (privacy) —
    just validate and acknowledge.
    Events are sent as context per-request to the agent.
    """
    user = db.query(User).filter(
        User.id == payload.user_id
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "status": "received",
        "event_count": len(payload.events),
        "user_id": payload.user_id,
        "message": f"Received {len(payload.events)} events for {payload.date_range}"
    }

@router.get("/status/{user_id}")
def calendar_status(user_id: int, db: Session = Depends(get_db)):
    """Check if calendar integration is configured for user."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "user_id": user_id,
        "calendar_enabled": True,
        "note": "Calendar data is read from device and sent per-request."
    }