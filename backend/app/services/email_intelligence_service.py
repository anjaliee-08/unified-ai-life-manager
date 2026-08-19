"""
Email Intelligence Service — UAILM Phase: Email → Task

Responsibilities:
  - Analyze email content using local Ollama/Qwen
  - Extract task candidates with deadline + priority + confidence
  - Parse relative date references into absolute datetimes
  - Validate and score extraction confidence
  - Check for duplicate task creation via email_source_id

Architecture:
  Ollama/Qwen handles NLP understanding.
  This service handles date resolution and confidence thresholds.
  Task persistence uses the EXISTING task model and endpoints.
"""

import json
import re
from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session

from app.models.task import Task
from app.services.ollama_provider import OllamaProvider

ollama = OllamaProvider()

# ── Confidence thresholds ──────────────────────────────────────────
# Keep configurable — do not scatter magic numbers in logic
CONFIDENCE_HIGH = 0.80
CONFIDENCE_MEDIUM = 0.50
CONFIDENCE_LOW = 0.30
AUTO_CREATE_THRESHOLD = 0.95   # reserved for future automatic mode
SUGGEST_THRESHOLD = 0.45       # below this, skip the suggestion entirely

# ── Extraction system prompt ───────────────────────────────────────
EXTRACTION_PROMPT = """You are an email task extraction AI for a personal task manager.

Given an email, determine if it contains an ACTIONABLE TASK the user must complete.

ACTIONABLE means:
- The USER needs to DO something
- There is a clear action required (submit, register, complete, send, attend, call, etc.)
- It is NOT just informational, congratulatory, or a past event

NEVER mark these as actionable:
- "Here are the slides from today's lecture" (informational)
- "Congratulations, you completed the assignment" (past/done)
- "The assignment deadline was last Friday" (past)
- "Here is a general announcement" (informational)
- "Your package has been delivered" (completed event)
- Newsletter or promotional emails

DO mark these as actionable:
- "Submit your ML assignment by Monday 11:59 PM"
- "Please complete the project report before Friday"
- "Registration closes tomorrow at 5 PM — register now"
- "Don't forget to submit the internship form"
- "Please attend the meeting tomorrow at 3 PM"
- "Reminder: workshop registration due Friday"

For the deadline, extract ONLY what is explicitly stated.
Do NOT invent deadlines.
If the deadline is relative (tomorrow, Monday, next week), preserve it exactly as stated.

Reply ONLY with valid JSON. No explanation. No markdown.

{
  "is_actionable": true or false,
  "task": "concise task description (what the user must do)",
  "deadline_text": "exact deadline phrase from email or null",
  "priority": "high or medium or low",
  "confidence": 0.0 to 1.0,
  "reason": "one sentence explaining why this is or is not actionable"
}

Priority rules:
- high: explicit deadline within 48 hours, or urgent/ASAP language
- medium: deadline within 1 week, or clear action without extreme urgency
- low: vague or distant deadline, or soft requests"""


# ── Date resolution ────────────────────────────────────────────────

WEEKDAYS = {
    "monday": 0, "tuesday": 1, "wednesday": 2,
    "thursday": 3, "friday": 4, "saturday": 5, "sunday": 6,
}

def resolve_deadline(deadline_text: Optional[str], now: datetime) -> Optional[datetime]:
    """
    Convert a relative deadline phrase into an absolute datetime.

    Examples:
      "tomorrow" → next day at 23:59
      "Monday at 11:59 PM" → next Monday at 23:59
      "Friday at 5 PM" → next Friday at 17:00
      "tonight" → today at 23:59
      null → None
    """
    if not deadline_text:
        return None

    text = deadline_text.lower().strip()

    # Extract time component if present
    time_hour = 23
    time_minute = 59

    time_match = re.search(
        r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)', text
    )
    if time_match:
        h = int(time_match.group(1))
        m = int(time_match.group(2) or 0)
        meridiem = time_match.group(3)
        if meridiem == 'pm' and h != 12:
            h += 12
        elif meridiem == 'am' and h == 12:
            h = 0
        time_hour = h
        time_minute = m

    # 24-hour time: "23:59"
    time24_match = re.search(r'\b(\d{1,2}):(\d{2})\b', text)
    if time24_match and not time_match:
        time_hour = int(time24_match.group(1))
        time_minute = int(time24_match.group(2))

    # Resolve the date
    target_date = None

    if 'tonight' in text or ('today' in text and time_hour < 23):
        target_date = now.date()

    elif 'tomorrow' in text:
        target_date = (now + timedelta(days=1)).date()

    elif 'next week' in text:
        target_date = (now + timedelta(weeks=1)).date()

    else:
        # Try weekday names: "Monday", "next Friday", etc.
        for day_name, day_num in WEEKDAYS.items():
            if day_name in text:
                days_ahead = day_num - now.weekday()
                if days_ahead <= 0:
                    days_ahead += 7
                # "next Monday" forces the following week even if
                # today is earlier in the week
                if 'next' in text:
                    days_ahead += 7
                target_date = (now + timedelta(days=days_ahead)).date()
                break

    if target_date is None:
        # Could not resolve — return None, not a fake date
        return None

    return datetime(
        target_date.year,
        target_date.month,
        target_date.day,
        time_hour,
        time_minute,
        0,
    )


# ── Core extraction ────────────────────────────────────────────────

async def analyze_email(
    email_data: dict,
    now: Optional[datetime] = None,
) -> dict:
    """
    Analyze a single email and return a task candidate.

    email_data keys (from EmailModel.toJson()):
      id, sender, sender_email, subject, snippet,
      received_at, is_unread, is_important, time_string

    Returns:
      {
        is_actionable: bool,
        task: str | None,
        deadline_text: str | None,
        deadline: ISO str | None,
        priority: str,
        confidence: float,
        confidence_label: str,
        reason: str,
        email_id: str,
        email_subject: str,
        email_sender: str,
        source: "email"
      }
    """
    if now is None:
        now = datetime.now()

    email_id = email_data.get('id', '')
    subject = email_data.get('subject', '(no subject)')
    sender = email_data.get('sender', 'Unknown')
    snippet = email_data.get('snippet', '')

    # Build prompt context
    email_context = (
        f"From: {sender}\n"
        f"Subject: {subject}\n"
        f"Preview: {snippet}"
    )

    if not await ollama.is_available():
        return _error_result(
            email_id, subject, sender,
            "AI offline — cannot analyze email"
        )

    try:
        raw = await ollama.generate(
            prompt=f"Analyze this email:\n\n{email_context}",
            system_prompt=EXTRACTION_PROMPT,
            temperature=0.1,
        )

        # Clean and parse JSON
        cleaned = re.sub(r'```json|```', '', raw).strip()
        result = json.loads(cleaned)

        is_actionable = bool(result.get('is_actionable', False))
        task_desc = result.get('task', '')
        deadline_text = result.get('deadline_text')
        priority = result.get('priority', 'medium')
        confidence = float(result.get('confidence', 0.5))
        reason = result.get('reason', '')

        # Resolve relative deadline → absolute datetime
        resolved_deadline = resolve_deadline(deadline_text, now)
        deadline_iso = resolved_deadline.isoformat() \
            if resolved_deadline else None

        # Adjust confidence based on deadline resolution
        if deadline_text and resolved_deadline is None:
            # Deadline mentioned but could not be resolved
            confidence = min(confidence, CONFIDENCE_MEDIUM)

        confidence_label = _confidence_label(confidence)

        return {
            "is_actionable": is_actionable,
            "task": task_desc,
            "deadline_text": deadline_text,
            "deadline": deadline_iso,
            "priority": priority,
            "confidence": round(confidence, 2),
            "confidence_label": confidence_label,
            "reason": reason,
            "email_id": email_id,
            "email_subject": subject,
            "email_sender": sender,
            "source": "email",
        }

    except json.JSONDecodeError:
        return _error_result(
            email_id, subject, sender,
            "AI returned invalid JSON — extraction failed"
        )
    except Exception as e:
        return _error_result(email_id, subject, sender, str(e))


def _confidence_label(confidence: float) -> str:
    if confidence >= CONFIDENCE_HIGH:
        return "high"
    if confidence >= CONFIDENCE_MEDIUM:
        return "medium"
    return "low"


def _error_result(
    email_id: str, subject: str, sender: str, error: str
) -> dict:
    return {
        "is_actionable": False,
        "task": None,
        "deadline_text": None,
        "deadline": None,
        "priority": "medium",
        "confidence": 0.0,
        "confidence_label": "low",
        "reason": f"Error: {error}",
        "email_id": email_id,
        "email_subject": subject,
        "email_sender": sender,
        "source": "email",
        "error": error,
    }


# ── Duplicate detection ────────────────────────────────────────────

def is_duplicate(
    user_id: int,
    email_id: str,
    db: Session,
) -> bool:
    """
    Check if a task already exists for this Gmail message ID
    and this user.

    Uses the email_source_id field added to the Task model.
    User isolation is enforced — checks user_id too.
    """
    if not email_id:
        return False
    existing = db.query(Task).filter(
        Task.user_id == user_id,
        Task.email_source_id == email_id,
    ).first()
    return existing is not None


# ── Task creation from confirmed candidate ─────────────────────────

def create_task_from_email(
    user_id: int,
    candidate: dict,
    db: Session,
) -> Task:
    """
    Create a Task from a confirmed email candidate.
    Reuses the existing Task model — no new schema beyond email_source_id.

    Called ONLY after explicit user confirmation.
    """
    deadline = None
    if candidate.get('deadline'):
        try:
            deadline = datetime.fromisoformat(candidate['deadline'])
        except ValueError:
            deadline = None

    task = Task(
        user_id=user_id,
        description=candidate.get('task', 'Task from email'),
        deadline=deadline,
        priority=candidate.get('priority', 'medium'),
        status='pending',
        source='email',
        confidence=candidate.get('confidence', 0.8),
        email_source_id=candidate.get('email_id'),
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    return task