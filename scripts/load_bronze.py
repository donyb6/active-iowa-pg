import json
import yaml
from pathlib import Path
from psycopg2.extras import execute_values
from config.db import engine

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