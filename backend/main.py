from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Body, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Optional
import os
from dotenv import load_dotenv
from datetime import datetime, timedelta
from pathlib import Path
import shutil
import threading
import time
import uuid
from fastapi.security import OAuth2PasswordRequestForm
from . import models, schemas, database, auth
from .ai_providers import generate_description as ai_generate_description, classify_item as ai_classify_item

load_dotenv()

models.Base.metadata.create_all(bind=database.engine)

app = FastAPI(title="Relic Archive API", description="Backend for Relic Archive App")

# --- Auth Routes ---

@app.post("/token", response_model=schemas.Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.email == form_data.username).first()
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/users/", response_model=schemas.User)
def create_user(user: schemas.UserCreate, db: Session = Depends(database.get_db)):
    db_user = db.query(models.User).filter(models.User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    hashed_password = auth.get_password_hash(user.password)
    db_user = models.User(email=user.email, hashed_password=hashed_password)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@app.get("/users/me/", response_model=schemas.User)
async def read_users_me(current_user: models.User = Depends(auth.get_current_user)):
    return current_user

# --- Simple Background Task Queue (Mocking Celery/RQ) ---
class TaskQueue:
    def __init__(self):
        self.queue = []
        self.lock = threading.Lock()
        self.worker_thread = threading.Thread(target=self._worker, daemon=True)
        self.worker_thread.start()

    def add_task(self, task_id: str, item_id: str, image_dir: Path):
        with self.lock:
            self.queue.append({"id": task_id, "item_id": item_id, "dir": image_dir})

    def _worker(self):
        while True:
            task = None
            with self.lock:
                if self.queue:
                    task = self.queue.pop(0)
            
            if task:
                self._process_task(task)
            else:
                time.sleep(1)

    def _process_task(self, task):
        task_id = task["id"]
        item_id = task["item_id"]
        print(f"Starting task {task_id} for item {item_id}...")
        
        db = database.SessionLocal()
        try:
            db_task = db.query(models.ReconstructionTask).filter(models.ReconstructionTask.id == task_id).first()
            if not db_task:
                return

            db_task.status = "processing"
            db_task.progress = "10%"
            db_task.message = "Initializing reconstruction..."
            db.commit()

            # Mock COLMAP stages
            stages = [
                ("20%", "Feature extraction..."),
                ("40%", "Feature matching..."),
                ("60%", "Sparse reconstruction..."),
                ("80%", "Dense reconstruction..."),
                ("90%", "Meshing and texturing..."),
            ]

            for progress, msg in stages:
                time.sleep(2) # Simulate work
                db_task.progress = progress
                db_task.message = msg
                db.commit()

            # Finalize
            time.sleep(1)
            
            # Use test model as result
            project_root = base_dir.parent
            test_model_src = project_root / "test_model.gltf"
            target_model_name = f"{task_id}_model.gltf"
            target_model_path = upload_dir / target_model_name
            
            final_path = None
            if test_model_src.exists():
                shutil.copy(test_model_src, target_model_path)
                final_path = f"/uploads/{target_model_name}"
            
            db_task.status = "completed"
            db_task.progress = "100%"
            db_task.message = "Reconstruction finished successfully."
            db_task.model_path = final_path
            
            # Auto-update item if success
            if final_path:
                db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
                if db_item:
                    db_item.model_path = final_path
            
            db.commit()
            print(f"Task {task_id} completed.")

        except Exception as e:
            print(f"Task {task_id} failed: {e}")
            if db_task:
                db_task.status = "failed"
                db_task.message = str(e)
                db.commit()
        finally:
            db.close()

task_queue = TaskQueue()

def _ensure_items_events_column():
    engine = database.engine
    if not engine.url.drivername.startswith("sqlite"):
        return
    with engine.connect() as conn:
        cols = conn.execute(text("PRAGMA table_info(items)")).fetchall()
        names = {row[1] for row in cols}
        if "events" not in names:
            conn.execute(text("ALTER TABLE items ADD COLUMN events TEXT"))
        if "model_path" not in names:
            conn.execute(text("ALTER TABLE items ADD COLUMN model_path VARCHAR"))
        if "video_path" not in names:
            conn.execute(text("ALTER TABLE items ADD COLUMN video_path VARCHAR"))
        # Ensure collections.items column
        cols_c = conn.execute(text("PRAGMA table_info(collections)")).fetchall()
        names_c = {row[1] for row in cols_c}
        if "items" not in names_c:
            conn.execute(text("ALTER TABLE collections ADD COLUMN items TEXT"))
        if "is_private" not in names_c:
            conn.execute(text("ALTER TABLE collections ADD COLUMN is_private INTEGER DEFAULT 1"))
        if "created_at" not in names_c:
            conn.execute(text("ALTER TABLE collections ADD COLUMN created_at DATETIME"))
        if "updated_at" not in names_c:
            conn.execute(text("ALTER TABLE collections ADD COLUMN updated_at DATETIME"))
        cols_c2 = conn.execute(text("PRAGMA table_info(collections)")).fetchall()
        names_c2 = {row[1] for row in cols_c2}
        if "created_at" in names_c2:
            conn.execute(text("UPDATE collections SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL"))
        if "updated_at" in names_c2:
            conn.execute(text("UPDATE collections SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"))
        conn.commit()

_ensure_items_events_column()

base_dir = Path(__file__).resolve().parent
upload_dir = base_dir / "uploads"
upload_dir.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(upload_dir)), name="uploads")

public_dir = base_dir / "public"
public_dir.mkdir(parents=True, exist_ok=True)
app.mount("/public", StaticFiles(directory=str(public_dir), html=True), name="public")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    db = database.SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/")
async def root():
    return {"message": "Welcome to Relic Archive API"}

@app.get("/privacy")
def privacy_redirect():
    return RedirectResponse(url="/public/privacy.html")

@app.get("/support")
def support_redirect():
    return RedirectResponse(url="/public/support.html")

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/items/", response_model=schemas.Item)
def create_item(item: schemas.ItemCreate, db: Session = Depends(get_db)):
    db_item = models.Item(**item.model_dump(mode="json"))
    if not db_item.events:
        db_item.events = [{"at": datetime.utcnow().isoformat(), "title": "创建档案"}]
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item

@app.patch("/items/{item_id}", response_model=schemas.Item)
def update_item(item_id: str, item: schemas.ItemUpdate, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    
    update_data = item.model_dump(exclude_unset=True, mode="json")
    for key, value in update_data.items():
        setattr(db_item, key, value)
    
    db.commit()
    db.refresh(db_item)
    return db_item

@app.post("/upload/model/")
async def upload_model(file: UploadFile = File(...)):
    filename = f"{uuid.uuid4()}_{file.filename}"
    file_path = upload_dir / filename
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"path": f"/uploads/{filename}"}

@app.post("/items/{item_id}/reconstruct", response_model=schemas.Task)
async def reconstruct_item_model(item_id: str, files: List[UploadFile] = File(...), db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")

    # 1. Save uploaded images (for future real reconstruction)
    task_id = str(uuid.uuid4())
    task_dir = upload_dir / "reconstruction" / task_id
    task_dir.mkdir(parents=True, exist_ok=True)

    for file in files:
        file_path = task_dir / file.filename
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

    # 2. Create Task Record
    db_task = models.ReconstructionTask(
        id=task_id,
        item_id=item_id,
        status="pending",
        progress="0%",
        message="Queued for reconstruction"
    )
    db.add(db_task)
    db.commit()
    db.refresh(db_task)

    # 3. Add to Queue
    task_queue.add_task(task_id, item_id, task_dir)

    return db_task

@app.get("/tasks/{task_id}", response_model=schemas.Task)
def get_task_status(task_id: str, db: Session = Depends(get_db)):
    db_task = db.query(models.ReconstructionTask).filter(models.ReconstructionTask.id == task_id).first()
    if db_task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return db_task

@app.get("/tasks/", response_model=List[schemas.Task])
def list_tasks(item_id: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(models.ReconstructionTask)
    if item_id:
        q = q.filter(models.ReconstructionTask.item_id == item_id)
    tasks = q.all()
    tasks.sort(key=lambda t: t.created_at, reverse=True)
    return tasks

@app.post("/collections/", response_model=schemas.Collection)
def create_collection(payload: schemas.CollectionCreate, db: Session = Depends(get_db)):
    col = models.Collection(
        name=payload.name,
        description=payload.description,
        theme=payload.theme,
        items=[],
        is_private=payload.is_private if payload.is_private is not None else True,
    )
    db.add(col)
    db.commit()
    db.refresh(col)
    return col

@app.get("/collections/", response_model=List[schemas.Collection])
def list_collections(db: Session = Depends(get_db)):
    cols = db.query(models.Collection).all()
    cols.sort(key=lambda c: c.created_at, reverse=True)
    return cols

@app.get("/collections/{collection_id}", response_model=schemas.Collection)
def get_collection(collection_id: str, db: Session = Depends(get_db)):
    col = db.query(models.Collection).filter(models.Collection.id == collection_id).first()
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return col

@app.patch("/collections/{collection_id}", response_model=schemas.Collection)
def update_collection(collection_id: str, payload: schemas.CollectionUpdate, db: Session = Depends(get_db)):
    col = db.query(models.Collection).filter(models.Collection.id == collection_id).first()
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    data = payload.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(col, k, v)
    db.commit()
    db.refresh(col)
    return col

@app.post("/collections/{collection_id}/items", response_model=schemas.Collection)
def add_collection_item(collection_id: str, payload: dict, db: Session = Depends(get_db)):
    item_id = payload.get("item_id")
    if not item_id:
        raise HTTPException(status_code=400, detail="Missing item_id")
    col = db.query(models.Collection).filter(models.Collection.id == collection_id).first()
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    items = list(col.items or [])
    if item_id not in items:
        items.append(item_id)
    col.items = items
    db.commit()
    db.refresh(col)
    return col

@app.delete("/collections/{collection_id}/items/{item_id}", response_model=schemas.Collection)
def remove_collection_item(collection_id: str, item_id: str, db: Session = Depends(get_db)):
    col = db.query(models.Collection).filter(models.Collection.id == collection_id).first()
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    items = list(col.items or [])
    items = [i for i in items if i != item_id]
    col.items = items
    db.commit()
    db.refresh(col)
    return col

@app.get("/collections/{collection_id}/items", response_model=List[schemas.Item])
def list_collection_items(collection_id: str, db: Session = Depends(get_db)):
    col = db.query(models.Collection).filter(models.Collection.id == collection_id).first()
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    items = db.query(models.Item).filter(models.Item.id.in_(col.items or [])).all()
    return items
@app.post("/items/{item_id}/reconstruct_from_existing", response_model=schemas.Item)
async def reconstruct_item_from_existing(item_id: str, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    # Ensure there are existing images
    if not db_item.image_paths or len(db_item.image_paths) == 0:
        raise HTTPException(status_code=400, detail="No existing images to reconstruct from")
    # Simulate processing time
    import time
    time.sleep(2)
    # Copy test model to uploads and set model_path
    task_id = str(uuid.uuid4())
    project_root = base_dir.parent
    test_model_src = project_root / "test_model.gltf"
    target_model_name = f"{task_id}_model.gltf"
    target_model_path = upload_dir / target_model_name
    if test_model_src.exists():
        shutil.copy(test_model_src, target_model_path)
        db_item.model_path = f"/uploads/{target_model_name}"
    db.commit()
    db.refresh(db_item)
    return db_item

@app.post("/items/{item_id}/describe", response_model=schemas.Item)
def describe_item(item_id: str, style: Optional[str] = Body(None, embed=True), db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    desc, meta = ai_generate_description(
        {
            "title": db_item.title,
            "image_paths": db_item.image_paths,
        },
        style,
    )
    summary = desc
    if db_item.image_paths:
        summary += f"\n\n（已关联 {len(db_item.image_paths)} 张影像记录）"
    db_item.description = summary
    existing_meta = dict(db_item.ai_metadata or {})
    existing_meta.update(meta)
    db_item.ai_metadata = existing_meta
    
    db.commit()
    db.refresh(db_item)
    return db_item

@app.post("/items/{item_id}/classify", response_model=schemas.Item)
def classify_item(item_id: str, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    cat, tags = ai_classify_item(
        {
            "title": db_item.title,
            "tags": db_item.tags,
            "ai_metadata": db_item.ai_metadata,
        }
    )
    current_tags = set(db_item.tags or [])
    for t in tags:
        current_tags.add(t)
    db_item.category = cat
    db_item.tags = list(current_tags)
    
    db.commit()
    db.refresh(db_item)
    return db_item

@app.get("/items/", response_model=List[schemas.Item])
def read_items(
    skip: int = 0,
    limit: int = 100,
    q: Optional[str] = None,
    tag: Optional[str] = None,
    mood: Optional[str] = None,
    category: Optional[str] = None,
    sort: str = "created_desc",
    db: Session = Depends(get_db),
):
    query = db.query(models.Item)
    
    # Pre-fetch all for in-memory filtering (SQLite basic search)
    # In production with Postgres/PGVector, we would do this in SQL.
    items = query.all()
    
    if q:
        search_term = q.strip().lower()
        if search_term:
            def _hit(item: models.Item) -> bool:
                title = (item.title or "").lower()
                desc = (item.description or "").lower()
                cat = (item.category or "").lower()
                tags = " ".join(item.tags or []).lower()
                mood_value = str((item.ai_metadata or {}).get("mood") or "").lower()
                return (
                    search_term in title
                    or search_term in desc
                    or search_term in cat
                    or search_term in tags
                    or search_term in mood_value
                )
            items = [i for i in items if _hit(i)]
            
    if tag:
        items = [i for i in items if tag in (i.tags or [])]
    
    if mood:
        items = [i for i in items if (i.ai_metadata or {}).get("mood") == mood]
        
    if category:
        items = [i for i in items if i.category == category]

    if sort == "created_asc":
        items.sort(key=lambda i: i.created_at)
    else:
        items.sort(key=lambda i: i.created_at, reverse=True)
        
    # Manual pagination after filtering
    start = skip
    end = skip + limit
    return items[start:end]

@app.get("/items/{item_id}", response_model=schemas.Item)
def read_item(item_id: str, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return db_item
 
@app.patch("/items/{item_id}", response_model=schemas.Item)
def update_item(item_id: str, payload: schemas.ItemUpdate, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    data = payload.model_dump(exclude_unset=True, mode="json")
    for k, v in data.items():
        setattr(db_item, k, v)
    db.commit()
    db.refresh(db_item)
    return db_item
 
@app.post("/items/{item_id}/images", response_model=schemas.Item)
def append_item_image(item_id: str, payload: dict, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    url = payload.get("url")
    if not url:
        raise HTTPException(status_code=400, detail="Missing url")
    current = list(db_item.image_paths or [])
    current.append(url)
    db_item.image_paths = current
    db.commit()
    db.refresh(db_item)
    return db_item

@app.post("/items/{item_id}/events", response_model=schemas.Item)
def append_item_event(
    item_id: str,
    payload: schemas.ItemEventCreate,
    db: Session = Depends(get_db),
):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    at = payload.at or datetime.utcnow()
    events = list(db_item.events or [])
    events.append({"at": at.isoformat(), "title": payload.title, "note": payload.note, "audio_url": payload.audio_url, "type": payload.type})
    db_item.events = events
    db.commit()
    db.refresh(db_item)
    return db_item

@app.post("/upload/audio/")
async def upload_audio(file: UploadFile = File(...)):
    content_type = file.content_type or ""
    if not content_type.startswith("audio/"):
        # Fallback check extension
        ext = Path(file.filename or "").suffix.lower()
        if ext not in [".mp3", ".wav", ".m4a", ".aac"]:
            raise HTTPException(status_code=400, detail="File must be an audio")
    suffix = Path(file.filename or "").suffix or ".m4a"
    unique_filename = f"{uuid.uuid4()}{suffix}"
    file_path = upload_dir / unique_filename
    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": unique_filename, "url": f"/uploads/{unique_filename}"}

@app.post("/upload/video/")
async def upload_video(file: UploadFile = File(...)):
    content_type = file.content_type or ""
    if not content_type.startswith("video/"):
        # Fallback check extension
        ext = Path(file.filename or "").suffix.lower()
        if ext not in [".mp4", ".mov", ".avi", ".mkv"]:
            raise HTTPException(status_code=400, detail="File must be a video")
    suffix = Path(file.filename or "").suffix or ".mp4"
    unique_filename = f"{uuid.uuid4()}{suffix}"
    file_path = upload_dir / unique_filename
    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": unique_filename, "url": f"/uploads/{unique_filename}"}

@app.delete("/items/{item_id}/events/{idx}", response_model=schemas.Item)
def delete_item_event(item_id: str, idx: int, db: Session = Depends(get_db)):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    events = list(db_item.events or [])
    if idx < 0 or idx >= len(events):
        raise HTTPException(status_code=400, detail="Invalid event index")
    del events[idx]
    db_item.events = events
    db.commit()
    db.refresh(db_item)
    return db_item

@app.patch("/items/{item_id}/events/{idx}", response_model=schemas.Item)
def update_item_event(
    item_id: str,
    idx: int,
    payload: schemas.ItemEventUpdate,
    db: Session = Depends(get_db),
):
    db_item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if db_item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    events = list(db_item.events or [])
    if idx < 0 or idx >= len(events):
        raise HTTPException(status_code=400, detail="Invalid event index")
    current = events[idx]
    at = payload.at or datetime.fromisoformat(current.get("at"))
    title = payload.title
    if title is None or not title.strip():
        title = current.get("title")
    note = payload.note if payload.note is not None else current.get("note")
    audio_url = payload.audio_url if payload.audio_url is not None else current.get("audio_url")
    ev_type = payload.type if payload.type is not None else current.get("type")
    events[idx] = {"at": at.isoformat(), "title": title, "note": note, "audio_url": audio_url, "type": ev_type}
    db_item.events = events
    db.commit()
    db.refresh(db_item)
    return db_item

@app.post("/upload/")
async def upload_file(file: UploadFile = File(...)):
    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        # Fallback check extension
        ext = Path(file.filename or "").suffix.lower()
        if ext not in [".jpg", ".jpeg", ".png", ".gif", ".webp"]:
            raise HTTPException(status_code=400, detail="File must be an image")

    suffix = Path(file.filename or "").suffix
    if not suffix:
        suffix = ".jpg"
    unique_filename = f"{uuid.uuid4()}{suffix}"
    file_path = upload_dir / unique_filename

    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    return {"filename": unique_filename, "url": f"/uploads/{unique_filename}"}
