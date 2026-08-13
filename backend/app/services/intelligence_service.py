"""
UAILM Intelligence Service — Task 2B

ML approach: Feature-based scoring with statistical learning from history.

Why not neural networks:
- User has few tasks (10–100), not enough for deep learning
- Need explainability ("I recommend this because...")
- Must work offline with no external dependencies
- Can improve incrementally as data grows

Architecture:
- IntelligenceService.score_task() → deterministic scoring
- IntelligenceService.analyze_history() → statistical patterns from real DB data
- IntelligenceService.focus_recommendations() → ranked list with reasons
- IntelligenceService.workload_analysis() → overload detection
- IntelligenceService.delay_risk() → per-task risk estimation
"""

from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session
from app.models.task import Task


# ─── Constants ────────────────────────────────────────────────────

MIN_HISTORY_FOR_LEARNING = 5  # tasks needed before learned behavior applies

PRIORITY_WEIGHT = {"high": 1.0, "medium": 0.6, "low": 0.3}

CATEGORY_KEYWORDS = {
    "academic": ["assignment", "exam", "submit", "professor",
                 "homework", "project", "study", "course", "class"],
    "meeting": ["meeting", "call", "standup", "sync",
                "interview", "appointment", "zoom", "teams"],
    "personal": ["gym", "doctor", "family", "birthday",
                 "shopping", "call mom", "health"],
    "work": ["report", "presentation", "client", "deadline",
             "review", "deploy", "release", "sprint"],
}


def detect_category(description: str) -> str:
    desc_lower = description.lower()
    for category, keywords in CATEGORY_KEYWORDS.items():
        if any(kw in desc_lower for kw in keywords):
            return category
    return "general"


# ─── Historical Pattern Analysis ──────────────────────────────────

class UserBehaviorProfile:
    """
    Statistical summary of user's task completion behavior.
    Built from real DB data only.
    """
    def __init__(self):
        self.total_completed = 0
        self.total_overdue_at_completion = 0
        self.avg_completion_hours: Optional[float] = None
        self.category_completion_rates: dict = {}
        self.priority_completion_rates: dict = {}
        self.late_completion_rate: float = 0.0
        self.has_sufficient_data: bool = False
        self.data_points: int = 0


def build_user_profile(user_id: int, db: Session) -> UserBehaviorProfile:
    """
    Analyze ALL tasks (including completed/deleted) for this user.
    Returns a profile based purely on real historical data.
    """
    profile = UserBehaviorProfile()

    # Get all completed tasks for this user
    completed = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "done",
        Task.completed_at != None
    ).all()

    profile.data_points = len(completed)

    if len(completed) < MIN_HISTORY_FOR_LEARNING:
        profile.has_sufficient_data = False
        return profile

    profile.has_sufficient_data = True
    profile.total_completed = len(completed)

    # ── Completion time analysis ───────────────────────────────────
    completion_hours = []
    late_count = 0

    for task in completed:
        hours = (task.completed_at - task.created_at).total_seconds() / 3600
        completion_hours.append(hours)

        # Was it completed after deadline?
        if task.deadline and task.completed_at > task.deadline:
            late_count += 1

    if completion_hours:
        profile.avg_completion_hours = sum(completion_hours) / len(completion_hours)

    profile.late_completion_rate = late_count / len(completed) if completed else 0.0
    profile.total_overdue_at_completion = late_count

    # ── Category completion rates ──────────────────────────────────
    category_counts: dict = {}
    category_late: dict = {}

    for task in completed:
        cat = detect_category(task.description)
        category_counts[cat] = category_counts.get(cat, 0) + 1
        if task.deadline and task.completed_at > task.deadline:
            category_late[cat] = category_late.get(cat, 0) + 1

    # Get all pending to calculate pending per category
    all_tasks = db.query(Task).filter(Task.user_id == user_id).all()
    category_total: dict = {}
    for task in all_tasks:
        cat = detect_category(task.description)
        category_total[cat] = category_total.get(cat, 0) + 1

    for cat, count in category_counts.items():
        total = category_total.get(cat, count)
        profile.category_completion_rates[cat] = count / total if total > 0 else 0.5
        late = category_late.get(cat, 0)
        # Store late rate per category (higher = more often late in this category)
        if cat not in profile.category_completion_rates:
            profile.category_completion_rates[cat] = {}

    # Store late rates separately
    profile._category_late_rates = {}
    for cat in category_counts:
        late = category_late.get(cat, 0)
        total = category_counts[cat]
        profile._category_late_rates[cat] = late / total if total > 0 else 0.0

    # ── Priority completion rates ──────────────────────────────────
    priority_counts: dict = {"high": 0, "medium": 0, "low": 0}
    priority_late: dict = {"high": 0, "medium": 0, "low": 0}

    for task in completed:
        p = task.priority or "medium"
        priority_counts[p] = priority_counts.get(p, 0) + 1
        if task.deadline and task.completed_at > task.deadline:
            priority_late[p] = priority_late.get(p, 0) + 1

    for p in ["high", "medium", "low"]:
        count = priority_counts[p]
        if count > 0:
            profile.priority_completion_rates[p] = (
                priority_late[p] / count
            )
        else:
            profile.priority_completion_rates[p] = None  # unknown

    return profile


# ─── Task Scoring ──────────────────────────────────────────────────

def score_task(
    task: Task,
    now: datetime,
    profile: UserBehaviorProfile
) -> dict:
    """
    Calculate intelligent priority score for a task.

    Score components:
    1. Priority weight (rule-based)
    2. Deadline urgency (rule-based)
    3. Overdue penalty (rule-based)
    4. Task age (rule-based)
    5. Category delay risk (learned from history if available)
    6. Priority late rate (learned from history if available)

    Returns score (0-100) + breakdown for explainability.
    """
    score = 0.0
    reasons = []

    # ── 1. Base priority score ─────────────────────────────────────
    priority_score = PRIORITY_WEIGHT.get(task.priority, 0.5) * 30
    score += priority_score
    reasons.append(f"{task.priority} priority (+{priority_score:.0f})")

    # ── 2. Deadline urgency ────────────────────────────────────────
    deadline_score = 0.0
    hours_until_deadline = None

    if task.deadline:
        delta = task.deadline - now
        hours = delta.total_seconds() / 3600

        if hours < 0:
            # Overdue — maximum urgency
            deadline_score = 40.0
            overdue_hours = abs(hours)
            reasons.append(f"overdue by {overdue_hours:.0f}h (+40)")
        elif hours <= 4:
            deadline_score = 35.0
            reasons.append(f"due in {hours:.1f}h (+35)")
        elif hours <= 24:
            deadline_score = 28.0
            reasons.append(f"due today (+28)")
        elif hours <= 48:
            deadline_score = 20.0
            reasons.append(f"due tomorrow (+20)")
        elif hours <= 168:  # 1 week
            deadline_score = 10.0
            reasons.append(f"due this week (+10)")
        else:
            deadline_score = 2.0
            reasons.append(f"due later (+2)")

        hours_until_deadline = hours
    else:
        # No deadline — small neutral score
        deadline_score = 5.0
        reasons.append("no deadline (+5)")

    score += deadline_score

    # ── 3. Task age (older pending tasks get a small boost) ────────
    age_hours = (now - task.created_at).total_seconds() / 3600
    if age_hours > 72:
        age_score = min(8.0, age_hours / 72)
        score += age_score
        days = age_hours / 24
        reasons.append(f"pending {days:.0f}d (+{age_score:.0f})")

    # ── 4. Learned behavior adjustment ────────────────────────────
    learned_adjustment = 0.0

    if profile.has_sufficient_data:
        cat = detect_category(task.description)
        cat_late_rate = getattr(profile, '_category_late_rates', {}).get(cat)

        if cat_late_rate is not None and cat_late_rate > 0.5:
            # User is often late on this category — boost urgency
            learned_adjustment += 7.0
            reasons.append(
                f"you're often late on {cat} tasks (+7)"
            )
        elif cat_late_rate is not None and cat_late_rate < 0.2:
            # User is reliably on time for this category — slight reduction
            learned_adjustment -= 3.0
            reasons.append(
                f"you handle {cat} tasks reliably (-3)"
            )

        # Priority-specific late rate
        p_late = profile.priority_completion_rates.get(task.priority)
        if p_late is not None and p_late > 0.6:
            learned_adjustment += 5.0
            reasons.append(
                f"you often complete {task.priority} tasks late (+5)"
            )

    score += learned_adjustment
    score = max(0.0, min(100.0, score))  # clamp 0–100

    return {
        "task_id": task.id,
        "description": task.description,
        "priority": task.priority,
        "deadline": task.deadline.isoformat() if task.deadline else None,
        "score": round(score, 1),
        "reasons": reasons,
        "category": detect_category(task.description),
        "hours_until_deadline": round(hours_until_deadline, 1)
        if hours_until_deadline is not None else None,
        "is_learned": profile.has_sufficient_data,
    }


# ─── Delay Risk Estimation ────────────────────────────────────────

def estimate_delay_risk(
    task: Task,
    now: datetime,
    profile: UserBehaviorProfile
) -> dict:
    """
    Estimate delay risk for a single task.
    Returns: low / medium / high + explanation.
    """
    if not task.deadline:
        return {
            "risk": "unknown",
            "explanation": "No deadline set — cannot assess delay risk.",
            "is_learned": False,
        }

    hours_until = (task.deadline - now).total_seconds() / 3600

    if hours_until < 0:
        return {
            "risk": "high",
            "explanation": "This task is already overdue.",
            "is_learned": False,
        }

    # Default risk from deadline proximity
    if hours_until <= 6:
        base_risk = "high"
    elif hours_until <= 24:
        base_risk = "medium"
    elif hours_until <= 72:
        base_risk = "low"
    else:
        base_risk = "low"

    if not profile.has_sufficient_data:
        return {
            "risk": base_risk,
            "explanation": (
                f"Based on deadline in {hours_until:.0f}h. "
                f"Not enough history yet — I'll improve this as you use UAILM more."
            ),
            "is_learned": False,
        }

    # Learned adjustment
    cat = detect_category(task.description)
    cat_late_rate = getattr(profile, '_category_late_rates', {}).get(cat, 0.0)
    overall_late_rate = profile.late_completion_rate

    risk_score = 0
    explanation_parts = []

    if cat_late_rate > 0.6:
        risk_score += 2
        explanation_parts.append(
            f"you're often late on {cat} tasks ({cat_late_rate*100:.0f}%)"
        )
    elif cat_late_rate < 0.2:
        risk_score -= 1
        explanation_parts.append(
            f"you handle {cat} tasks reliably"
        )

    if overall_late_rate > 0.5:
        risk_score += 1
        explanation_parts.append(
            f"your overall late rate is {overall_late_rate*100:.0f}%"
        )

    if hours_until <= 6:
        risk_score += 2
    elif hours_until <= 24:
        risk_score += 1

    if risk_score >= 3:
        risk = "high"
    elif risk_score >= 1:
        risk = "medium"
    else:
        risk = "low"

    explanation = f"Due in {hours_until:.0f}h"
    if explanation_parts:
        explanation += ". " + "; ".join(explanation_parts) + "."

    return {
        "risk": risk,
        "explanation": explanation,
        "is_learned": True,
    }


# ─── Workload Analysis ────────────────────────────────────────────

def analyze_workload(
    user_id: int,
    db: Session,
    now: datetime
) -> dict:
    """
    Detect overload situations from real task data.
    """
    pending = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).all()

    total = len(pending)
    high = sum(1 for t in pending if t.priority == "high")
    overdue = sum(
        1 for t in pending
        if t.deadline and t.deadline < now
    )
    due_today = sum(
        1 for t in pending
        if t.deadline and t.deadline.date() == now.date()
        and t.deadline >= now
    )
    due_this_week = sum(
        1 for t in pending
        if t.deadline and now <= t.deadline <= now + timedelta(days=7)
    )

    # Overload detection rules
    warnings = []
    level = "normal"

    if overdue >= 3:
        warnings.append(
            f"You have {overdue} overdue tasks — these need immediate attention."
        )
        level = "high"
    elif overdue >= 1:
        warnings.append(f"{overdue} overdue task(s) need attention.")
        if level == "normal":
            level = "medium"

    if high >= 5:
        warnings.append(
            f"{high} high-priority tasks is a lot — consider reprioritizing."
        )
        level = "high"
    elif high >= 3:
        warnings.append(f"You have {high} high-priority tasks.")
        if level == "normal":
            level = "medium"

    if due_today >= 4:
        warnings.append(
            f"{due_today} tasks are due today — tight schedule ahead."
        )
        if level == "normal":
            level = "medium"

    if total >= 15:
        warnings.append(
            f"You have {total} pending tasks — consider breaking them down."
        )
        if level == "normal":
            level = "medium"

    # Deadline clustering detection
    deadlines_24h = [
        t for t in pending
        if t.deadline and 0 <= (t.deadline - now).total_seconds() / 3600 <= 24
    ]
    if len(deadlines_24h) >= 3:
        warnings.append(
            f"{len(deadlines_24h)} tasks are due within the next 24 hours."
        )
        level = "high"

    return {
        "level": level,
        "total_pending": total,
        "high_priority": high,
        "overdue": overdue,
        "due_today": due_today,
        "due_this_week": due_this_week,
        "warnings": warnings,
        "summary": (
            "Your workload looks manageable." if level == "normal"
            else f"Your workload is {level} — attention needed."
        )
    }


# ─── Focus Recommendations ────────────────────────────────────────

def get_focus_recommendations(
    user_id: int,
    db: Session,
    profile: UserBehaviorProfile,
    top_n: int = 5
) -> dict:
    """
    Return ranked task recommendations with explanations.
    Uses intelligent scoring, not database order.
    """
    now = datetime.now()

    pending = db.query(Task).filter(
        Task.user_id == user_id,
        Task.status == "pending"
    ).all()

    if not pending:
        return {
            "recommendations": [],
            "message": "You have no pending tasks right now. You're all clear! ✨",
            "total_scored": 0,
            "is_learned": profile.has_sufficient_data,
        }

    # Score every task
    scored = [score_task(t, now, profile) for t in pending]
    scored.sort(key=lambda x: x["score"], reverse=True)
    top = scored[:top_n]

    # Add delay risk to top tasks
    task_map = {t.id: t for t in pending}
    for item in top:
        task = task_map.get(item["task_id"])
        if task:
            item["delay_risk"] = estimate_delay_risk(task, now, profile)

    learning_note = (
        "Recommendations based on your task history and behavior patterns."
        if profile.has_sufficient_data
        else f"Using default scoring. Complete {MIN_HISTORY_FOR_LEARNING - profile.data_points} more tasks to unlock personalized recommendations."
    )

    return {
        "recommendations": top,
        "message": learning_note,
        "total_scored": len(scored),
        "is_learned": profile.has_sufficient_data,
        "data_points": profile.data_points,
    }