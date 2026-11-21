import yaml
import requests
from pathlib import Path

with open("data.yaml") as f:
    cfg = yaml.safe_load(f)

raw_dir = Path(cfg["storage"]["raw_dir"])
raw_dir.mkdir(parents=True, exist_ok=True)
out = raw_dir / cfg["storage"]["raw_dir"]

with requests.get(cfg["source"]["url"]):
    