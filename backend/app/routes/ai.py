from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from app.services.ollama_provider import OllamaProvider

router = APIRouter()
ollama = OllamaProvider()

@router.get("/status")
async def ai_status():
    is_online = await ollama.is_available()
    return {
        "status": "online" if is_online else "offline",
        "model": ollama.model,
        "message": None if is_online else "Run: ollama serve"
    }

class ChatRequest(BaseModel):
    message: str

@router.post("/chat")
async def chat(req: ChatRequest):
    if not await ollama.is_available():
        return {"response": "⚠️ AI offline. Run: ollama serve"}
    response = await ollama.generate(
        prompt=req.message,
        system_prompt="You are UAILM, a helpful AI life manager assistant. Be concise and helpful."
    )
    return {"response": response}

@router.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    async def generate():
        async for token in ollama.generate_stream(
            prompt=req.message,
            system_prompt="You are UAILM, a helpful AI life manager. Be concise."
        ):
            yield f"data: {token}\n\n"
    return StreamingResponse(generate(), media_type="text/event-stream")

class ExtractRequest(BaseModel):
    text: str

@router.post("/extract")
async def extract_tasks(req: ExtractRequest):
    if not await ollama.is_available():
        return {"error": "AI offline", "tasks": []}
    
    response = await ollama.generate(
        prompt=f"Extract tasks from this text. Reply JSON only:\n{req.text}",
        system_prompt='You extract tasks from text. Always reply with valid JSON: {"tasks": [{"description": "...", "priority": "high/medium/low", "deadline": "date or null"}]}',
        temperature=0.1
    )
    return {"raw": response}