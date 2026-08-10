from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "sqlite:///./uailm.db"
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "qwen2.5:3b"
    ollama_timeout: int = 60
    app_name: str = "Unified AI Life Manager"
    debug: bool = True

    class Config:
        env_file = ".env"

settings = Settings()