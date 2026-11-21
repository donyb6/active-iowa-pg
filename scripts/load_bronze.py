import json
import yaml
from pathlib import Path
from psycopg2.extras import execute_values
from sqlalchemy import text, insert, MetaData, Table
from config.db import engine, get_session

with open("data.yaml") as f:
    cfg = yaml.safe_load(f)
    
raw_dir = Path(cfg["storage"]["raw_dir"])
src = raw_dir / cfg["storage"]["extracted_filename"]

COLUMNS = [
    "corp_number", "legal_name", "corporation_type", "effective_date",
    "registered_agent", "ra_address_1", "ra_city", "ra_state", "ra_zip",
    "ra_latitude", "ra_longitude", "ra_location",
    "ho_address_1", "ho_city", "ho_state", "ho_zip", "ho_country",
    "ho_latitude", "ho_longitude", "ho_location",
]

BATCH_SIZE = 5000

def to_text(v):
    return None if v is None else str(v)

def parse_line(line, source_file):
    rec = json.loads(line)
    row = {c: to_text(rec.get(c)) for c in COLUMNS}
    row["source_file"] = source_file
    return row

raw_table = Table(
    "iowa_businesses_raw", MetaData(), schema="bronze", autoload_with=engine
)

total = 0
bad_lines = 0
batch = []