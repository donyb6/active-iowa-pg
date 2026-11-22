-- 1. overview
SELECT pass, COUNT(*) AS mappings, SUM(row_count) AS rows_affected
FROM silver.city_corrections GROUP BY pass ORDER BY pass;

-- 2. Des Moines safety (should return 0 rows)
SELECT * FROM silver.city_corrections
WHERE original LIKE '%DES MOINES%' AND proposed NOT LIKE '%DES MOINES%';

-- 3. leftovers (should return 0 rows)
SELECT * FROM silver.city_corrections
WHERE proposed LIKE '%SAINT%'
   OR proposed ~ '(^| )(JCT|SGT|HTS|HGTS)( |$)'
   OR proposed ~ '^[NSEW] ';

-- 4. biggest non-trivial changes
SELECT original, zip5, state, proposed, pass, zip_top_pct, row_count
FROM silver.city_corrections
WHERE pass IN ('zip_fill', 'fuzzy', 'normalize+fuzzy', 'UNRESOLVED_short')
ORDER BY row_count DESC
LIMIT 60;

-- 5. merged spellings
SELECT original, zip5, proposed, row_count
FROM silver.city_corrections
WHERE pass = 'respace'
ORDER BY row_count DESC
LIMIT 40;