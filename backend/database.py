from sqlalchemy import create_engine, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
import sqlite3

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./relic_archive.db")

# Global monkey patch for old pysqlite create_function signature
_patched_cf = getattr(sqlite3, "_ra_cf_patched", False)
if not _patched_cf and hasattr(sqlite3, "Connection") and hasattr(sqlite3.Connection, "create_function"):
    _orig_cf = sqlite3.Connection.create_function
    def _wrapped_cf(self, name, num_params, func, *args, **kwargs):
        try:
            return _orig_cf(self, name, num_params, func, *args, **kwargs)
        except TypeError:
            return _orig_cf(self, name, num_params, func)
    try:
        sqlite3.Connection.create_function = _wrapped_cf
        setattr(sqlite3, "_ra_cf_patched", True)
    except Exception:
        pass

def _build_engine(url: str):
    if url.startswith("sqlite"):
        try:
            return create_engine(url, connect_args={"check_same_thread": False})
        except TypeError:
            # Older pysqlite without this kwarg; fall back without it
            return create_engine(url)
    return create_engine(url)

engine = _build_engine(SQLALCHEMY_DATABASE_URL)

# Hot-fix for old sqlite3 bindings where Connection.create_function only
# accepts three positional arguments. We wrap it to gracefully ignore extra
# args (e.g., deterministic) that some libraries may pass.
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def _patch_sqlite_create_function(dbapi_connection, connection_record):
        try:
            orig = getattr(dbapi_connection, "create_function", None)
            # Avoid double-wrapping
            if not orig or getattr(dbapi_connection, "_ra_cf_patched", False):
                return

            def wrapped(name, num_params, func, *args, **kwargs):
                try:
                    return orig(name, num_params, func, *args, **kwargs)
                except TypeError:
                    # Retry with the minimal signature supported by old pysqlite
                    return orig(name, num_params, func)

            dbapi_connection.create_function = wrapped
            setattr(dbapi_connection, "_ra_cf_patched", True)
        except Exception:
            # Best-effort patch; ignore if anything goes wrong
            pass

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
