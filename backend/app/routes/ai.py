from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from app.services.ollama_provider import OllamaProvider
from app.services.nlp_service import NLPService
from app.services.chat_service import ChatService

router = APIRouter()
ollama = OllamaProvider()
nlp = NLPService()
chat_service = ChatService()

@router.get("/status")
async def status():
    online = await ollama.is_available()
    return {
        "status": "online" if online else "offline",
        "model": ollama.model,
        "tip": None if online else "Run: ollama serve"
    }

class ChatRequest(BaseModel):
    message: str

@router.post("/chat")
async def chat(req: ChatRequest):
    response = await chat_service.chat(req.message)
    return {"response": response}

@router.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    async def generate():
        async for token in chat_service.chat_stream(req.message):
            yield f"data: {token}\n\n"
    return StreamingResponse(generate(), media_type="text/event-stream")

class ExtractRequest(BaseModel):
    text: str

@router.post("/extract")
async def extract(req: ExtractRequest):
    result = await nlp.extract(req.text)
    return result