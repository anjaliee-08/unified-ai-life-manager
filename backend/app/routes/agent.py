from app.services.intelligence_service import (
    build_user_profile,
    get_focus_recommendations,
    analyze_workload,
)
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional,List
from datetime import datetime, date, timedelta
import json
import re

from app.database import get_db
from app.models.task import Task
from app.models.user import User
from app.services.ollama_provider import OllamaProvider

router = APIRouter()
ollama = OllamaProvider()

# ─── Request/Response Models ──────────────────────────────────────
class CalendarEventData(BaseModel):
    """Calendar event sent from Flutter to agent"""
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
class EmailData(BaseModel):
    """Email metadata sent from Flutter to agent — read-only"""
    id: str
    sender: str
    sender_email: str
    subject: str
    snippet: str
    received_at: str
    is_unread: bool
    is_important: bool
    is_today: bool
    time_string: str
    labels: list = []
class MessageData(BaseModel):
    """SMS/device message sent from Flutter to agent — read-only"""
    id: str = ""
    sender: str
    address: str = ""
    snippet: str
    timestamp: str
    is_read: bool = True
    is_incoming: bool = True
    is_today: bool = False
    time_string: str = ""
class AgentRequest(BaseModel):
    user_id: int
    message: str
    confirm_action: Optional[str] = None  # for destructive confirmations
    confirm_task_id: Optional[int] = None
    calendar_events: Optional[List[CalendarEventData]] = None
    confirm_calendar_action: Optional[str] = None
    confirm_event_id: Optional[str] = None
    confirm_calendar_id: Optional[str] = None
    emails: Optional[List[EmailData]] = None
    messages: Optional[List[MessageData]] = None
class AgentResponse(BaseModel):
    response: str
    action_taken: Optional[str] = None
    requires_confirmation: bool = False
    pending_action: Optional[dict] = None

# ─── Tool: Get Tasks ──────────────────────────────────────────────

def tool_get_today_tasks(user_id: int, db: Session) -> list:
    today = date.today()
    tasks = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).all()
    today_tasks = []
    for t in tasks:
        if t.deadline and t.deadline.date() == today:
            today_tasks.append(t)
        elif not t.deadline:
            # Tasks with no deadline are always "today" tasks
            today_tasks.append(t)
    return today_tasks

def tool_get_all_pending(user_id: int, db: Session) -> list:
    return db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).order_by(Task.created_at.desc()).all()

def tool_get_high_priority(user_id: int, db: Session) -> list:
    return db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending",
        Task.priority == "high"
    ).all()

def tool_get_overdue(user_id: int, db: Session) -> list:
    now = datetime.now()
    return db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending",
        Task.deadline != None,
        Task.deadline < now
    ).all()

def tool_get_due_tomorrow(user_id: int, db: Session) -> list:
    tomorrow = date.today() + timedelta(days=1)
    tasks = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending",
        Task.deadline != None
    ).all()
    return [t for t in tasks if t.deadline.date() == tomorrow]

def tool_get_upcoming(user_id: int, db: Session) -> list:
    now = datetime.now()
    week_later = now + timedelta(days=7)
    tasks = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending",
        Task.deadline != None,
        Task.deadline >= now,
        Task.deadline <= week_later
    ).all()
    return sorted(tasks, key=lambda t: t.deadline)

def tool_find_task_by_reference(
    user_id: int, reference: str, db: Session
) -> list:
    """
    Safely find tasks matching a natural language reference.
    Returns list — caller handles multiple matches.
    Never accesses other users' tasks.
    """
    reference_lower = reference.lower().strip()
    all_tasks = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).all()

    # Exact match first
    exact = [
        t for t in all_tasks
        if reference_lower in t.description.lower()
    ]
    if exact:
        return exact

    # Word-by-word match
    words = [w for w in reference_lower.split() if len(w) > 2]
    partial = [
        t for t in all_tasks
        if any(w in t.description.lower() for w in words)
    ]
    return partial

# ─── Task serializer ──────────────────────────────────────────────

def task_to_dict(t: Task) -> dict:
    return {
        "id": t.id,
        "description": t.description,
        "priority": t.priority,
        "status": t.status,
        "deadline": t.deadline.isoformat() if t.deadline else None,
        "source": t.source,
    }

def format_task_list(tasks: list) -> str:
    if not tasks:
        return "none"
    lines = []
    for t in tasks:
        deadline_str = ""
        if t.deadline:
            deadline_str = f", due {t.deadline.strftime('%b %d %I:%M %p')}"
        lines.append(
            f"- [{t.priority.upper()}] {t.description}{deadline_str} (id:{t.id})"
        )
    return "\n".join(lines)

# ─── Intent Detection ─────────────────────────────────────────────

INTENT_SYSTEM_PROMPT = """You are an intent classifier for a personal AI life manager.

Classify the user's message into EXACTLY ONE intent from this list:

TASK INTENTS:
QUERY_TODAY - tasks and/or schedule for today
QUERY_FOCUS - what to focus on, most important tasks
QUERY_HIGH_PRIORITY - high priority tasks
QUERY_OVERDUE - overdue tasks
QUERY_TOMORROW - tasks and/or schedule for tomorrow
QUERY_UPCOMING - upcoming tasks/events this week
QUERY_ALL - all pending tasks

CALENDAR INTENTS:
QUERY_CALENDAR - calendar events generally
QUERY_MEETINGS - meetings or appointments
QUERY_SCHEDULE_AT - events at a specific time

EMAIL INTENTS:
QUERY_EMAIL_ALL - recent emails generally
QUERY_EMAIL_TODAY - today's emails
QUERY_EMAIL_UNREAD - unread emails
QUERY_EMAIL_SENDER - emails from a specific person
QUERY_EMAIL_SUBJECT - emails about a specific topic
QUERY_EMAIL_IMPORTANT - important emails

MESSAGE INTENTS — use these when the user asks about SMS or text messages:
QUERY_MESSAGE_ALL - recent messages generally ("show my messages", "what messages did I get")
QUERY_MESSAGE_TODAY - messages received today ("messages today", "texts today")
QUERY_MESSAGE_UNREAD - unread messages ("unread messages", "new texts")
QUERY_MESSAGE_SENDER - messages from a specific person ("did Aditya message me", "texts from Rahul", "did Priya send a message")
QUERY_MESSAGE_KEYWORD - messages about a specific topic ("messages about assignment", "texts about meeting")

TASK ACTION INTENTS:
ACTION_COMPLETE - mark a task complete
ACTION_DELETE - delete a task
ACTION_PRIORITY - change task priority
ACTION_CREATE - create a new task
ACTION_CREATE_EVENT - create a calendar event
ACTION_DELETE_EVENT - delete a calendar event

GENERAL - anything else not covered above

Reply ONLY with valid JSON. No explanation. No markdown. No code blocks.

{
  "intent": "INTENT_NAME",
  "task_reference": "task name mentioned or null",
  "event_reference": "calendar event mentioned or null",
  "email_sender_reference": "email sender name or null",
  "email_subject_reference": "email subject keyword or null",
  "message_sender_reference": "person name from message query or null",
  "message_keyword_reference": "topic from message query or null",
  "new_priority": "high or medium or low or null",
  "time_reference": "specific time mentioned or null",
  "confidence": 0.9
}

IMPORTANT: For queries like "did Aditya message me?" or "has Rahul texted?" —
always use QUERY_MESSAGE_SENDER and set message_sender_reference to the person's name."""
async def detect_intent(message: str) -> dict:
    """Use Qwen to classify intent from user message."""
    try:
        response = await ollama.generate(
            prompt=f"Classify this message: {message}",
            system_prompt=INTENT_SYSTEM_PROMPT,
            temperature=0.1
        )
        cleaned = re.sub(r'```json|```', '', response).strip()
        return json.loads(cleaned)
    except Exception:
        return {
            "intent": "GENERAL",
            "task_reference": None,
            "new_priority": None,
            "confidence": 0.5
        }

# ─── Response Generator ───────────────────────────────────────────

RESPONSE_SYSTEM_PROMPT = """You are UAILM, a personal AI life manager assistant.

You are given REAL data from the user's task database.

Rules:
- NEVER invent tasks, deadlines, or meetings not in the provided data.
- If data shows no tasks, say there are none — do NOT make up tasks.
- Be concise, friendly, and helpful.
- Keep responses under 120 words.
- Format task lists cleanly with emojis for priority (🔴 high, 🟠 medium, 🟢 low).
- If data is empty, acknowledge it naturally.
- Speak in first person as UAILM."""

async def generate_response(
    user_message: str,
    real_data: str,
    action_result: Optional[str] = None
) -> str:
    """Generate natural response grounded in real data."""
    context = f"""
User asked: {user_message}

Real data from database:
{real_data}

{f'Action result: {action_result}' if action_result else ''}

Now respond naturally based ONLY on the data above.
"""
    try:
        return await ollama.generate(
            prompt=context,
            system_prompt=RESPONSE_SYSTEM_PROMPT,
            temperature=0.4
        )
    except ConnectionError:
        return "⚠️ AI is offline. Please run: ollama serve"

# ─── Main Agent Endpoint ──────────────────────────────────────────

@router.post("/chat", response_model=AgentResponse)
async def agent_chat(
    req: AgentRequest,
    db: Session = Depends(get_db)
):
    print("========== CALENDAR DEBUG ==========")
    print("Calendar events received:", len(req.calendar_events or []))

    for event in (req.calendar_events or []):
        print("EVENT:", event)

    print("====================================")
    """
    Main AI agent endpoint.
    1. Validates user exists
    2. Detects intent
    3. Executes appropriate tool with user isolation
    4. Generates grounded natural language response
    """

    # ── Validate user exists ──────────────────────────────────────
    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # ── Handle pending confirmation (destructive actions) ─────────
    if req.confirm_action == "delete" and req.confirm_task_id:
        task = db.query(Task).filter(
            Task.id == req.confirm_task_id,
            Task.user_id == req.user_id  # user isolation enforced
        ).first()
        if not task:
            return AgentResponse(
                response="I couldn't find that task. It may have already been deleted."
            )
        desc = task.description
        db.delete(task)
        db.commit()
        return AgentResponse(
            response=f"✅ Done! I've deleted '{desc}'.",
            action_taken="delete_task"
        )

    if req.confirm_action == "complete" and req.confirm_task_id:
        task = db.query(Task).filter(
            Task.id == req.confirm_task_id,
            Task.user_id == req.user_id  # user isolation enforced
        ).first()
        if not task:
            return AgentResponse(
                response="I couldn't find that task."
            )
        desc = task.description
        task.status = "done"
        db.commit()
        return AgentResponse(
            response=f"✅ Marked '{desc}' as complete! Great work! 🎉",
            action_taken="complete_task"
        )

    if req.confirm_action == "cancel":
        return AgentResponse(response="No problem! Action cancelled.")

    # ── AI offline check ──────────────────────────────────────────
    if not await ollama.is_available():
        return AgentResponse(
            response="⚠️ UAILM AI is offline. Please run `ollama serve` to continue."
        )

    # ── Detect intent ─────────────────────────────────────────────
    intent_data = await detect_intent(req.message)
    intent = intent_data.get("intent", "GENERAL")
    task_ref = intent_data.get("task_reference")
    new_priority = intent_data.get("new_priority")

    # Debug — visible in uvicorn logs
    import logging
    logging.getLogger("uvicorn").info(
        f"Agent intent: {intent} | "
        f"message_sender_ref: {intent_data.get('message_sender_reference')} | "
        f"messages_count: {len(req.messages or [])}"
    )

    real_data = ""
    action_result = None
    requires_confirmation = False
    pending_action = None

    # ── Execute tool based on intent ──────────────────────────────

    if intent == "QUERY_TODAY":
        now = datetime.now()
        today_str = now.strftime("%B %d, %Y")  # e.g. "August 14, 2026"
        tasks = tool_get_today_tasks(req.user_id, db)
        workload = analyze_workload(req.user_id, db, now)
        cal_events = [e.dict() for e in (req.calendar_events or [])]
        real_data = (
            f"Today is {today_str}.\n\n"
            f"Today's tasks:\n{format_task_list(tasks)}\n\n"
            f"{format_calendar_events(cal_events, today_str)}\n\n"
            f"Workload: {workload['summary']}\n"
            f"Warnings: {'; '.join(workload['warnings']) if workload['warnings'] else 'none'}"
        )

    elif intent == "QUERY_FOCUS":
        profile = build_user_profile(req.user_id, db)
        focus = get_focus_recommendations(req.user_id, db, profile, top_n=3)
        if not focus["recommendations"]:
             real_data = "No pending tasks found."
        else:
            lines = []
            for item in focus["recommendations"]:
                risk = item.get("delay_risk", {})
                risk_str = f" [delay risk: {risk.get('risk', 'unknown')}]" if risk else ""
                reasons_str = ", ".join(item["reasons"][:2])
                lines.append(
                f"- [{item['priority'].upper()}] {item['description']}"
                f" (score: {item['score']}{risk_str})"
                f"\n  Why: {reasons_str}"
                )
            real_data = (
                 f"Intelligently ranked tasks ({focus['message']}):\n"
                  + "\n".join(lines)
          )

    elif intent == "QUERY_HIGH_PRIORITY":
        tasks = tool_get_high_priority(req.user_id, db)
        real_data = f"High priority tasks:\n{format_task_list(tasks)}"

    elif intent == "QUERY_OVERDUE":
        tasks = tool_get_overdue(req.user_id, db)
        real_data = f"Overdue tasks:\n{format_task_list(tasks)}"

    elif intent == "QUERY_TOMORROW":
        from datetime import timedelta
        tomorrow = datetime.now() + timedelta(days=1)
        tomorrow_str = tomorrow.strftime("%B %d, %Y")
        tasks = tool_get_due_tomorrow(req.user_id, db)
        cal_events = [e.dict() for e in (req.calendar_events or [])]
        real_data = (
            f"Tomorrow is {tomorrow_str}.\n\n"
            f"Tasks due tomorrow:\n{format_task_list(tasks)}\n\n"
            f"{format_calendar_events(cal_events, tomorrow_str)}"
        )

    elif intent == "QUERY_UPCOMING":
        tasks = tool_get_upcoming(req.user_id, db)
        real_data = f"Upcoming tasks this week:\n{format_task_list(tasks)}"

    elif intent == "QUERY_MEETINGS":
        all_tasks = tool_get_all_pending(req.user_id, db)
        meeting_tasks = [
            t for t in all_tasks
            if any(w in t.description.lower()
                   for w in ["meeting", "call", "standup",
                              "sync", "interview", "appointment"])
        ]
        cal_events = [e.dict() for e in (req.calendar_events or [])]
        now = datetime.now()
        today_str = now.strftime("%B %d, %Y")
        real_data = (
            f"Today is {today_str}.\n\n"
            f"Meeting-related tasks:\n{format_task_list(meeting_tasks)}\n\n"
            f"{format_calendar_events(cal_events, today_str)}"
        )
    elif intent == "QUERY_CALENDAR":
        cal_events = [e.dict() for e in (req.calendar_events or [])]
        if not cal_events:
            real_data = (
                "No calendar events were provided. "
                "Calendar may be empty or permission not granted."
            )
        else:
            real_data = format_calendar_events(cal_events)
    elif intent == "QUERY_EMAIL_ALL":
        emails = [e.dict() for e in (req.emails or [])]
        if not emails:
            real_data = (
                "No emails were provided. "
                "Email integration may not be connected."
            )
        else:
            real_data = format_emails(emails, "recent")

    elif intent == "QUERY_EMAIL_TODAY":
        emails = [e.dict() for e in (req.emails or [])]
        today_emails = [e for e in emails if e.get('is_today')]
        real_data = format_emails(
            today_emails if today_emails else emails,
            "today" if today_emails else "recent — no emails today"
        )

    elif intent == "QUERY_EMAIL_UNREAD":
        emails = [e.dict() for e in (req.emails or [])]
        unread = [e for e in emails if e.get('is_unread')]
        real_data = format_emails(unread, "unread")

    elif intent == "QUERY_EMAIL_IMPORTANT":
        emails = [e.dict() for e in (req.emails or [])]
        important = [e for e in emails if e.get('is_important')]
        real_data = format_emails(important, "important")

    elif intent == "QUERY_EMAIL_SENDER":
        sender_ref = intent_data.get("email_sender_reference", "")
        emails = [e.dict() for e in (req.emails or [])]
        if sender_ref:
            ref_lower = sender_ref.lower()
            matched = [
                e for e in emails
                if ref_lower in e.get('sender', '').lower()
                or ref_lower in e.get('sender_email', '').lower()
            ]
        else:
            matched = emails
        real_data = format_emails(
            matched,
            f"from '{sender_ref}'" if sender_ref else "all senders"
        )

    elif intent == "QUERY_EMAIL_SUBJECT":
        subject_ref = intent_data.get("email_subject_reference", "")
        emails = [e.dict() for e in (req.emails or [])]
        if subject_ref:
            ref_lower = subject_ref.lower()
            matched = [
                e for e in emails
                if ref_lower in e.get('subject', '').lower()
                or ref_lower in e.get('snippet', '').lower()
            ]
        else:
            matched = emails
        real_data = format_emails(
            matched,
            f"about '{subject_ref}'" if subject_ref else "all"
        )
    elif intent == "QUERY_MESSAGE_ALL":
        msgs = [m.dict() for m in (req.messages or [])]
        if not msgs:
            real_data = (
                "No messages provided. "
                "Message permission may not be granted."
            )
        else:
            real_data = format_messages(msgs, "recent")

    elif intent == "QUERY_MESSAGE_TODAY":
        msgs = [m.dict() for m in (req.messages or [])]
        today_msgs = [m for m in msgs if m.get('is_today')]
        real_data = format_messages(
            today_msgs if today_msgs else msgs,
            "today" if today_msgs
            else "recent — no messages today"
        )

    elif intent == "QUERY_MESSAGE_UNREAD":
        msgs = [m.dict() for m in (req.messages or [])]
        unread = [m for m in msgs if not m.get('is_read')]
        real_data = format_messages(unread, "unread")

    elif intent == "QUERY_MESSAGE_SENDER":
        sender_ref = intent_data.get(
            "message_sender_reference", "") or ""
        msgs = [m.dict() for m in (req.messages or [])]
        print("========== MESSAGE DEBUG ==========")
        print("Sender requested:", sender_ref)
        print("Total messages:", len(msgs))

        for i, m in enumerate(msgs):
            print(
                f"{i}: sender={m.get('sender')} | "
                f"address={m.get('address')} | "
                f"time={m.get('time_string')} | "
                f"snippet={m.get('snippet')}"
            )

        print("===================================")

        if not msgs:
            real_data = (
                "No messages were provided. "
                "Message permission may not be granted on the device."
            )
        elif sender_ref:
            ref_lower = sender_ref.lower().strip()
            # Search sender name AND address AND snippet
            # This handles cases where contact name resolution
            # gave us a phone number instead of a name
            matched = [
                m for m in msgs
                if ref_lower in m.get('sender', '').lower()
                or ref_lower in m.get('address', '').lower()
                or ref_lower in m.get('snippet', '').lower()
            ]
            if matched:
                real_data = format_messages(
                    matched,
                    f"from '{sender_ref}'"
                )
            else:
                # No match — show all messages so AI can search
                # and explain that no match was found
                real_data = (
                    f"No messages found specifically from "
                    f"'{sender_ref}'. "
                    f"All available messages:\n"
                    f"{format_messages(msgs, 'recent')}"
                )
        else:
            real_data = format_messages(msgs, "recent")

    elif intent == "QUERY_MESSAGE_KEYWORD":
        keyword_ref = intent_data.get(
            "message_keyword_reference", "")
        msgs = [m.dict() for m in (req.messages or [])]
        if keyword_ref:
            kw = keyword_ref.lower()
            matched = [
                m for m in msgs
                if kw in m.get('snippet', '').lower()
                or kw in m.get('sender', '').lower()
            ]
        else:
            matched = msgs
        real_data = format_messages(
            matched,
            f"about '{keyword_ref}'" if keyword_ref else "all"
        )
    elif intent == "QUERY_SCHEDULE_AT":
        intent_data_full = await detect_intent(req.message)
        time_ref = intent_data_full.get("time_reference", "")
        cal_events = [e.dict() for e in (req.calendar_events or [])]

        if time_ref and cal_events:
            matching = [
                e for e in cal_events
                if time_ref.lower() in e.get('time_string', '').lower()
                or time_ref in e.get('start', '')
            ]
            real_data = (
                f"Events around {time_ref}:\n"
                f"{format_calendar_events(matching) if matching else 'none found'}"
            )
        else:
            real_data = (
                f"Calendar events:\n{format_calendar_events(cal_events)}"
            )

    elif intent == "ACTION_DELETE_EVENT":
        event_ref = intent_data.get("event_reference", "")
        cal_events = [e.dict() for e in (req.calendar_events or [])]
        matches = find_event_by_reference(cal_events, event_ref or "")

        if not matches:
            return AgentResponse(
                response=f"I couldn't find a calendar event matching '{event_ref}'. "
                         f"Please check your calendar and try again."
            )
        elif len(matches) == 1:
            event = matches[0]
            return AgentResponse(
                response=f"I found **'{event['title']}'** "
                         f"({event.get('time_string', '')}).\n"
                         f"Are you sure you want to delete it?",
                requires_confirmation=True,
                pending_action={
                    "type": "delete_calendar_event",
                    "event_id": event['id'],
                    "calendar_id": event.get('calendar_id', ''),
                    "event_title": event['title'],
                }
            )
        else:
            event_list = "\n".join(
                [f"{i+1}. {e['title']} ({e.get('time_string', '')})"
                 for i, e in enumerate(matches[:5])]
            )
            return AgentResponse(
                response=f"I found {len(matches)} matching events:\n\n"
                         f"{event_list}\n\nWhich one did you want to delete?"
            )

    elif intent == "ACTION_CREATE_EVENT":
        # Signal Flutter to show event creation UI
        return AgentResponse(
            response="I'd love to create a calendar event! "
                     "Please tell me:\n"
                     "• Event title\n"
                     "• Date and time\n"
                     "• Duration (optional)\n"
                     "• Location (optional)\n\n"
                     "For example: 'Create a meeting called Team Sync tomorrow at 3pm for 1 hour'",
            action_taken="prompt_create_event"
        )

    elif intent == "QUERY_ALL":
        tasks = tool_get_all_pending(req.user_id, db)
        real_data = f"All pending tasks ({len(tasks)}):\n{format_task_list(tasks)}"

    elif intent == "ACTION_COMPLETE" and task_ref:
        matches = tool_find_task_by_reference(req.user_id, task_ref, db)

        if not matches:
            real_data = f"No task found matching '{task_ref}' for this user."

        elif len(matches) == 1:
            task = matches[0]
            requires_confirmation = True
            pending_action = {
                "type": "complete",
                "task_id": task.id,
                "task_description": task.description
            }
            response = (
                f"I found **'{task.description}'** "
                f"({task.priority} priority). "
                f"Mark it as complete?"
            )
            return AgentResponse(
                response=response,
                requires_confirmation=True,
                pending_action=pending_action
            )

        else:
            # Multiple matches — ask user to clarify
            task_list = "\n".join(
                [f"{i+1}. {t.description}" for i, t in enumerate(matches[:5])]
            )
            return AgentResponse(
                response=f"I found {len(matches)} tasks matching '{task_ref}':\n\n"
                         f"{task_list}\n\nWhich one did you mean?"
            )

    elif intent == "ACTION_DELETE" and task_ref:
        matches = tool_find_task_by_reference(req.user_id, task_ref, db)

        if not matches:
            real_data = f"No task found matching '{task_ref}'."

        elif len(matches) == 1:
            task = matches[0]
            return AgentResponse(
                response=f"I found **'{task.description}'**. "
                         f"Are you sure you want to delete it? "
                         f"This cannot be undone.",
                requires_confirmation=True,
                pending_action={
                    "type": "delete",
                    "task_id": task.id,
                    "task_description": task.description
                }
            )

        else:
            task_list = "\n".join(
                [f"{i+1}. {t.description}" for i, t in enumerate(matches[:5])]
            )
            return AgentResponse(
                response=f"I found {len(matches)} tasks matching '{task_ref}':\n\n"
                         f"{task_list}\n\nWhich one did you want to delete?"
            )

    elif intent == "ACTION_PRIORITY" and task_ref and new_priority:
        matches = tool_find_task_by_reference(req.user_id, task_ref, db)

        if not matches:
            real_data = f"No task found matching '{task_ref}'."

        elif len(matches) == 1:
            task = matches[0]
            old_priority = task.priority
            task.priority = new_priority
            db.commit()
            action_result = (
                f"Changed priority of '{task.description}' "
                f"from {old_priority} to {new_priority}."
            )
            real_data = action_result

        else:
            task_list = "\n".join(
                [f"{i+1}. {t.description}" for i, t in enumerate(matches[:5])]
            )
            return AgentResponse(
                response=f"Which task did you want to update?\n\n{task_list}"
            )

    elif intent == "ACTION_CREATE":
        # Let extract endpoint handle creation
        # Here we just acknowledge and suggest using extract
        real_data = (
            "User wants to create a task. "
            "Suggest they use the Extract Tasks feature "
            "or describe the task more clearly."
        )

    else:
        # GENERAL — give context about tasks + any emails provided
        tasks = tool_get_all_pending(req.user_id, db)
        emails = [e.dict() for e in (req.emails or [])]
        real_data = (
            f"User's pending tasks ({len(tasks)}):\n"
            f"{format_task_list(tasks)}"
        )
        if emails:
            real_data += f"\n\nRecent emails:\n{format_emails(emails[:3])}"

    # ── Generate grounded response ────────────────────────────────
    response_text = await generate_response(
        req.message, real_data, action_result
    )

    return AgentResponse(
        response=response_text,
        action_taken=action_result,
        requires_confirmation=requires_confirmation,
        pending_action=pending_action
    )

# ─── Quick task query endpoints (for Flutter to call directly) ────

@router.get("/tasks/today/{user_id}")
def get_today_tasks(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    tasks = tool_get_today_tasks(user_id, db)
    return [task_to_dict(t) for t in tasks]

@router.get("/tasks/overdue/{user_id}")
def get_overdue_tasks(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    tasks = tool_get_overdue(user_id, db)
    return [task_to_dict(t) for t in tasks]

@router.get("/tasks/high-priority/{user_id}")
def get_high_priority(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    tasks = tool_get_high_priority(user_id, db)
    return [task_to_dict(t) for t in tasks]

@router.get("/tasks/upcoming/{user_id}")
def get_upcoming(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    tasks = tool_get_upcoming(user_id, db)
    return [task_to_dict(t) for t in tasks]

def format_calendar_events(events: list, requested_date: str = "") -> str:
    """Format calendar events for AI context with explicit date labels."""
    if not events:
        return "none"
    
    date_label = f" (for {requested_date})" if requested_date else ""
    lines = [f"Calendar events{date_label}:"]
    
    for e in events:
        time_str = e.get('time_string', 'All day')
        loc = f" @ {e['location']}" if e.get('location') else ""
        now_str = " [HAPPENING NOW]" if e.get('is_now') else ""
        
        # Include explicit date in output so LLM cannot confuse dates
        date_str = e.get('date_string', '')
        date_prefix = f"[{date_str}] " if date_str else ""
        
        lines.append(
            f"- {date_prefix}{e['title']} | {time_str}{loc}{now_str}"
        )
    
    return "\n".join(lines)
def format_emails(emails: list, filter_desc: str = "") -> str:
    """Format email list for AI context."""
    if not emails:
        return "none"

    desc = f" ({filter_desc})" if filter_desc else ""
    lines = [f"Emails{desc}:"]

    for e in emails:
        unread = "UNREAD " if e.get('is_unread') else ""
        important = "⭐ " if e.get('is_important') else ""
        subject = e.get('subject', '(no subject)')
        sender = e.get('sender', 'Unknown')
        snippet = e.get('snippet', '')
        time_str = e.get('time_string', '')

        # Truncate snippet to avoid bloating context
        if len(snippet) > 120:
            snippet = snippet[:120] + '...'

        lines.append(
            f"- {unread}{important}From: {sender} | "
            f"Subject: {subject} | {time_str}\n"
            f"  Preview: {snippet}"
        )

    return "\n".join(lines)
def format_messages(messages: list, filter_desc: str = "") -> str:
    """Format device messages for AI context."""
    if not messages:
        return "none"

    desc = f" ({filter_desc})" if filter_desc else ""
    lines = [f"Messages{desc}:"]

    for m in messages:
        unread = "UNREAD " if not m.get('is_read') else ""
        sender = m.get('sender', 'Unknown')
        snippet = m.get('snippet', '')
        time_str = m.get('time_string', '')

        # Truncate snippet for AI context
        if len(snippet) > 100:
            snippet = snippet[:100] + '...'

        lines.append(
            f"- {unread}From: {sender} | {time_str}\n"
            f"  Message: {snippet}"
        )

    return "\n".join(lines)
def find_event_by_reference(
    events: list, reference: str
) -> list:
    """Find calendar events matching a natural language reference."""
    if not events or not reference:
        return []
    ref_lower = reference.lower()
    matches = [
        e for e in events
        if ref_lower in e.get('title', '').lower()
        or any(
            w in e.get('title', '').lower()
            for w in ref_lower.split()
            if len(w) > 2
        )
    ]
    return matches