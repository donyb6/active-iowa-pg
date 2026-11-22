import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT))

from sqlalchemy import text
from config.db import get_session

SQL_FILES = ["city_correction.sql", "silver_layer.sql"]