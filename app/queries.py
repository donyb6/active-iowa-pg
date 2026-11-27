import os
import sys

import pandas as pd
from sqlalchemy import text

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.db import engine

CACHE_SECONDS = 3600

ROLES = {
    "HEAD_OFFICE": {"loc": "ho_location_key", "lat": "ho_latitude",
                    "lon": "ho_longitude", "status": "ho_coord_status"},
    "REGISTERED_AGENT": {"loc": "ra_location_key", "lat": "ra_latitude",
                         "lon": "ra_longitude", "status": "ra_coord_status"}
}


def _role(role):
    return ROLES[role]

def run(sql, params=None):
    with engine.connect() as conn:
        return pd.read_sql(text(sql), conn, params=params or {}, coerce_float=True)