import yaml
import requests
from pathlib import Path

project_dir = Path(__file__).resolve().parent.parent

with open(project_dir / "data" / "data.yaml") as f:
    cfg = yaml.safe_load(f)

raw_dir = Path(cfg["storage"]["raw_dir"])
if not raw_dir.is_absolute():
    raw_dir = project_dir / raw_dir
raw_dir.mkdir(parents=True, exist_ok=True)
out = raw_dir / cfg["storage"]["file_name"]

with requests.get(cfg["source"]["url"], stream=True, timeout=cfg["source"]["timeout_sec"]) as r:
    r.raise_for_status()
    with open(out, "wb") as f:
        for chunk in r.iter_content(chunk_size=1024 * 1024):
            f.write(chunk)

print(f"Saved to {out}")    
    