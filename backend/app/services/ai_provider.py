from abc import ABC, abstractmethod
from typing import AsyncGenerator, Optional

class AIProvider(ABC):
    
    @abstractmethod
    async def generate(self, prompt: str, system_prompt: Optional[str] = None, temperature: float = 0.7) -> str:
        pass
    
    @abstractmethod
    async def generate_stream(self, prompt: str, system_prompt: Optional[str] = None) -> AsyncGenerator[str, None]:
        pass
    
    @abstractmethod
    async def is_available(self) -> bool:
        pass