from pathlib import Path
from config.db import get_session
from sqlalchemy import text

sql = Path("schema.sql").read_text()

session = get_session()
try:
    session.execute(text(sql))
    session.commit()
    print("Schemas and tables created.")
except Exception:
    session.rollback()
    raise
finally:
    session.close()

print("Schemas and tables created.")