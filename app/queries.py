import os
import sys

import pandas as pd
import streamlit as st
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

    
# caches
@st.cache_data(ttl=CACHE_SECONDS)
def kpis():
    return run("""
        SELECT COUNT(*) AS total_entities,
               COUNT(*) FILTER (WHERE t.category = 'LLC') AS llcs,
               COUNT(*) FILTER (WHERE l.region_group = 'IOWA') AS iowa_head_offices,
               COUNT(*) FILTER (WHERE l.region_group <> 'UNKNOWN') AS known_head_offices,
               COUNT(*) FILTER (WHERE d.full_date > CURRENT_DATE - 365
                                  AND d.full_date <= CURRENT_DATE) AS new_last_12_months,
               COUNT(DISTINCT l.city) FILTER (WHERE l.region_group = 'IOWA'
                                                AND l.city <> 'UNKNOWN') AS iowa_cities
        FROM gold.fact_business_entity f
        JOIN gold.dim_corporation_type t ON t.corporation_type_key = f.corporation_type_key
        JOIN gold.dim_location l ON l.location_key = f.ho_location_key
        JOIN gold.dim_date d ON d.date_key = f.effective_date_key
    """)
    
@st.cache_data(ttl=CACHE_SECONDS)
def category_share():
    return run("""
        SELECT t.category,
            COUNT(*) AS entities,
            ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM gold.fact_business_entity f
        JOIN gold.dim_corporation_type t ON t.corporation_type_key = f.corporation_type_key
        GROUP BY t.category
        ORDER BY entities DESC
     """)
    
@st.cache_data(ttl=CACHE_SECONDS)
def entities_by_year(year_from=1900, year_to=2100):
    return run("""
        SELECT d.calendar_year AS year, t.category, COUNT(*) AS entities
        FROM gold.fact_business_entity f
        JOIN gold.dim_date d ON d.date_key = f.effective_date_key
        JOIN gold.dim_corporation_type t ON t.corporation_type_key = f.corporation_type_key
        WHERE d.calendar_year BETWEEN :year_from AND :year_to
        GROUP BY d.calendar_year, t.category
        ORDER BY d.calendar_year, t.category
    """, {"year_from": year_from, "year_to": year_to}
    )
