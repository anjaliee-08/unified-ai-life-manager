"""
SMS Intelligence Service — UAILM Phase 5A

Responsibilities:
  - Analyze SMS messages using local Ollama/Qwen
  - Extract structured information (type, title, date, amount, etc.)
  - Return informational extractions ONLY — no task/event creation
  - Sender identity comes from MessageModel.sender (contact-resolved),
    NEVER inferred from message body

Reuses:
  - OllamaProvider (same as email_intelligence_service)
  - JSON extraction + cleanup pattern (same as email_intelligence_service)
  - Confidence scoring constants (same thresholds)

Phase 5B (SMS → Task) and 5C (SMS → Calendar) are NOT implemented here.
"""

import json
import re
from datetime import datetime
from typing import Optional
from app.services.ollama_provider import OllamaProvider

ollama = OllamaProvider()

# ── Confidence thresholds (reused from email_intelligence_service) ──
CONFIDENCE_HIGH   = 0.80
CONFIDENCE_MEDIUM = 0.50
CONFIDENCE_LOW    = 0.30
SHOW_THRESHOLD    = 0.40  # below this, skip showing extraction

# ── SMS types ──────────────────────────────────────────────────────
SMS_TYPES = [
    "TASK", "EVENT", "MEETING", "APPOINTMENT", "REMINDER",
    "DEADLINE", "BILL", "PAYMENT", "TRANSACTION", "DELIVERY",
    "OTP", "INFORMATION", "OTHER"
]

# ── Extraction prompt ──────────────────────────────────────────────
SMS_EXTRACTION_PROMPT = """You are an SMS intelligence extraction AI.

Your job is to analyze SMS messages and extract structured information.

TODAY'S DATE will be provided in the user message. Use it to understand relative dates.

SENDER IDENTITY RULE — THIS IS CRITICAL:
The sender name is provided separately. You must NEVER infer or change the sender
from the message body. For example:
  Sender: JK-SBIUPI-S
  Body: "Your account was credited by ADITYA YADAV"
  → The sender is "JK-SBIUPI-S", NOT "Aditya Yadav".
  → "ADITYA YADAV" in the body is just content — not the sender.

SMS TYPES you must classify into:
  TASK        - something the user must do ("submit", "complete", "send", "register")
  EVENT       - an event happening ("meeting at 5 PM", "event tomorrow")
  MEETING     - a specific meeting/call
  APPOINTMENT - a scheduled appointment (doctor, bank, etc.)
  REMINDER    - a general reminder ("don't forget", "reminder:")
  DEADLINE    - a deadline/due date without a specific task
  BILL        - a bill/invoice/utility due ("electricity bill due")
  PAYMENT     - a payment required
  TRANSACTION - a financial transaction (credit/debit/UPI)
  DELIVERY    - a package/courier delivery
  OTP         - a one-time password or verification code
  INFORMATION - general informational message with no action needed
  OTHER       - does not fit any above category

RULES:
1. Extract ONLY what is explicitly stated in the message. Never hallucinate.
2. Preserve relative dates as-is ("tomorrow", "Monday") — do not convert them.
3. For OTP messages: type = OTP, do NOT include the OTP value in the output.
4. confidence = how clearly the SMS supports the extraction (0.0 to 1.0).
5. Fields that do not apply must be null — never invent values.
6. If the message is purely promotional with no useful information, use INFORMATION.
7. amount must be a number (no currency symbol) or null.

Reply with ONLY valid JSON. No explanation. No markdown. No code blocks.

{
  "type": "ONE_OF_THE_TYPES_ABOVE",
  "title": "short title or null",
  "description": "brief description or null",
  "date": "date string from message or null",
  "time": "time string from message or null",
  "deadline": "deadline phrase from message or null",
  "due_date": "due date phrase from message or null",
  "amount": null,
  "transaction_type": "credit or debit or null",
  "confidence": 0.95
}"""


# ── Core extraction ────────────────────────────────────────────────

async def analyze_sms(
    message_data: dict,
    now: Optional[datetime] = None,
) -> dict:
    """
    Analyze a single SMS message and return structured extraction.

    message_data keys (from MessageModel.toJson()):
      id, sender, address, snippet, timestamp, is_read,
      is_incoming, is_today, time_string

    IMPORTANT: sender comes from contact-resolved MessageModel.sender.
    This function never infers sender from message body.

    Returns extraction dict with message_id and sender attached.
    """
    if now is None:
        now = datetime.now()

    message_id = message_data.get('id', '')
    # Sender from contact resolution — not from body
    sender = message_data.get('sender', 'Unknown')
    snippet = message_data.get('snippet', '')
    time_str = message_data.get('time_string', '')

    if not snippet.strip():
        return _empty_result(message_id, sender, "Empty message")

    if not await ollama.is_available():
        return _error_result(
            message_id, sender,
            "AI offline — cannot analyze message"
        )

    today_str = now.strftime("%B %d, %Y (%A)")

    prompt = (
        f"Today is {today_str}.\n\n"
        f"Analyze this SMS message:\n\n"
        f"Sender: {sender}\n"
        f"Message: {snippet}\n\n"
        f"Extract structured information. Reply with JSON only."
    )

    try:
        raw = await ollama.generate(
            prompt=prompt,
            system_prompt=SMS_EXTRACTION_PROMPT,
            temperature=0.1,
        )

        cleaned = re.sub(r'```json|```', '', raw).strip()
        result = json.loads(cleaned)

        # Validate type
        sms_type = result.get('type', 'OTHER')
        if sms_type not in SMS_TYPES:
            sms_type = 'OTHER'

        confidence = float(result.get('confidence', 0.5))

        return {
            "message_id": message_id,
            # Sender always from MessageModel — never from body
            "sender": sender,
            "type": sms_type,
            "title": result.get('title'),
            "description": result.get('description'),
            "date": result.get('date'),
            "time": result.get('time'),
            "deadline": result.get('deadline'),
            "due_date": result.get('due_date'),
            # OTP value deliberately excluded from output
            "amount": result.get('amount'),
            "transaction_type": result.get('transaction_type'),
            "confidence": round(confidence, 2),
            "confidence_label": _confidence_label(confidence),
            "original_snippet": snippet,
        }

    except json.JSONDecodeError as e:
        # Log for developer, do not crash
        import logging
        logging.getLogger("uvicorn").warning(
            f"SMS extraction JSON parse error for msg {message_id}: {e}"
        )
        return _error_result(message_id, sender, "AI returned invalid JSON")

    except Exception as e:
        return _error_result(message_id, sender, str(e))


async def analyze_sms_batch(
    messages: list,
    now: Optional[datetime] = None,
) -> list:
    """
    Analyze a list of SMS messages individually.
    Returns extractions above SHOW_THRESHOLD confidence.
    Each message is analyzed separately — never combined.
    """
    if now is None:
        now = datetime.now()

    results = []
    for msg in messages:
        extraction = await analyze_sms(msg, now)
        # Include if above threshold AND not an error result
        if (
            extraction.get('confidence', 0) >= SHOW_THRESHOLD
            and not extraction.get('error')
        ):
            results.append(extraction)

    return results


# ── Helpers ────────────────────────────────────────────────────────

def _confidence_label(confidence: float) -> str:
    if confidence >= CONFIDENCE_HIGH:
        return "high"
    if confidence >= CONFIDENCE_MEDIUM:
        return "medium"
    return "low"


def _empty_result(
    message_id: str, sender: str, reason: str
) -> dict:
    return {
        "message_id": message_id,
        "sender": sender,
        "type": "INFORMATION",
        "title": None,
        "description": reason,
        "date": None, "time": None,
        "deadline": None, "due_date": None,
        "amount": None, "transaction_type": None,
        "confidence": 0.0,
        "confidence_label": "low",
        "original_snippet": "",
    }


def _error_result(
    message_id: str, sender: str, error: str
) -> dict:
    return {
        "message_id": message_id,
        "sender": sender,
        "type": "OTHER",
        "title": None,
        "description": None,
        "date": None, "time": None,
        "deadline": None, "due_date": None,
        "amount": None, "transaction_type": None,
        "confidence": 0.0,
        "confidence_label": "low",
        "original_snippet": "",
        "error": error,
    }