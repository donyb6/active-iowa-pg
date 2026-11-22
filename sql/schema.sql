CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;


CREATE TABLE IF NOT EXISTS bronze.iowa_businesses_raw (
    id               BIGSERIAL PRIMARY KEY,
    corp_number      TEXT,
    legal_name       TEXT,
    corporation_type TEXT,
    effective_date   TEXT,
    registered_agent TEXT,
    ra_address_1     TEXT,
    ra_city          TEXT,
    ra_state         TEXT,
    ra_zip           TEXT,
    ra_latitude      TEXT,
    ra_longitude     TEXT,
    ra_location      TEXT,
    ho_address_1     TEXT,
    ho_city          TEXT,
    ho_state         TEXT,
    ho_zip           TEXT,
    ho_country       TEXT,
    ho_latitude      TEXT,
    ho_longitude     TEXT,
    ho_location      TEXT,
    source_file      TEXT,
    ingested_at      TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS silver.iowa_businesses (
    corp_number      TEXT PRIMARY KEY,
    legal_name       TEXT NOT NULL,
    corporation_type TEXT,
    effective_date   DATE,
    registered_agent TEXT,
    ra_address_1     TEXT,
    ra_city          TEXT,
    ra_state         TEXT,
    ra_zip           TEXT,
    ra_latitude      NUMERIC(9,6),
    ra_longitude     NUMERIC(9,6),
    ho_address_1     TEXT,
    ho_city          TEXT,
    ho_state         TEXT,
    ho_zip           TEXT,
    ho_country       TEXT,
    ho_latitude      NUMERIC(9,6),
    ho_longitude     NUMERIC(9,6)
);