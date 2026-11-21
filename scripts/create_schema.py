from pathlib import Path
from config.db import engine

sql = Path("schema.sql").read_text()

with engine.begin() as conn:
    conn.exec_driver_sql(sql)

print("Schemas and tables created.")