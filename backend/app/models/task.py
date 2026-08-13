from sqlalchemy import Column, Integer, String, DateTime, Float, ForeignKey
from sqlalchemy.sql import func
from app.database import Base

class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    description = Column(String, nullable=False)
    deadline = Column(DateTime, nullable=True)
    priority = Column(String, default="medium")  # high/medium/low
    status = Column(String, default="pending")   # pending/done/dismissed
    source = Column(String, default="manual")    # email/message/manual
    confidence = Column(Float, default=1.0)      # AI confidence score
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    completed_at = Column(DateTime, nullable=True)