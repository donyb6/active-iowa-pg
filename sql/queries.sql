SELECT *
FROM bronze.iowa_businesses_raw;

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'iowa_businesses_raw'
  AND table_schema = 'bronze'
ORDER BY ordinal_position;

SELECT
    effective_date,
    TO_DATE(effective_date, 'YYYY-MM-DD') AS date_fix
FROM bronze.iowa_businesses_raw; -- change effective_date col to date

SELECT DISTINCT corporation_type, 
	TRIM(corporation_type) AS trimmed_corporation_type
FROM bronze.iowa_businesses_raw; -- trim

SELECT DISTINCT corporation_type, 
	COUNT(*) AS count_corporation_type
FROM bronze.iowa_businesses_raw
GROUP BY corporation_type;

SELECT legal_name, UPPER(TRIM(legal_name)) AS trimmed_legal_name
FROM bronze.iowa_businesses_raw; -- trim

SELECT registered_agent, UPPER(TRIM(registered_agent)) AS trimmed_registered_agent
FROM bronze.iowa_businesses_raw; -- trim

SELECT legal_name, REPLACE(legal_name, '"', '') AS trimmed_legal_name
FROM bronze.iowa_businesses_raw
WHERE legal_name LIKE '"%' OR legal_name LIKE '%"' OR legal_name LIKE '"%"'; -- remove quotes, 102 rows out of 350k

SELECT ra_address_1, REPLACE(ra_address_1, '"', '') AS ra_1_cleaned
FROM bronze.iowa_businesses_raw
WHERE ra_address_1 LIKE '"%' OR ra_address_1 LIKE '%"' OR ra_address_1 LIKE '"%"'; -- remove quotes, 2 rows


SELECT ho_city, REPLACE(ho_city, '"', '') AS ho_city_cleaned
FROM bronze.iowa_businesses_raw
WHERE ho_city LIKE '"%' OR ho_city LIKE '%"' OR ho_city LIKE '"%"'; -- remove quotes, 1 row


SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_address_1 ~ '^[0-9]+$'; -- only numbers in ra_address_1(54 rows): remove/keep(tbd)


SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_city ~ '^[0-9]+$'; -- only numbers in ra_city, 12 rows. some numbers(most) correspond with ra_zip


SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_state ~ '^[A-Za-z]{3,}$'; -- no ra_state has three or more letters

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_state ~ '^[0-9]+$'; -- no ra_state has numbers

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_city ~ '^[A-Za-z]{2}$'; -- ra_city could be city names since LE, CL and DA are abbrs for cities

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_zip ~ '^[A-Za-z]'; -- no ra_zip contains letters

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_zip ~ '^[0-9]{1,4}$'; -- ra_zip contains zip codes with nums <= 4

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_address_1 ~ '^[0-9]+$'; -- ho_address_1 has 187 entries which are only numbers

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_city ~ '^[0-9]+$';

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_state ~ '^[A-Za-z]{3,}$'; -- no ho_state has >= 3 letters

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_state ~ '^[0-9]+$'; -- no ho_state has numerical entries

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_city ~ '^[A-Za-z]{2}$' AND ho_state <> 'IA'; -- 25 rows have shortened city names

SELECT *
FROM (
    SELECT *,
        COUNT(*) OVER (
            PARTITION BY corp_number, legal_name, corporation_type, effective_date, registered_agent,
				ra_address_1, ra_city, ra_state, ra_zip, ra_latitude, ra_longitude, ra_location,
				ho_address_1, ho_city, ho_state, ho_zip, ho_country, ho_latitude, ho_longitude, ho_location
        ) AS duplicate_count
    FROM bronze.iowa_businesses_raw
) AS duplicates
WHERE duplicate_count > 1; -- no duplicates

SELECT TRIM(corp_number) AS corp_number, COUNT(*)
FROM bronze.iowa_businesses_raw
GROUP BY TRIM(corp_number)
HAVING COUNT(*) > 1;

SELECT ra_state, ho_state
FROM bronze.iowa_businesses_raw
WHERE (ra_state IS NOT NULL AND TRIM(ra_state) <> '' AND LENGTH(TRIM(ra_state)) <> 2)
   OR (ho_state IS NOT NULL AND TRIM(ho_state) <> '' AND LENGTH(TRIM(ho_state)) <> 2);


WITH clean AS (
    SELECT
        id,
        UPPER(TRIM(REPLACE(ho_city, '"', ''))) AS city,
        CASE WHEN TRIM(ho_zip) ~ '^[0-9]{5}' THEN LEFT(TRIM(ho_zip), 5) END AS zip5,
        ho_state,
        ho_country
    FROM bronze.iowa_businesses_raw
),
city_counts AS (
    -- the lookup: how often each full-length city appears per ZIP
    SELECT zip5, city, COUNT(*) AS n
    FROM clean
    WHERE ho_country = 'USA'
      AND zip5 IS NOT NULL
      AND LENGTH(city) > 2
    GROUP BY zip5, city
),
ranked AS (
    SELECT
        zip5, city, n,
        SUM(n) OVER (PARTITION BY zip5) AS zip_total,
        ROW_NUMBER() OVER (PARTITION BY zip5 ORDER BY n DESC, city) AS rn
    FROM city_counts
)
SELECT
    c.city                              AS short_city,
    c.zip5,
    c.ho_state,
    r.city                              AS candidate_city,
    r.n                                 AS candidate_rows,
    r.zip_total                         AS rows_in_zip,
    ROUND(100.0 * r.n / r.zip_total, 1) AS pct
FROM clean c
LEFT JOIN ranked r
       ON r.zip5 = c.zip5 AND r.rn = 1
WHERE c.ho_country = 'USA'
  AND c.city ~ '^[A-Za-z]{2}$'
ORDER BY pct DESC NULLS LAST, c.zip5;

SELECT
    LEFT(TRIM(ho_zip), 5)                      AS zip5,
    UPPER(TRIM(REPLACE(ho_city, '"', '')))     AS city,
    COUNT(*)                                   AS n
FROM bronze.iowa_businesses_raw
WHERE ho_country = 'USA'
  AND LEFT(TRIM(ho_zip), 5) IN ('52314', '50324')
GROUP BY 1, 2
ORDER BY zip5, n DESC;


SELECT ho_address_1, ho_city, ho_zip, ho_country
FROM silver.iowa_businesses
WHERE ho_country <> 'USA'; -- i have to rollback to standardise ho_city non US countries

SELECT 
    'bronze' AS layer,
    COUNT(*) FILTER (WHERE ho_country = 'USA') AS usa_count,
    COUNT(*) FILTER (WHERE ho_country <> 'USA' AND TRIM(ho_country) <> '') AS non_usa_count,
    COUNT(*) FILTER (WHERE ho_country IS NULL OR TRIM(ho_country) = '') AS missing_count
FROM bronze.iowa_businesses_raw
UNION ALL
SELECT 
    'silver' AS layer,
    COUNT(*) FILTER (WHERE ho_country = 'USA') AS usa_count,
    COUNT(*) FILTER (WHERE ho_country <> 'USA' AND TRIM(ho_country) <> '') AS non_usa_count,
    COUNT(*) FILTER (WHERE ho_country IS NULL OR TRIM(ho_country) = '') AS missing_count
FROM silver.iowa_businesses; -- equal values in bronze and silver layer.


SELECT
    COUNT(*) FILTER (WHERE ho_city_corrected AND ho_country = 'USA')  AS ho_usa,
    COUNT(*) FILTER (WHERE ho_city_corrected AND ho_country IS NULL)  AS ho_null_country,
    COUNT(*) FILTER (WHERE ho_city_corrected AND ho_country <> 'USA') AS ho_intl,
    COUNT(*) FILTER (WHERE ra_city_corrected)                         AS ra,
    (SELECT SUM(row_count) FROM silver.city_corrections
     WHERE pass <> 'UNRESOLVED_short')                                AS us_table,
    (SELECT SUM(row_count) FROM silver.intl_city_corrections
     WHERE proposed <> original)                                      AS intl_table
FROM silver.iowa_businesses;

SELECT COUNT(*) FILTER (WHERE ho_city_corrected) AS corrected_in_null_country
FROM silver.iowa_businesses
WHERE ho_country IS NULL;


SELECT COUNT(*) AS null_country_rows,
       COUNT(*) FILTER (WHERE ho_address_1 IS NULL AND ho_city IS NULL
                          AND ho_state IS NULL AND ho_zip IS NULL) AS no_head_office_info,
       COUNT(*) FILTER (WHERE ho_state ~ '^[A-Z]{2}$'
                          AND ho_zip ~ '^[0-9]{5}') AS us_looking
FROM silver.iowa_businesses
WHERE ho_country IS NULL;


SELECT corp_number, ho_city, ho_state, ho_zip, ho_country
FROM silver.iowa_businesses
WHERE ho_country <> 'USA'
  AND ho_zip ~ '^[0-9]{5}' AND ho_state ~ '^[A-Z]{2}$';

--  intl_cit_corrections queries
SELECT pass, COUNT(*) AS mappings, SUM(row_count) AS rows_affected
FROM silver.intl_city_corrections
GROUP BY pass ORDER BY pass;

SELECT country, original, proposed, pass, dist, row_count
FROM silver.intl_city_corrections
ORDER BY pass, country, row_count DESC;

SELECT corporation_type, COUNT(*) AS n
FROM silver.iowa_businesses
GROUP BY corporation_type
ORDER BY n DESC;

SELECT
    (SELECT COUNT(*) FROM (SELECT DISTINCT ho_country, ho_state, ho_city
                           FROM silver.iowa_businesses) a) AS ho_locations,
    (SELECT COUNT(*) FROM (SELECT DISTINCT ra_state, ra_city
                           FROM silver.iowa_businesses) b) AS ra_locations,
    (SELECT COUNT(DISTINCT registered_agent) FROM silver.iowa_businesses) AS agents,
    (SELECT MIN(effective_date) FROM silver.iowa_businesses) AS min_date,
    (SELECT MAX(effective_date) FROM silver.iowa_businesses) AS max_date;

SELECT
    COUNT(*) AS total,
    COUNT(ho_latitude) AS ho_with_coords,
    COUNT(ra_latitude) AS ra_with_coords,
    COUNT(*) FILTER (WHERE ho_latitude = 0 OR ho_longitude = 0) AS ho_zero,
    COUNT(*) FILTER (WHERE ho_state = 'IA'
        AND (ho_latitude NOT BETWEEN 40.3 AND 43.6
          OR ho_longitude NOT BETWEEN -96.7 AND -90.0)) AS ho_iowa_outside_bounds,
    COUNT(*) FILTER (WHERE ra_state = 'IA'
        AND (ra_latitude NOT BETWEEN 40.3 AND 43.6
          OR ra_longitude NOT BETWEEN -96.7 AND -90.0)) AS ra_iowa_outside_bounds
FROM silver.iowa_businesses;


-- queries on gold layer

SELECT f.corp_number, f.legal_name, f.registered_agent,
    t.category, t.type_label, t.type_description,
    d.full_date AS effective_date, d.calendar_quarter,
    l.city, l.state, l.country, l.region_group, l.latitude, l.latitude
FROM gold.fact_business_entity AS f
JOIN gold.dim_corporation_type AS t
    ON t.corporation_type_key = f.corporation_type_key
JOIN gold.dim_date AS d
    ON d.date_key = f.effective_date_key
JOIN gold.dim_location as l
    ON l.location_key = f.ho_location_key
ORDER BY d.calendar_year;

SELECT t.category, COUNT(*) AS entities,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct
FROM gold.fact_business_entity AS f
JOIN gold.dim_corporation_type AS t
    ON f.corporation_type_key = t.corporation_type_key
GROUP BY t.category
ORDER BY entities DESC;

SELECT d.calendar_year, COUNT(*) AS active_entities,
    COUNT (*) FILTER(WHERE t.category = 'LLC') AS llcs,
    ROUND(100.0 * COUNT (*) FILTER(WHERE t.category = 'LLC') / COUNT(*), 1) AS llc_pct
FROM gold.fact_business_entity AS f
JOIN gold.dim_date as d
    ON d.date_key = f.effective_date_key
JOIN gold.dim_corporation_type AS t
    ON t.corporation_type_key = f.corporation_type_key
GROUP BY d.calendar_year
ORDER BY d.calendar_year;


SELECT t.category, d.calendar_year, COUNT(*) AS entities,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) as category_pct
FROM gold.fact_business_entity as f
JOIN gold.dim_corporation_type AS t
    ON t.corporation_type_key = f.corporation_type_key
JOIN gold.dim_date AS d
    ON d.date_key = f.effective_date_key
GROUP BY d.calendar_year, t.category
ORDER BY d.calendar_year;
