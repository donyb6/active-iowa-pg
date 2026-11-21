import yaml
import requests
import zipfile
from pathlib import Path

project_dir = Path(__file__).resolve().parent.parent

with open(project_dir / "config" / "data.yaml") as f:
    cfg = yaml.safe_load(f)

raw_dir = Path(cfg["storage"]["raw_dir"])
if not raw_dir.is_absolute():
    raw_dir = project_dir / raw_dir
raw_dir.mkdir(parents=True, exist_ok=True)
zip_path = raw_dir / cfg["storage"]["archive_filename"]

with requests.get(cfg["source"]["url"], stream=True, timeout=cfg["source"]["timeout_sec"]) as r:
    r.raise_for_status()
    with open(zip_path, "wb") as f:
        for chunk in r.iter_content(chunk_size=1024 * 1024):
            f.write(chunk)

with zipfile.ZipFile(zip_path) as z:
    print(z.namelist())
    z.extractall(raw_dir)

print("Done:", raw_dir / cfg["storage"]["extracted_filename"]) 