from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os

# Prefer env var for production; fallback to local sqlite file
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./relic_archive.db")

# Some distro Python builds ship an older pysqlite that does not support
# 'check_same_thread' or newer connect() kwargs. We try a safe fallback.
def _build_engine(url: str):
    if url.startswith("sqlite"):
        try:
            return create_engine(url, connect_args={"check_same_thread": False})
        except TypeError:
            # Older pysqlite without this kwarg; fall back without it
            return create_engine(url)
    return create_engine(url)

engine = _build_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
