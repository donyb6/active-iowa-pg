import os, sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlalchemy import text
from config.db import get_session

s = get_session()
print(s.execute(text("SELECT 38")).scalar())
s.close()