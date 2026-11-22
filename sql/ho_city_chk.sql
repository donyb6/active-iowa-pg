CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
DROP TABLE IF EXISTS ho_city_map;
CREATE TEMP TABLE ho_city_map AS
WITH base AS (
    SELECT
        UPPER(TRIM(REPLACE(ho_city, '"', ''))) AS city0,
        ho_state,
        CASE WHEN TRIM(ho_zip) ~ '^[0-9]{5}' THEN LEFT(TRIM(ho_zip), 5) END AS zip5
    FROM bronze.iowa_businesses_raw
    WHERE ho_country = 'USA'
      AND ho_city IS NOT NULL
      AND TRIM(ho_city) <> ''
),
-- PASS 1: deterministic cleanup (periods, trailing state text, abbreviations)
norm0 AS (
    SELECT
        city0, ho_state, zip5,
        REGEXP_REPLACE(
            CASE WHEN ho_state = 'IA'
                 THEN REGEXP_REPLACE(REPLACE(REPLACE(d, 'D.C.', 'DC'), '.', ' '), '[, ]+(IA|IOWA)$', '')
                 ELSE REPLACE(REPLACE(d, 'D.C.', 'DC'), '.', ' ') END,
            '\s+', ' ', 'g') AS c
    FROM (
        SELECT *,
            CASE
                WHEN city0 ~ '^N\. ?[A-Z]{2}' THEN REGEXP_REPLACE(city0, '^N\. ?', 'NORTH ')
                WHEN city0 ~ '^S\. ?[A-Z]{2}' THEN REGEXP_REPLACE(city0, '^S\. ?', 'SOUTH ')
                WHEN city0 ~ '^E\. ?[A-Z]{2}' THEN REGEXP_REPLACE(city0, '^E\. ?', 'EAST ')
                WHEN city0 ~ '^W\. ?[A-Z]{2}' THEN REGEXP_REPLACE(city0, '^W\. ?', 'WEST ')
                ELSE city0
            END AS d
        FROM base
    ) b
),
dir_known AS (
    SELECT c AS full_name
    FROM norm0
    WHERE c ~ '^(NORTH|SOUTH|EAST|WEST) '
    GROUP BY c
    HAVING COUNT(*) >= 2
),
norm0b AS (
    SELECT n0.city0, n0.ho_state, n0.zip5,
           COALESCE(k.full_name, n0.c) AS c
    FROM norm0 n0
    LEFT JOIN dir_known k
           ON n0.c ~ '^[NSEW] '
          AND k.full_name = (CASE LEFT(n0.c, 1)
                                 WHEN 'N' THEN 'NORTH'
                                 WHEN 'S' THEN 'SOUTH'
                                 WHEN 'E' THEN 'EAST'
                                 ELSE 'WEST' END) || SUBSTRING(n0.c FROM 2)
),
norm AS (
    SELECT
        city0, ho_state, zip5,
        TRIM(BOTH ' ,' FROM
            REGEXP_REPLACE(
            REGEXP_REPLACE(
            REGEXP_REPLACE(
            REGEXP_REPLACE(
            REGEXP_REPLACE(
            REGEXP_REPLACE(
                c,
                '^MT\M', 'MOUNT'),
                '^FT\M', 'FORT'),
                '\mSGT\M', 'SERGEANT'),
                '\mJCT\M', 'JUNCTION'),
                '\m(HTS|HGTS)\M', 'HEIGHTS', 'g'),
                '\mSAINT\M', 'ST', 'g')
        ) AS city1
    FROM norm0b
),
-- ZIP lookup, built AFTER pass 1 so spelling variants merge into one count
zip_city AS (
    SELECT zip5, city1, COUNT(*) AS n
    FROM norm
    WHERE zip5 IS NOT NULL AND LENGTH(city1) > 2
    GROUP BY zip5, city1
),
zip_top AS (
    SELECT zip5, city1 AS top_city, n AS top_n, zip_total
    FROM (
        SELECT zip5, city1, n,
               SUM(n) OVER (PARTITION BY zip5) AS zip_total,
               ROW_NUMBER() OVER (PARTITION BY zip5 ORDER BY n DESC, city1) AS rn
        FROM zip_city
    ) t
    WHERE rn = 1
),
city_freq AS (
    SELECT city1, COUNT(*) AS n_dataset
    FROM norm
    GROUP BY city1
),
decided AS (
    SELECT
        n.city0, n.city1, n.zip5, n.ho_state,
        t.top_city,
        ROUND(100.0 * t.top_n / t.zip_total, 1)       AS pct,
        (t.top_n >= 0.9 * t.zip_total AND t.zip_total >= 5) AS zip_is_reliable,
        f.n_dataset,
        LEVENSHTEIN(n.city1, t.top_city)              AS dist
    FROM norm n
    LEFT JOIN zip_top   t ON t.zip5  = n.zip5
    LEFT JOIN city_freq f ON f.city1 = n.city1
),
final AS (
    SELECT *,
        CASE
            -- short-city fill: 2-letter value, ZIP has a clear dominant city
            WHEN city1 ~ '^[A-Z]{2}$' AND zip_is_reliable
                THEN top_city
            -- PASS 2 (fuzzy): rare value, within 2 edits of the ZIP's dominant city
            WHEN city1 !~ '^[A-Z]{2}$' AND zip_is_reliable
                 AND city1 <> top_city
                 AND n_dataset < 5
                 AND LENGTH(top_city) >= 6
                 AND dist <= 2
                THEN top_city
            ELSE city1
        END AS proposed
    FROM decided
)
SELECT
    city0   AS original,
    zip5,
    ho_state,
    proposed,
    CASE
        WHEN city1 ~ '^[A-Z]{2}$' AND proposed <> city1 THEN 'zip_fill'
        WHEN city1 <> city0 AND proposed <> city1        THEN 'normalize+fuzzy'
        WHEN proposed <> city1                           THEN 'fuzzy'
        WHEN city1 <> city0                              THEN 'normalize'
        ELSE 'UNRESOLVED_short'
    END     AS pass,
    pct     AS zip_top_pct,
    dist,
    COUNT(*) AS row_count
FROM final
WHERE proposed <> city0 OR city1 ~ '^[A-Z]{2}$'
GROUP BY city0, city1, zip5, ho_state, proposed, pct, dist;

-- 1. Overview
SELECT pass, COUNT(*) AS distinct_mappings, SUM(row_count) AS rows_affected
FROM ho_city_map
GROUP BY pass
ORDER BY pass;

-- 2. Des Moines safety check: must return 0 rows
SELECT *
FROM ho_city_map
WHERE original LIKE '%DES MOINES%'
  AND proposed NOT LIKE '%DES MOINES%';

-- 3. The rows that need your eyes (everything except plain normalize)
SELECT *
FROM ho_city_map
WHERE pass <> 'normalize'
ORDER BY pass, row_count DESC;

SELECT original, proposed, row_count
FROM ho_city_map
WHERE pass = 'normalize'
ORDER BY row_count DESC
LIMIT 40;


SELECT original, proposed, row_count
FROM ho_city_map
WHERE pass = 'normalize'
  AND original !~ '^(MT|ST|FT)[. ]'
  AND original !~ ', (IA|IOWA)$'
ORDER BY row_count DESC
LIMIT 40;

SELECT original, proposed, row_count
FROM ho_city_map
WHERE proposed LIKE '%SAINT%'
   OR proposed ~ '(^| )(JCT|SGT|HTS|HGTS)( |$)'
   OR proposed LIKE 'W %';

SELECT original, proposed, pass, row_count
FROM ho_city_map
WHERE original ~ '^[NSEW]\.? '
ORDER BY row_count DESC;

SELECT UPPER(TRIM(ho_city)) AS city, COUNT(*) AS n
FROM bronze.iowa_businesses_raw
WHERE ho_country = 'USA'
  AND UPPER(TRIM(ho_city)) ~ '^[NSEW] '
GROUP BY 1
ORDER BY n DESC;
