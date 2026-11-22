import pytest
import warnings

from sqlalchemy import text
from typing import NamedTuple

class Check(NamedTuple):
    name: str
    severity: str
    sql: str
    max_allowed: int = 0    