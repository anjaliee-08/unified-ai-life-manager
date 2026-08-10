from app.services.ollama_provider import OllamaProvider
from typing import AsyncGenerator

class ChatService:

    def __init__(self):
        self.ai = OllamaProvider()
        self.system_prompt = """
You are UAILM, an intelligent personal life manager assistant.
Help users manage tasks, deadlines and schedules.
Be concise, friendly and actionable.
Keep responses under 100 words unless asked for more detail.
"""

    async def chat(self, message: str) -> str:
        if not await self.ai.is_available():
            return "⚠️ AI is offline. Please run: ollama serve"
        return await self.ai.generate(
            prompt=message,
            system_prompt=self.system_prompt,
            temperature=0.7
        )

    async def chat_stream(self, message: str) -> AsyncGenerator[str, None]:
        if not await self.ai.is_available():
            yield "⚠️ AI is offline. Run: ollama serve"
            return
        async for token in self.ai.generate_stream(
            prompt=message,
            system_prompt=self.system_prompt
        ):
            yield token