from pydantic import BaseModel, field_validator
from typing import List, Optional, Dict, Any
from datetime import datetime

# --- Item Schemas ---

class ItemBase(BaseModel):
    title: Optional[str] = None
    category: Optional[str] = None
    tags: List[str] = []
    description: Optional[str] = None
    model_path: Optional[str] = None
    video_path: Optional[str] = None

class ItemEvent(BaseModel):
    at: datetime
    title: str
    note: Optional[str] = None
    audio_url: Optional[str] = None
    type: Optional[str] = None

class ItemEventCreate(BaseModel):
    at: Optional[datetime] = None
    title: str
    note: Optional[str] = None
    audio_url: Optional[str] = None
    type: Optional[str] = None

class ItemEventUpdate(BaseModel):
    at: Optional[datetime] = None
    title: Optional[str] = None
    note: Optional[str] = None
    audio_url: Optional[str] = None
    type: Optional[str] = None

class ItemCreate(ItemBase):
    image_paths: List[str] = []
    ai_metadata: Optional[Dict[str, Any]] = None
    events: List[ItemEvent] = []

class ItemUpdate(ItemBase):
    ai_metadata: Optional[Dict[str, Any]] = None
    image_paths: Optional[List[str]] = None
    events: Optional[List[ItemEvent]] = None

class Item(ItemBase):
    id: str
    image_paths: List[str] = []
    ai_metadata: Optional[Dict[str, Any]] = None
    events: List[ItemEvent] = []
    model_path: Optional[str] = None
    video_path: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    @field_validator("events", mode="before")
    @classmethod
    def _events_default(cls, v):
        return v or []

    class Config:
        from_attributes = True

# --- Task Schemas ---

class TaskBase(BaseModel):
    item_id: str
    status: str
    progress: str
    message: Optional[str] = None
    model_path: Optional[str] = None

class Task(TaskBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# --- Collection Schemas ---

class CollectionBase(BaseModel):
    name: str
    description: Optional[str] = None
    theme: Optional[str] = None
    is_private: Optional[bool] = True

class CollectionCreate(CollectionBase):
    pass

class CollectionUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    theme: Optional[str] = None
    is_private: Optional[bool] = None

class Collection(CollectionBase):
    id: str
    items: List[str] = []
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# --- User Schemas ---

class UserBase(BaseModel):
    email: str

class UserCreate(UserBase):
    password: str

class User(UserBase):
    id: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    email: Optional[str] = None