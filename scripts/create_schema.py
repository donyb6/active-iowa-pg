import psycopg2
from pathlib import Path
from config.db import CONNECTION_URL

conn = psycopg2.connect(CONNECTION_URL)

sql = Path("schema.sql").read_text()

with conn, conn.cursor() as cur:
    cur.execute(sql)

print("Schemas and tables created.")
conn.close()