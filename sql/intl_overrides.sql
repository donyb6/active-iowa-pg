DROP TABLE IF EXISTS silver.intl_city_overrides;
CREATE TABLE silver.intl_city_overrides (
    original TEXT NOT NULL,
    country  TEXT NOT NULL,
    official TEXT NOT NULL,
    PRIMARY KEY (original, country)
);
INSERT INTO silver.intl_city_overrides (original, country, official) VALUES
    ('QUEENSLAND, AUSTRALIA', 'AUS', 'QUEENSLAND')
    -- , ('DPO, AA', 'PRI', 'DPO, AA')
    -- , ('ALFRED GAUCI, ST., JULIANS', 'MLT', 'ST JULIANS')
    -- , ('KRAWKOW, POLAND OBOZOWA STR. 30/32', 'POL', 'KRAKOW')
    -- , ('AARHUS N DENMARK', 'DNK', 'AARHUS')
    -- , ('TOWN OF MOUNT ROYAL, QUEBEC', 'CAN', 'MOUNT ROYAL')
    -- , ('BENGALURU, KARNATAKA', 'IND', 'BANGALORE')
    -- , ('MANAPAKKAM, CHENNAI', 'IND', 'CHENNAI')
    -- , ('HI TEC CITY, HYDERABAD, MADHAPUR', 'IND', 'HYDERABAD')
    -- , ('GERMASOGEIA, 4044 LIMASSOL', 'CYP', 'LIMASSOL')
;
DELETE FROM silver.intl_city_corrections c
USING silver.intl_city_overrides o
WHERE c.original = o.original AND c.country = o.country;
INSERT INTO silver.intl_city_corrections (original, country, proposed, pass, dist, row_count)
SELECT o.original, o.country, o.official, 'override', NULL,
       (SELECT COUNT(*) FROM bronze.iowa_businesses_raw b
        WHERE UPPER(TRIM(REPLACE(b.ho_city, '"', ''))) = o.original
          AND UPPER(TRIM(b.ho_country)) = o.country)
FROM silver.intl_city_overrides o;
CREATE UNIQUE INDEX IF NOT EXISTS ux_intl_city_corrections
    ON silver.intl_city_corrections (original, country);