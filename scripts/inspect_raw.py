import yaml
from pathlib import Path

project_dir = Path(__file__).resolve().parent.parent

with (project_dir / "config" / "data.yaml").open(encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

raw_dir = Path(cfg["storage"]["raw_dir"])
if not raw_dir.is_absolute():
    raw_dir = project_dir / raw_dir
p = raw_dir / cfg["storage"]["extracted_filename"]

with open(p, encoding="utf-8") as f:
    first = f.readline()
    second = f.readline()


print(first[:80])
print(second[:80])
print("size MB:", p.stat().st_size / 1e6)