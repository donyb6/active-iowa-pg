import pytest

from app import queries as q

TOTAL = "SELECT COUNT(*) FROM gold.fact_business_entity"



def scalar(sql):
    return int(q.run(sql).iloc[0, 0])


def test_kpis_total_matches_fact():
    assert int(q.kpis().loc[0, "total_entities"]) == scalar(TOTAL)
    
    
def test_category_share_adds_up():
    assert int(q.category_share()["entities"].sum()) == scalar(TOTAL)
    
    
def test_types_breakdown_adds_up():
    assert int(q.types_breakdown()["entities"].sum()) == scalar(TOTAL)
    

@pytest.mark.parametrize("role", ["HEAD_OFFICE", "REGISTERED_AGENT"])
def test_region_split_adds_up(role):
    assert int(q.region_split(role)["entities"].sum()) == scalar(TOTAL)
    
    
def test_by_year_covers_every_dated_entity():
    dated = scalar("SELECT COUNT(*) FROM gold.fact_business_entity WHERE effective_date_key <> -1")
    assert int(q.entities_by_year(1000, 3000)["entities"].sum()) == dated
    
    
@pytest.mark.parametrize("role,status_col", [("HEAD_OFFICE", "ho_coord_status"), ("REGISTERED_AGENT", "ra_coord_status")])
def test_density_grid_covers_every_ok_coordinate(role, status_col):
    ok = scalar(f"SELECT COUNT(*) FROM gold.fact_business_entity WHERE {status_col} = 'OK'")
    grid = q.density_grid(role, south=-90, north=90, west=-180, east=180)
    assert int(grid["entity_count"].sum()) == ok
    

def test_agent_buckets_cover_every_agent():
    agents = scalar("SELECT COUNT(DISTINCT registered_agent) FROM gold.fact_business_entity")
    assert int(q.agent_size_buckets()["agents"].sum()) == agents
    
    
def test_top_cities_sorted_and_limited():
    df = q.top_cities("HEAD_OFFICE", "IOWA", limit=10)
    assert len(df) <= 10
    assert df["entities"].is_monotonic_decreasing


def test_role_whitelist_rejects_unknown_role():
    with pytest.raises(KeyError):
        q.top_cities("x; DROP TABLE gold.fact_business_entity", "IOWA")