import sys
import pytest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT))

from config.db import get_session

@pytest.fixture(scope="session")
def session():
    s = get_session()
    yield s
    s.close()