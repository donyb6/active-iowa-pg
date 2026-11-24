CREATE EXTENSION IF NOT EXISTS fuzzystrmatch SCHEMA public;
DROP TABLE IF EXISTS silver.intl_city_corrections;
CREATE TABLE silver.intl_city_corrections AS
WITH cfg AS (
    SELECT 'AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|PEI|QC|SK|YT|CA|UK|GB|KA|NSW|QLD|ALBERTA|BRITISH COLUMBIA|MANITOBA|NEW BRUNSWICK|NEWFOUNDLAND|NOVA SCOTIA|ONTARIO|QUEBEC|SASKATCHEWAN|PRINCE EDWARD ISLAND|YUKON|CANADA|UNITED KINGDOM|UNITED KINGDON|ENGLAND|GERMANY|INDIA|MALTA|POLAND|DENMARK|FRANCE|AUSTRALIA|MAHARASHTRA|KARNATAKA|HARYANA|UTTAR PRADESH|QUEENSLAND|HUNAN' AS tok
),
src AS (
    SELECT UPPER(TRIM(REPLACE(ho_city, '"', ''))) AS city0,
           UPPER(TRIM(ho_country)) AS country
    FROM bronze.iowa_businesses_raw
    WHERE ho_country IS NOT NULL
      AND UPPER(TRIM(ho_country)) <> 'USA'
      AND ho_city IS NOT NULL AND TRIM(ho_city) <> ''
),
cnt AS (
    SELECT city0, country, COUNT(*) AS rc
    FROM src
    GROUP BY city0, country
),
parts AS (
    SELECT s.city0, s.country, t.ord,
           TRIM(REGEXP_REPLACE(
                REGEXP_REPLACE(t.part, '\m[A-Z0-9]*[0-9][A-Z0-9]*\M', ' ', 'g'),
                '\s+', ' ', 'g')) AS p
    FROM (SELECT DISTINCT city0, country FROM src) s,
         UNNEST(STRING_TO_ARRAY(
             REGEXP_REPLACE(REPLACE(s.city0, 'B.C.', 'BC'), '[().]', ' ', 'g'), ','))
             WITH ORDINALITY AS t(part, ord)
),
stripped AS (
    SELECT p.city0, p.country, p.ord,
           TRIM(REGEXP_REPLACE(p.p,
               '(\s+|^)(' || c.tok || ')(\s+(' || c.tok || '))*\s*$', '')) AS p2
    FROM parts p CROSS JOIN cfg c
),
picked AS (
    SELECT DISTINCT ON (city0, country)
           city0, country, REGEXP_REPLACE(p2, '\s+', ' ', 'g') AS cand
    FROM stripped
    WHERE p2 <> ''
    ORDER BY city0, country, ord
),
resolved AS (
    SELECT c.city0, c.country, c.rc, p.cand
    FROM cnt c
    LEFT JOIN picked p ON p.city0 = c.city0 AND p.country = c.country
),
freq AS (
    SELECT country, cand, SUM(rc) AS n
    FROM resolved
    WHERE cand IS NOT NULL
    GROUP BY country, cand
),
resolved2 AS (
    SELECT r.city0, r.country, r.rc, r.cand, f.n AS cand_n
    FROM resolved r
    LEFT JOIN freq f ON f.country = r.country AND f.cand = r.cand
),
final AS (
    SELECT r.city0, r.country, r.rc, r.cand, fz.city AS fuzzy_city, fz.dist
    FROM resolved2 r
    LEFT JOIN LATERAL (
        SELECT q.cand AS city,
               public.LEVENSHTEIN(LEFT(r.cand, 255), LEFT(q.cand, 255)) AS dist
        FROM freq q
        WHERE r.cand IS NOT NULL
          AND r.cand_n < 3
          AND q.country = r.country
          AND q.n >= 3
          AND q.cand <> r.cand
          AND LENGTH(q.cand) >= 6
          AND public.LEVENSHTEIN(LEFT(r.cand, 255), LEFT(q.cand, 255)) <= 2
        ORDER BY dist, q.n DESC
        LIMIT 1
    ) fz ON TRUE
)
SELECT
    city0 AS original,
    country,
    COALESCE(fuzzy_city, cand, city0) AS proposed,
    CASE
        WHEN cand IS NULL                              THEN 'UNRESOLVED_empty'
        WHEN fuzzy_city IS NOT NULL AND cand <> city0  THEN 'strip+fuzzy'
        WHEN fuzzy_city IS NOT NULL                    THEN 'fuzzy'
        ELSE 'strip'
    END AS pass,
    dist,
    rc AS row_count
FROM final
WHERE cand IS NULL OR cand <> city0 OR fuzzy_city IS NOT NULL;