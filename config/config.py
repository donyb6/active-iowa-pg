import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if DATABASE_URL:
    CONNECTION_URL = DATABASE_URL
    for prefix in ("postgresql://", "postgres://"):
        if CONNECTION_URL.startswith(prefix):
            CONNECTION_URL = "postgresql+psycopg2://" + CONNECTION_URL[len(prefix):]
            break
else:
    
    CONNECTION_URL = URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
        host=os.getenv("POSTGRES_HOST"),
        port=int(os.getenv("POSTGRES_PORT")),
        database=os.getenv("POSTGRES_DATABASE"),
    )