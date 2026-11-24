CREATE OR REPLACE FUNCTION silver.clean_text(t TEXT) RETURNS TEXT AS $$
    SELECT NULLIF(REGEXP_REPLACE(TRIM(REPLACE(t, '"', '')), '\s+', ' ', 'g'), '')
$$ LANGUAGE SQL IMMUTABLE;

-- one correction per original city, state and zip, so the joins cannot duplicate rows
CREATE UNIQUE INDEX IF NOT EXISTS ux_city_corrections
    ON silver.city_corrections (original, COALESCE(state, ''), COALESCE(zip5, ''));

DROP TABLE IF EXISTS silver.iowa_businesses;

CREATE TABLE silver.iowa_businesses (
    corp_number        TEXT PRIMARY KEY,
    legal_name         TEXT NOT NULL,
    corporation_type   TEXT,
    effective_date     DATE,
    registered_agent   TEXT,
    ra_address_1       TEXT,
    ra_city            TEXT,
    ra_city_corrected  BOOLEAN NOT NULL DEFAULT FALSE,
    ra_state           VARCHAR(2),
    ra_zip             TEXT,
    ra_zip_invalidated BOOLEAN NOT NULL DEFAULT FALSE,
    ra_latitude        NUMERIC(11,8),
    ra_longitude       NUMERIC(11,8),
    ho_address_1       TEXT,
    ho_city            TEXT,
    ho_city_corrected  BOOLEAN NOT NULL DEFAULT FALSE,
    ho_state           VARCHAR(2),
    ho_zip             TEXT,
    ho_country         TEXT,
    ho_latitude        NUMERIC(11,8),
    ho_longitude       NUMERIC(11,8),
    loaded_at          TIMESTAMPTZ DEFAULT now()
);

INSERT INTO silver.iowa_businesses (
    corp_number, legal_name, corporation_type, effective_date, registered_agent,
    ra_address_1, ra_city, ra_city_corrected, ra_state, ra_zip, ra_zip_invalidated,
    ra_latitude, ra_longitude,
    ho_address_1, ho_city, ho_city_corrected, ho_state, ho_zip, ho_country,
    ho_latitude, ho_longitude
)
SELECT
    TRIM(r.corp_number),
    UPPER(silver.clean_text(r.legal_name)),
    silver.clean_text(r.corporation_type),
    CAST(NULLIF(TRIM(r.effective_date), '') AS DATE),
    UPPER(silver.clean_text(r.registered_agent)),

    silver.clean_text(r.ra_address_1),
    COALESCE(rc.proposed, UPPER(silver.clean_text(r.ra_city))),
    COALESCE(rc.proposed <> rc.original, FALSE),
    UPPER(silver.clean_text(r.ra_state)),
    CASE WHEN silver.clean_text(r.ra_zip) ~ '^[0-9]{5}(-[0-9]{4})?$'
         THEN silver.clean_text(r.ra_zip) END,
    (silver.clean_text(r.ra_zip) IS NOT NULL
     AND silver.clean_text(r.ra_zip) !~ '^[0-9]{5}(-[0-9]{4})?$'),
    CAST(NULLIF(TRIM(r.ra_latitude), '') AS NUMERIC(11,8)),
    CAST(NULLIF(TRIM(r.ra_longitude), '') AS NUMERIC(11,8)),

    silver.clean_text(r.ho_address_1),
    COALESCE(hc.proposed, ic.proposed, UPPER(silver.clean_text(r.ho_city))),
    COALESCE(hc.proposed <> hc.original, ic.proposed <> ic.original, FALSE),
    UPPER(silver.clean_text(r.ho_state)),
    silver.clean_text(r.ho_zip),
    silver.clean_text(r.ho_country),
    CAST(NULLIF(TRIM(r.ho_latitude), '') AS NUMERIC(11,8)),
    CAST(NULLIF(TRIM(r.ho_longitude), '') AS NUMERIC(11,8))
FROM bronze.iowa_businesses_raw AS r
LEFT JOIN silver.city_corrections AS rc
       ON rc.original = UPPER(TRIM(REPLACE(r.ra_city, '"', '')))
      AND rc.state IS NOT DISTINCT FROM UPPER(TRIM(r.ra_state))
      AND rc.zip5 IS NOT DISTINCT FROM
          (CASE WHEN TRIM(r.ra_zip) ~ '^[0-9]{5}' THEN LEFT(TRIM(r.ra_zip), 5) END)
LEFT JOIN silver.city_corrections hc
       ON hc.original = UPPER(TRIM(REPLACE(r.ho_city, '"', '')))
      AND hc.state IS NOT DISTINCT FROM UPPER(TRIM(r.ho_state))
      AND hc.zip5 IS NOT DISTINCT FROM
          (CASE WHEN TRIM(r.ho_zip) ~ '^[0-9]{5}' THEN LEFT(TRIM(r.ho_zip), 5) END)
      AND (r.ho_country = 'USA' OR r.ho_country IS NULL)
LEFT JOIN silver.intl_city_corrections ic
       ON ic.original = UPPER(TRIM(REPLACE(r.ho_city, '"', '')))
      AND ic.country = UPPER(TRIM(r.ho_country));