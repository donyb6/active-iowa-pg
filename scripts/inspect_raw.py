import json
from pathlib import Path

project_dir = Path(__file__).resolve().parent.parent

raw_file = project_dir / "data" / "raw" / "active_iowa_business.json"
with raw_file.open(encoding="utf-8") as f:
    rows = [json.loads(line) for line in (f.readline(), f.readline()) if line.strip()]

if rows:
    print(type(rows[0]))
    if isinstance(rows[0], dict):
        print(list(rows[0].keys()))

print("Sample:")
print(json.dumps(rows, indent=2, ensure_ascii=False))