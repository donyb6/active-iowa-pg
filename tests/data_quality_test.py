import pytest
import warnings

from sqlalchemy import text
from typing import NamedTuple

class Check(NamedTuple):
    name: str
    severity: str
    sql: str
    max_allowed: int = 0    
    

CHECKS =[
    Check("bronze_not_empty", "error",
          "SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM bronze.iowa_businesses_raw"),
    
    Check("row_count_matches_bronze", "error", 
          r"""SELECT ABS((SELECT COUNT(*) FROM bronze.iowa_businesses_raw)
                        - (SELECT COUNT(*) FROM silver.iowa_businesses))"""),
    
    Check("corp_number_unique", "error",
          r"""SELECT COUNT(*) FROM (
                  SELECT corp_number FROM silver.iowa_businesses
                  GROUP BY corp_number HAVING COUNT(*) > 1) AS d"""),
    
    Check("legal_name_present", "error",
          "SELECT COUNT(*) FROM silver.iowa_businesses WHERE legal_name IS NULL OR legal_name = ''"),
    
    Check("effective_date_plausible", "warn",
          r"""SELECT COUNT(*) FROM silver.iowa_businesses
              WHERE effective_date IS NULL
                 OR effective_date > CURRENT_DATE
                 OR effective_date < DATE '1800-01-01'"""),
    
    Check("state_codes_two_letters", "error",
          r"""SELECT COUNT(*) FROM silver.iowa_businesses
              WHERE (ra_state IS NOT NULL AND ra_state !~ '^[A-Z]{2}$')
                 OR (ho_state IS NOT NULL AND ho_state !~ '^[A-Z]{2}$')"""),
    
    Check("ra_zip_valid_format", "error",
          r"""SELECT COUNT(*) FROM silver.iowa_businesses
              WHERE ra_zip IS NOT NULL AND ra_zip !~ '^[0-9]{5}(-[0-9]{4})?$'"""),

    Check("coordinates_in_range", "error",
          r"""SELECT COUNT(*) FROM silver.iowa_businesses
              WHERE ra_latitude  NOT BETWEEN -90  AND 90
                 OR ho_latitude  NOT BETWEEN -90  AND 90
                 OR ra_longitude NOT BETWEEN -180 AND 180
                 OR ho_longitude NOT BETWEEN -180 AND 180"""),
    
    Check("text_columns_clean", "error",
          r"""SELECT COUNT(*)
              FROM silver.iowa_businesses s,
                   LATERAL (VALUES (s.legal_name), (s.registered_agent), (s.corporation_type),
                                   (s.ra_address_1), (s.ra_city), (s.ho_address_1), (s.ho_city)) v(x)
              WHERE v.x ~ '"' OR v.x ~ '\s\s' OR v.x <> TRIM(v.x)"""),
     
    Check("zip_flag_consistent", "error",
          "SELECT COUNT(*) FROM silver.iowa_businesses WHERE ra_zip_invalidated AND ra_zip IS NOT NULL"),
    
         Check("city_flags_match_corrections", "error",
          r"""SELECT ABS(
                  (SELECT COUNT(*) FILTER (WHERE ho_city_corrected)
                        + COUNT(*) FILTER (WHERE ra_city_corrected)
                   FROM silver.iowa_businesses)
                - (SELECT COALESCE(SUM(row_count), 0) FROM silver.city_corrections
                   WHERE pass <> 'UNRESOLVED_short')
                - (SELECT COALESCE(SUM(row_count), 0) FROM silver.intl_city_corrections
                   WHERE proposed <> original))"""),
     
      Check("short_city_codes_remaining", "warn",
          r"""SELECT COUNT(*) FROM silver.iowa_businesses
              WHERE (ho_country = 'USA' AND ho_city ~ '^[A-Z]{2}$' AND NOT ho_city_corrected)
                 OR (ra_city ~ '^[A-Z]{2}$' AND NOT ra_city_corrected)""",
          max_allowed=2),

    Check("no_split_city_spellings", "warn",
          r"""SELECT COUNT(*) FROM (
                  SELECT 1
                  FROM (SELECT ho_zip, ho_city, COUNT(*) AS n
                        FROM silver.iowa_businesses
                        WHERE ho_country = 'USA' AND ho_zip IS NOT NULL
                        GROUP BY ho_zip, ho_city
                        HAVING COUNT(*) >= 5) t
                  GROUP BY ho_zip, REPLACE(ho_city, ' ', '')
                  HAVING COUNT(*) > 1) g"""),
]


@pytest.mark.parametrize("check", CHECKS, ids=[c.name for c in CHECKS])
def test_silver(session, check):
    violations = session.execute(text(check.sql)).scalar()
    message = f"{check.name}: {violations} violations (allowed {check.max_allowed})"

    if check.severity == "error":
        assert violations <= check.max_allowed, message
    elif violations > check.max_allowed:
        warnings.warn(message)