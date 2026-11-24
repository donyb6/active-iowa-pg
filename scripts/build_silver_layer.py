import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT))

from sqlalchemy import text
from config.db import get_session

SQL_FILES = ["city_correction.sql", "intl_city_corrections.sql",
             "intl_overrides.sql", "silver_layer.sql"]

session = get_session()

try:
    for name in SQL_FILES:
        session.execute(text((ROOT / "sql" / name).read_text()))
        print(f"ran {name}")
    session.commit()
    
    bronze = session.execute(text("SELECT COUNT(*) FROM bronze.iowa_businesses_raw")).scalar()
    silver = session.execute(text("SELECT COUNT(*) FROM silver.iowa_businesses")).scalar()
    print(f"bronze: {bronze:,} silver: {silver:,}")
except Exception:
    session.rollback()
    raise
finally:
    session.close()