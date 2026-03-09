from sqlalchemy import Column, String, Text, JSON, DateTime, Boolean
from datetime import datetime
import uuid
from .database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Item(Base):
    __tablename__ = "items"

    id = Column(String, primary_key=True, default=generate_uuid, index=True)
    title = Column(String, index=True, nullable=True)
    image_paths = Column(JSON, default=list)
    description = Column(Text, nullable=True)
    ai_metadata = Column(JSON, nullable=True)
    tags = Column(JSON, default=list)
    category = Column(String, index=True, nullable=True)
    events = Column(JSON, default=list)
    model_path = Column(String, nullable=True)
    video_path = Column(String, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    is_active = Column(Boolean, default=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)


class ReconstructionTask(Base):
    __tablename__ = "reconstruction_tasks"

    id = Column(String, primary_key=True, default=generate_uuid, index=True)
    item_id = Column(String, index=True)
    status = Column(String, default="pending") # pending, processing, completed, failed
    progress = Column(String, default="0%")
    message = Column(String, nullable=True)
    model_path = Column(String, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class Collection(Base):
    __tablename__ = "collections"

    id = Column(String, primary_key=True, default=generate_uuid, index=True)
    name = Column(String, index=True)
    description = Column(Text, nullable=True)
    theme = Column(String, nullable=True)
    items = Column(JSON, default=list)
    is_private = Column(Boolean, default=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
