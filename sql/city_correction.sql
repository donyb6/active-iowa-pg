CREATE EXTENSION IF NOT EXISTS fuzzystrmatch SCHEMA public;
DROP TABLE IF EXISTS silver.city_corrections;
CREATE TABLE silver.city_corrections AS
WITH src AS (
    SELECT UPPER(TRIM(REPLACE(ho_city, '"', ''))) AS city0,
           UPPER(TRIM(ho_state)) AS st,
           CASE WHEN TRIM(ho_zip) ~ '^[0-9]{5}' THEN LEFT(TRIM(ho_zip), 5) END AS zip5
    FROM bronze.iowa_businesses_raw
    WHERE ho_country = 'USA' AND ho_city IS NOT NULL AND TRIM(ho_city) <> ''
    UNION ALL
    SELECT UPPER(TRIM(REPLACE(ra_city, '"', ''))),
           UPPER(TRIM(ra_state)),
           CASE WHEN TRIM(ra_zip) ~ '^[0-9]{5}' THEN LEFT(TRIM(ra_zip), 5) END
    FROM bronze.iowa_businesses_raw
    WHERE ra_city IS NOT NULL AND TRIM(ra_city) <> ''
),
norm0 AS (
    SELECT
        city0, st, zip5,
        REGEXP_REPLACE(
            CASE WHEN st = 'IA'
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
        FROM src
    ) s
),
dir_known AS (
    SELECT c AS full_name
    FROM norm0
    WHERE c ~ '^(NORTH|SOUTH|EAST|WEST) '
    GROUP BY c
    HAVING COUNT(*) >= 2
),
norm0b AS (
    SELECT n0.city0, n0.st, n0.zip5,
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
        city0, st, zip5,
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
forms5 AS (
    SELECT zip5, city1, REPLACE(city1, ' ', '') AS k, COUNT(*) AS n
    FROM norm
    WHERE zip5 IS NOT NULL AND LENGTH(city1) > 2
    GROUP BY zip5, city1
    HAVING COUNT(*) >= 5
),
canon AS (
    SELECT DISTINCT ON (zip5, k) zip5, k, city1 AS canon_city
    FROM forms5
    ORDER BY zip5, k, n DESC, city1
),
overrides(canon_city, official) AS (
    VALUES ('LAMOTTE', 'LA MOTTE'), ('LE GRAND', 'LEGRAND'), ('DEWITT', 'DE WITT')
),
norm2 AS (
    SELECT n.city0, n.st, n.zip5, n.city1 AS city1_pre,
           COALESCE(o.official, c.canon_city, n.city1) AS city1
    FROM norm n
    LEFT JOIN forms5 f ON f.zip5 = n.zip5 AND f.city1 = n.city1
    LEFT JOIN canon c  ON c.zip5 = f.zip5 AND c.k = f.k
    LEFT JOIN overrides o ON o.canon_city = COALESCE(c.canon_city, n.city1)
),
zip_city AS (
    SELECT zip5, city1, COUNT(*) AS n
    FROM norm2
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
    FROM norm2
    GROUP BY city1
),
decided AS (
    SELECT
        n.city0, n.city1, n.city1_pre, n.zip5, n.st,
        t.top_city,
        ROUND(100.0 * t.top_n / t.zip_total, 1) AS pct,
        (t.top_n >= 0.9 * t.zip_total AND t.zip_total >= 5) AS zip_is_reliable,
        f.n_dataset,
        public.LEVENSHTEIN(LEFT(n.city1, 255), LEFT(t.top_city, 255)) AS dist
    FROM norm2 n
    LEFT JOIN zip_top   t ON t.zip5  = n.zip5
    LEFT JOIN city_freq f ON f.city1 = n.city1
),
final AS (
    SELECT *,
        CASE
            WHEN city1 ~ '^[A-Z]{2}$' AND zip_is_reliable
                THEN top_city
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
    city0 AS original,
    zip5,
    st AS state,
    proposed,
    CASE
        WHEN city1 ~ '^[A-Z]{2}$' AND proposed <> city1 THEN 'zip_fill'
        WHEN city1 <> city0 AND proposed <> city1        THEN 'normalize+fuzzy'
        WHEN proposed <> city1                           THEN 'fuzzy'
        WHEN city1 <> city1_pre                          THEN 'respace'
        WHEN city1 <> city0                              THEN 'normalize'
        ELSE 'UNRESOLVED_short'
    END AS pass,
    pct AS zip_top_pct,
    dist,
    COUNT(*) AS row_count
FROM final
WHERE proposed <> city0 OR city1 ~ '^[A-Z]{2}$'
GROUP BY city0, city1, city1_pre, zip5, st, proposed, pct, dist;