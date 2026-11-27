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

    
# caching

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
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_corporation_type AS t 
            ON t.corporation_type_key = f.corporation_type_key
        JOIN gold.dim_location AS l 
            ON l.location_key = f.ho_location_key
        JOIN gold.dim_date d ON d.date_key = f.effective_date_key
    """)
    
@st.cache_data(ttl=CACHE_SECONDS)
def category_share():
    return run("""
        SELECT t.category,
            COUNT(*) AS entities,
            ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_corporation_type AS t 
            ON t.corporation_type_key = f.corporation_type_key
        GROUP BY t.category
        ORDER BY entities DESC
     """)
    
@st.cache_data(ttl=CACHE_SECONDS)
def entities_by_year(year_from=1900, year_to=2100):
    return run("""
        SELECT d.calendar_year AS year, t.category, COUNT(*) AS entities
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_date d 
            ON d.date_key = f.effective_date_key
        JOIN gold.dim_corporation_type AS t 
            ON t.corporation_type_key = f.corporation_type_key
        WHERE d.calendar_year BETWEEN :year_from AND :year_to
        GROUP BY d.calendar_year, t.category
        ORDER BY d.calendar_year, t.category
    """, {"year_from": year_from, "year_to": year_to}
    )

@st.cache_data(ttl=CACHE_SECONDS)
def entities_by_month(year_from=2000):
    return run("""
            SELECT d.calendar_year, d.calendar_month as month,
                d.month_name, COUNT(*) AS entities
            FROM gold.fact_business_entity AS f
            JOIN gold.dim_date AS d 
                ON d.date_key = f.effective_date_key
            WHERE d.calendar_year >= :year_from
            GROUP BY d.calendar_year, d.calendar_month, d.month_name
            ORDER BY d.calendar_year, d.calendar_month
        """, {"year_from": year_from}
        )
    
@st.cache_data(ttl=CACHE_SECONDS)
def types_breakdown():
    return run("""
        SELECT t.category, t.type_description, t.domestic_foreign, COUNT(*) AS entities
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_corporation_type AS t 
            ON t.corporation_type_key = f.corporation_type_key
        GROUP BY t.category, t.type_description, t.domestic_foreign
        ORDER BY entities DESC
    """)

# mapping cache
@st.cache_data(ttl=CACHE_SECONDS)
def region_split(role="HEAD_OFFICE"):
    c = _role(role)
    return run(f"""
        SELECT l.region_group, COUNT(*) AS entities
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_location AS l 
            ON l.location_key = f.{c['loc']}
        GROUP BY l.region_group
        ORDER BY entities DESC
    """)

@st.cache_data(ttl=CACHE_SECONDS)
def top_cities(role="HEAD_OFFICE", region_group="IOWA", limit=20):
    c = _role(role)
    return run(f"""
        SELECT l.city, l.state, l.country,
               CAST(l.latitude AS DOUBLE PRECISION) AS lat,
               CAST(l.longitude AS DOUBLE PRECISION) AS lon,
               COUNT(*) AS entities
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_location AS l 
            ON l.location_key = f.{c['loc']}
        WHERE l.region_group = :region_group
          AND l.city <> 'UNKNOWN'
        GROUP BY l.city, l.state, l.country, l.latitude, l.longitude
        ORDER BY entities DESC
        LIMIT :limit
    """, {"region_group": region_group, "limit": limit}
    )
    
@st.cache_data(ttl=CACHE_SECONDS)
def density_grid(role="HEAD_OFFICE", south=40.3, north=43.6, west=-96.7, east=-90.0):
    _role(role)
    return run("""
        SELECT CAST(lat AS DOUBLE PRECISION) AS lat,
               CAST(lon AS DOUBLE PRECISION) AS lon,
               entity_count
        FROM gold.agg_map_grid
        WHERE role = :role
          AND lat BETWEEN :south AND :north
          AND lon BETWEEN :west AND :east
    """, {"role": role, "south": south, "north": north, "west": west, "east": east}
    )
    
@st.cache_data(ttl=CACHE_SECONDS)
def city_options(role="HEAD_OFFICE"):
    c = _role(role)
    return run(f"""
        SELECT l.city, l.state, COUNT(*) AS entities
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_location AS l 
            ON l.location_key = f.{c['loc']}
        WHERE l.region_group = 'IOWA' AND l.city <> 'UNKNOWN'
        GROUP BY l.city, l.state
        ORDER BY entities DESC
        LIMIT 300
    """)
    
@st.cache_data(ttl=CACHE_SECONDS)
def city_points(city, state, role="HEAD_OFFICE", limit=5000):
    c = _role(role)
    return run(f"""
        SELECT f.corp_number, f.legal_name, t.category,
               CAST(f.{c['lat']} AS DOUBLE PRECISION) AS lat,
               CAST(f.{c['lon']} AS DOUBLE PRECISION) AS lon
        FROM gold.fact_business_entity AS f
        JOIN gold.dim_location AS l 
            ON l.location_key = f.{c['loc']}
        JOIN gold.dim_corporation_type AS t 
            ON t.corporation_type_key = f.corporation_type_key
        WHERE l.city = :city AND l.state = :state AND f.{c['status']} = 'OK'
        ORDER BY MD5(f.corp_number)
        LIMIT :limit
    """, {"city": city, "state": state, "limit": limit}
    )
    
    
# registered agents

@st.cache_data(ttl=CACHE_SECONDS)
def agent_top(limit=25):
    return run("""
        SELECT agent_rank, registered_agent, entity_count, pct_of_entities
        FROM gold.agg_registered_agents
        ORDER BY agent_rank
        LIMIT :limit
    """, {"limit": limit}
    )

@st.cache_data(ttl=CACHE_SECONDS)
def agent_concentration():
    return run("""
        SELECT agent_rank, entity_count, pct_of_entities
        FROM gold.agg_registered_agents
        ORDER BY agent_rank
    """)

@st.cache_data(ttl=CACHE_SECONDS)
def agent_size_buckets():
    return run("""
        WITH a AS (
            SELECT registered_agent, COUNT(*) AS n
            FROM gold.fact_business_entity
            WHERE registered_agent IS NOT NULL
            GROUP BY registered_agent
        )
        SELECT CASE WHEN n = 1  THEN '1 entity'
                    WHEN n < 5  THEN '2-4'
                    WHEN n < 10 THEN '5-9'
                    WHEN n < 100 THEN '10-99'
                    ELSE '100+' END AS size_bucket,
               COUNT(*) AS agents,
               CAST(SUM(n) AS BIGINT) AS entities
        FROM a
        GROUP BY 1
        ORDER BY MIN(n)
    """)