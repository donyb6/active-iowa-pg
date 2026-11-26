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
);

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


-- dim_corporation_type
CREATE TABLE gold.dim_corporation_type (
    corporation_type_key INTEGER PRIMARY KEY,
    type_label TEXT NOT NULL UNIQUE,
    type_description TEXT NOT NULL,
    category TEXT NOT NULL,
    domestic_foreign TEXT NOT NULL
);

INSERT INTO gold.dim_corporation_type VALUES (-1, 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 'N/A');
INSERT INTO gold.dim_corporation_type
SELECT code, type_label, description,
       CASE WHEN code IN (34, 35, 36, 37) THEN 'LLC'
            WHEN code IN (10, 11, 12, 13, 61) THEN 'CORPORATION'
            WHEN code IN (22, 23, 26) THEN 'NON-PROFIT'
            WHEN code IN (43, 44, 45, 46, 56, 57, 58, 59) THEN 'PARTNERSHIP'
            WHEN code IN (24, 25, 51, 53, 54, 55) THEN 'COOPERATIVE'
            WHEN code IN (60, 62, 63) THEN 'FINANCIAL & INSURANCE'
            ELSE 'OTHER' END,
       CASE WHEN STRPOS(description, 'DOMESTIC') > 0 THEN 'DOMESTIC'
            WHEN STRPOS(description, 'FOREIGN') > 0  THEN 'FOREIGN'
            ELSE 'N/A' END
FROM (
     SELECT DISTINCT corporation_type AS type_label,
           CAST(SPLIT_PART(corporation_type, ' - ', 1) AS INTEGER) AS code,
           SUBSTRING(corporation_type FROM STRPOS(corporation_type, ' - ') + 3) AS description
    FROM silver.iowa_businesses
    WHERE corporation_type IS NOT NULL
) AS t;


-- dim_location
CREATE TABLE gold.dim_location (
    location_key INTEGER PRIMARY KEY,
    country TEXT NOT NULL,
    state TEXT NOT NULL,
    city TEXT NOT NULL,
    region_group TEXT NOT NULL,
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),
    UNIQUE(country, state, city)
);

INSERT INTO gold.dim_location VALUES (-1, 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', NULL, NULL);
INSERT INTO gold.dim_location (location_key, country, state, city, region_group, latitude, longitude)
WITH pts AS (
    SELECT ho_country_n AS country, ho_state_n AS state, ho_city_n AS city,
           ho_latitude AS lat, ho_longitude AS lon, ho_coord_status AS coord_status
    FROM gold.stg_entity
    UNION ALL
    SELECT ra_country_n, ra_state_n, ra_city_n, ra_latitude, ra_longitude, ra_coord_status
    FROM gold.stg_entity
)
SELECT ROW_NUMBER() OVER (ORDER BY country, state, city),
       country, state, city,
       CASE WHEN country = 'UNKNOWN' THEN 'UNKNOWN'
            WHEN country IN ('PRI', 'VIR', 'GUM') THEN 'US TERRITORY'
            WHEN country = 'USA' AND state = 'UNKNOWN' THEN 'UNKNOWN'
            WHEN country = 'USA' AND state = 'IA' THEN 'IOWA'
            WHEN country = 'USA' THEN 'OTHER US STATE'
            ELSE 'INTERNATIONAL' END,
       ROUND(AVG(lat) FILTER (WHERE coord_status = 'OK'), 6),
       ROUND(AVG(lon) FILTER (WHERE coord_status = 'OK'), 6)
FROM pts
WHERE NOT (country = 'UNKNOWN' AND state = 'UNKNOWN' AND city = 'UNKNOWN')
GROUP BY country, state, city;


-- fact table
CREATE TABLE gold.fact_business_entity (
    corp_number TEXT PRIMARY KEY,
    effective_date_key INTEGER NOT NULL REFERENCES gold.dim_date (date_key),
    corporation_type_key INTEGER NOT NULL REFERENCES gold.dim_corporation_type (corporation_type_key),
    ho_location_key INTEGER NOT NULL REFERENCES gold.dim_location (location_key),
    ra_location_key INTEGER NOT NULL REFERENCES gold.dim_location (location_key),
    legal_name TEXT NOT NULL,
    registered_agent TEXT,
    ho_address_1 TEXT,
    ho_zip TEXT,
    ho_latitude NUMERIC(11,8),
    ho_longitude NUMERIC(11,8),
    ho_coord_status TEXT NOT NULL,
    ra_address_1 TEXT,
    ra_zip TEXT,
    ra_latitude NUMERIC(11,8),
    ra_longitude NUMERIC(11,8),
    ra_coord_status TEXT NOT NULL,
    ho_city_corrected BOOLEAN NOT NULL,
    ra_city_corrected BOOLEAN NOT NULL,
    ra_zip_invalidated BOOLEAN NOT NULL,
    entity_count SMALLINT NOT NULL DEFAULT 1
);

INSERT INTO gold.fact_business_entity (
    corp_number, effective_date_key, corporation_type_key, ho_location_key, ra_location_key,
    legal_name, registered_agent,
    ho_address_1, ho_zip, ho_latitude, ho_longitude, ho_coord_status,
    ra_address_1, ra_zip, ra_latitude, ra_longitude, ra_coord_status,
    ho_city_corrected, ra_city_corrected, ra_zip_invalidated
)
SELECT
    s.corp_number,
    COALESCE(CAST(TO_CHAR(s.effective_date, 'YYYYMMDD') AS INTEGER), -1),
    COALESCE(t.corporation_type_key, -1),
    hl.location_key,
    rl.location_key,
    s.legal_name, s.registered_agent,
    s.ho_address_1, s.ho_zip, s.ho_latitude, s.ho_longitude, s.ho_coord_status,
    s.ra_address_1, s.ra_zip, s.ra_latitude, s.ra_longitude, s.ra_coord_status,
    s.ho_city_corrected, s.ra_city_corrected, s.ra_zip_invalidated
FROM gold.stg_entity AS s
LEFT JOIN gold.dim_corporation_type AS t 
    ON t.type_label = s.corporation_type
LEFT JOIN gold.dim_location AS hl
    ON hl.country = s.ho_country_n AND hl.state = s.ho_state_n AND hl.city = s.ho_city_n
LEFT JOIN gold.dim_location AS rl
    ON rl.country = s.ra_country_n AND rl.state = s.ra_state_n AND rl.city = s.ra_city_n;


CREATE INDEX ix_fact_effective_date ON gold.fact_business_entity (effective_date_key);
CREATE INDEX ix_fact_corp_type      ON gold.fact_business_entity (corporation_type_key);
CREATE INDEX ix_fact_ho_location    ON gold.fact_business_entity (ho_location_key);
CREATE INDEX ix_fact_ra_location    ON gold.fact_business_entity (ra_location_key);


-- aggregate for the registered agents (agents serving 10 or more entities)
CREATE TABLE gold.agg_registered_agents AS
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS agent_rank,
       registered_agent,
       COUNT(*) AS entity_count,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM gold.fact_business_entity), 3) AS pct_of_entities
FROM gold.fact_business_entity
WHERE registered_agent IS NOT NULL
GROUP BY registered_agent
HAVING COUNT(*) >= 10;