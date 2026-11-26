import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT))

from sqlalchemy import text
from config.db import get_session
                
session = get_session()
try:
    session.execute(text((ROOT / "sql" / "gold_layer.sql").read_text()))
    session.commit()
    for table in ["dim_date", "dim_corporation_type", "dim_location",
                  "fact_business_entity", "agg_registered_agents", "agg_map_grid"]:
        n = session.execute(text(f"SELECT COUNT(*) FROM gold.{table}")).scalar()
        print(f"gold.{table:<24} {n:>9,}")
except Exception:
    session.rollback()
    raise
finally:
    session.close()