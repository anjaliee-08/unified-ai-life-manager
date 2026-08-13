from app.services.intelligence_service import (
    build_user_profile,
    get_focus_recommendations,
    analyze_workload,
)
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
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

class AgentRequest(BaseModel):
    user_id: int
    message: str
    confirm_action: Optional[str] = None  # for destructive confirmations
    confirm_task_id: Optional[int] = None

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

INTENT_SYSTEM_PROMPT = """You are an intent classifier for a task management AI assistant.

Classify the user's message into EXACTLY ONE of these intents:

QUERY_TODAY - asking about today's tasks
QUERY_FOCUS - asking what to focus on or what's most important
QUERY_HIGH_PRIORITY - asking about high priority tasks
QUERY_OVERDUE - asking about overdue tasks
QUERY_TOMORROW - asking about tomorrow's tasks
QUERY_UPCOMING - asking about upcoming tasks this week
QUERY_MEETINGS - asking about meetings
QUERY_ALL - general question about all tasks

ACTION_COMPLETE - wants to mark a task as done/complete
ACTION_DELETE - wants to delete a task
ACTION_PRIORITY - wants to change task priority
ACTION_CREATE - wants to create a new task

GENERAL - general conversation not related to tasks

Reply with ONLY a JSON object. No explanation. No markdown.

Format:
{
  "intent": "INTENT_NAME",
  "task_reference": "the task they mentioned or null",
  "new_priority": "high/medium/low or null",
  "confidence": 0.9
}"""

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

    real_data = ""
    action_result = None
    requires_confirmation = False
    pending_action = None

    # ── Execute tool based on intent ──────────────────────────────

    if intent == "QUERY_TODAY":
        now = datetime.now()
        tasks = tool_get_today_tasks(req.user_id, db)
        workload = analyze_workload(req.user_id, db, now)
        real_data = (
            f"Today's tasks:\n{format_task_list(tasks)}\n\n"
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
        tasks = tool_get_due_tomorrow(req.user_id, db)
        real_data = f"Tasks due tomorrow:\n{format_task_list(tasks)}"

    elif intent == "QUERY_UPCOMING":
        tasks = tool_get_upcoming(req.user_id, db)
        real_data = f"Upcoming tasks this week:\n{format_task_list(tasks)}"

    elif intent == "QUERY_MEETINGS":
        all_tasks = tool_get_all_pending(req.user_id, db)
        meetings = [
            t for t in all_tasks
            if any(w in t.description.lower()
                   for w in ["meeting", "call", "standup",
                              "sync", "interview", "appointment"])
        ]
        real_data = f"Meeting-related tasks:\n{format_task_list(meetings)}"

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
        # GENERAL — give context about all tasks
        tasks = tool_get_all_pending(req.user_id, db)
        real_data = (
            f"User's pending tasks ({len(tasks)}):\n"
            f"{format_task_list(tasks)}"
        )

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