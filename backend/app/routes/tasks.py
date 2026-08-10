from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from app.database import get_db
from app.models.task import Task

router = APIRouter()

class TaskCreate(BaseModel):
    user_id: int
    description: str
    priority: Optional[str] = "medium"
    source: Optional[str] = "manual"

class TaskResponse(BaseModel):
    id: int
    user_id: int
    description: str
    priority: str
    status: str
    source: str
    
    class Config:
        from_attributes = True

@router.post("/", response_model=TaskResponse)
def create_task(task: TaskCreate, db: Session = Depends(get_db)):
    new_task = Task(**task.model_dump())
    db.add(new_task)
    db.commit()
    db.refresh(new_task)
    return new_task

@router.get("/user/{user_id}", response_model=list[TaskResponse])
def get_user_tasks(user_id: int, db: Session = Depends(get_db)):
    return db.query(Task).filter(Task.user_id == user_id).all()

@router.patch("/{task_id}/status")
def update_status(task_id: int, status: str, db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    task.status = status
    db.commit()
    return {"message": "Updated", "task_id": task_id, "status": status}