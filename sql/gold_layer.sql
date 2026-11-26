CREATE SCHEMA IF NOT EXISTS gold;

DROP TABLE IF EXISTS gold.fact_business_entity;
DROP TABLE IF EXISTS gold.agg_map_grid;
DROP TABLE IF EXISTS gold.agg_registered_agents;
DROP TABLE IF EXISTS gold.dim_location;
DROP TABLE IF EXISTS gold.dim_corporation_type;
DROP TABLE IF EXISTS gold.dim_date;


-- staging view
CREATE OR REPLACE VIEW gold.stg_entity ASC
SELECT
    s.corp_number, s.legal_name, s.corporation_type, s.effective_date, s.registered_agent,
    s.ho_address_1, s.ho_zip, s.ho_latitude, s.ho_longitude,
    s.ra_address_1, s.ra_zip, s.ra_latitude, s.ra_longitude,
    s.ho_city_corrected, s.ra_city_corrected, s.ra_zip_invalidated,
    CASE WHEN s.ho_country IS NOT NULL THEN s.ho_country
         WHEN s.ho_address_1 IS NOT NULL OR s.ho_city IS NOT NULL
           OR s.ho_state IS NOT NULL OR s.ho_zip IS NOT NULL THEN 'USA'
         ELSE 'UNKNOWN' END AS ho_country_n,
    COALESCE(s.ho_state, 'UNKNOWN') AS ho_state_n,
    COALESCE(s.ho_city, 'UNKNOWN') AS ho_city_n,
     CASE WHEN s.ra_state IS NULL AND s.ra_city IS NULL THEN 'UNKNOWN'
         ELSE 'USA' END AS ra_country_n,
    COALESCE(s.ra_state, 'UNKNOWN') AS ra_state_n,
    COALESCE(s.ra_city, 'UNKNOWN')  AS ra_city_n,
    CASE WHEN s.ho_latitude IS NULL OR s.ho_longitude IS NULL THEN 'MISSING'
         WHEN s.ho_state = 'IA' AND (s.ho_latitude NOT BETWEEN 40.3 AND 43.6
                                  OR s.ho_longitude NOT BETWEEN -96.7 AND -90.0) THEN 'SUSPECT'
         ELSE 'OK' END AS ho_coord_status,
    CASE WHEN s.ra_latitude IS NULL OR s.ra_longitude IS NULL THEN 'MISSING'
         WHEN s.ra_state = 'IA' AND (s.ra_latitude NOT BETWEEN 40.3 AND 43.6
                                  OR s.ra_longitude NOT BETWEEN -96.7 AND -90.0) THEN 'SUSPECT'
         ELSE 'OK' END AS ra_coord_status
FROM silver.iowa_businesses AS s;


-- dim_date
CREATE TABLE gold.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE,
    calendar_year INTEGER,
    calendar_quarter INTEGER,
    calendar_month INTEGER,
    month_name TEXT,
    day_of_week INTEGER,
    day_name TEXT
)

INSERT INTO gold.dim_date VALUES (-1, NULL, NULL, NULL, NULL, 'UNKNOWN', NULL, 'UNKNOWN');
INSERT INTO gold.dim_date
WITH bounds AS (
    SELECT MAKE_DATE(CAST(EXTRACT(YEAR FROM MIN(effective_date)) AS INTEGER), 1, 1)   AS d0,
           MAKE_DATE(CAST(EXTRACT(YEAR FROM MAX(effective_date)) AS INTEGER), 12, 31) AS d1
    FROM silver.iowa_businesses
),
days AS (
    SELECT b.d0 + g AS d
    FROM bounds AS b, GENERATE_SERIES(0, b.d1 - b.d0) AS g
)
SELECT CAST(TO_CHAR(d, 'YYYYMMDD') AS INTEGER),
       d,
       CAST(EXTRACT(YEAR FROM d) AS INTEGER),
       CAST(EXTRACT(QUARTER FROM d) AS INTEGER),
       CAST(EXTRACT(MONTH FROM d) AS INTEGER),
       TRIM(TO_CHAR(d, 'Month')),
       CAST(EXTRACT(ISODOW FROM d) AS INTEGER),
       TRIM(TO_CHAR(d, 'Day'))
FROM days;

