from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User

router = APIRouter()


@router.get("/status/{user_id}")
def email_status(user_id: int, db: Session = Depends(get_db)):
    """
    Check whether email integration is available for this user.

    Email authentication and fetching are handled entirely on the
    Flutter/device side via Gmail OAuth (gmail.readonly scope).

    This endpoint only confirms the user exists in the UAILM database.
    It does NOT authenticate with Gmail, fetch emails, or store any
    email data — that all happens on-device.

    The actual email flow is:
      Flutter EmailService (OAuth) → emails[] payload → POST /api/agent/chat
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "user_id": user_id,
        "user_name": user.name,
        "email_integration": "gmail_readonly",
        "auth_location": "device",
        "scope": "https://www.googleapis.com/auth/gmail.readonly",
        "note": (
            "Email data is fetched on-device via Gmail OAuth "
            "and sent per-request to /api/agent/chat as context. "
            "No email data is stored on this backend."
        ),
    }