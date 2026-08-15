from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base
from app.routes import auth, tasks, ai
from app.routes import agent
from app.routes import intelligence
from app.routes import calendar as calendar_router
from app.routes import email_route
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="UAILM API",
    description="Unified AI Life Manager — Powered by Local AI",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/auth", tags=["Auth"])
app.include_router(tasks.router, prefix="/api/tasks", tags=["Tasks"])
app.include_router(ai.router, prefix="/api/ai", tags=["AI"])
app.include_router(agent.router, prefix="/api/agent", tags=["Agent"])
app.include_router(
    intelligence.router,
    prefix="/api/intelligence",
    tags=["Intelligence"]
)
app.include_router(
    calendar_router.router,
    prefix="/api/calendar",
    tags=["Calendar"]
)
app.include_router(
    email_route.router,
    prefix="/api/email",
    tags=["Email"]
)

@app.get("/")
async def root():
    return {"app": "UAILM", "status": "running"}

@app.get("/health")
async def health():
    return {"status": "healthy"}