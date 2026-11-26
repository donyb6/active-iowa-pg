import pytest
import warnings

from sqlalchemy import text
from typing import NamedTuple

class Check(NamedTuple):
    name: str
    severity: str
    sql: str
    max_allowed: int = 0    
    
CHECKS = [
    Check("fact_rows_match_silver", "error",
          r"""SELECT ABS((SELECT COUNT(*) FROM gold.fact_business_entity)
                       - (SELECT COUNT(*) FROM silver.iowa_businesses))"""),

    Check("fact_flags_match_silver", "error",
          r"""SELECT ABS(
                  (SELECT COUNT(*) FILTER (WHERE ho_city_corrected)
                        + COUNT(*) FILTER (WHERE ra_city_corrected)
                        + COUNT(*) FILTER (WHERE ra_zip_invalidated)
                   FROM gold.fact_business_entity)
                - (SELECT COUNT(*) FILTER (WHERE ho_city_corrected)
                        + COUNT(*) FILTER (WHERE ra_city_corrected)
                        + COUNT(*) FILTER (WHERE ra_zip_invalidated)
                   FROM silver.iowa_businesses))"""),
    
    Check("unknown_head_office_matches_silver", "error",
          r"""SELECT ABS(
                  (SELECT COUNT(*) FROM gold.fact_business_entity WHERE ho_location_key = -1)
                - (SELECT COUNT(*) FROM silver.iowa_businesses
                   WHERE ho_country IS NULL AND ho_address_1 IS NULL AND ho_city IS NULL
                     AND ho_state IS NULL AND ho_zip IS NULL))"""),

    Check("iowa_head_offices_match_silver", "error",
          r"""SELECT ABS(
                  (SELECT COUNT(*) FROM gold.fact_business_entity f
                   JOIN gold.dim_location l ON l.location_key = f.ho_location_key
                   WHERE l.region_group = 'IOWA')
                - (SELECT COUNT(*) FROM silver.iowa_businesses
                   WHERE ho_state = 'IA' AND (ho_country = 'USA' OR ho_country IS NULL)))"""),

    Check("grid_matches_ok_coordinates", "error",
          r"""SELECT ABS(
                  (SELECT COALESCE(SUM(entity_count), 0) FROM gold.agg_map_grid
                   WHERE role = 'HEAD_OFFICE')
                - (SELECT COUNT(*) FROM gold.fact_business_entity WHERE ho_coord_status = 'OK'))
               + ABS(
                  (SELECT COALESCE(SUM(entity_count), 0) FROM gold.agg_map_grid
                   WHERE role = 'REGISTERED_AGENT')
                - (SELECT COUNT(*) FROM gold.fact_business_entity WHERE ra_coord_status = 'OK'))"""),

    Check("unused_location_rows", "error",
          r"""SELECT COUNT(*) FROM gold.dim_location l
              WHERE l.location_key <> -1
                AND NOT EXISTS (SELECT 1 FROM gold.fact_business_entity f
                                WHERE f.ho_location_key = l.location_key
                                   OR f.ra_location_key = l.location_key)"""),

    Check("unknown_effective_date", "warn",
          "SELECT COUNT(*) FROM gold.fact_business_entity WHERE effective_date_key = -1"),

    Check("unknown_corporation_type", "warn",
          "SELECT COUNT(*) FROM gold.fact_business_entity WHERE corporation_type_key = -1"),

    Check("unexpected_other_category", "warn",
          r"""SELECT COUNT(*) FROM gold.dim_corporation_type
              WHERE category = 'OTHER' AND corporation_type_key NOT IN (52, 90, 93, 94)"""),

    Check("suspect_head_office_coordinates", "warn",
          "SELECT COUNT(*) FROM gold.fact_business_entity WHERE ho_coord_status = 'SUSPECT'",
          max_allowed=606),

    Check("suspect_agent_coordinates", "warn",
          "SELECT COUNT(*) FROM gold.fact_business_entity WHERE ra_coord_status = 'SUSPECT'",
          max_allowed=564),
]

@pytest.mark.parametrize("check", CHECKS, ids=[c.name for c in CHECKS])
def test_gold(session, check):
    violations = session.execute(text(check.sql)).scalar()
    message = f"{check.name}: {violations} violations (allowed {check.max_allowed})"

    if check.severity == "error":
        assert violations <= check.max_allowed, message
    elif violations > check.max_allowed:
        warnings.warn(message)