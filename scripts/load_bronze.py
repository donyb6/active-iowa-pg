import json
import yaml
from pathlib import Path
from psycopg2.extras import execute_values
from config.db import engine

with open("data.yaml") as f:
    cfg = yaml.safe_load(f)