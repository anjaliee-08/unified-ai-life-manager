import json
import re
from app.services.ollama_provider import OllamaProvider

class NLPService:

    def __init__(self):
        self.ai = OllamaProvider()
        self.system_prompt = """
You are a task extraction AI. Extract tasks from text.
ONLY reply with valid JSON. No explanation. No markdown.

Format:
{
  "tasks": [
    {
      "description": "task description",
      "priority": "high or medium or low",
      "deadline": "YYYY-MM-DD or null"
    }
  ],
  "has_tasks": true
}

Priority rules:
- high = urgent, ASAP, today, tomorrow, strict deadline
- medium = this week, specific date mentioned  
- low = vague, sometime, eventually
"""

    async def extract(self, text: str) -> dict:
        if not await self.ai.is_available():
            return {
                "has_tasks": False,
                "tasks": [],
                "error": "Ollama offline. Run: ollama serve"
            }

        try:
            response = await self.ai.generate(
                prompt=f"Extract tasks from:\n{text}",
                system_prompt=self.system_prompt,
                temperature=0.1
            )
            cleaned = re.sub(r'```json|```', '', response).strip()
            return json.loads(cleaned)
        except json.JSONDecodeError:
            return {"has_tasks": False, "tasks": [], "error": "AI returned invalid JSON"}
        except ConnectionError as e:
            return {"has_tasks": False, "tasks": [], "error": str(e)}