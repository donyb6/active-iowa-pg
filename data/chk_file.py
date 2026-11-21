import os
p = "data/raw/active_iowa_businesses.json"
print(os.path.getsize(p) / 1e6, "MB")
with open(p) as f:
    print(f.read(600))