"""Produce a new, non-overwriting LuaTools script bundle. Does not flash a device."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("output",type=Path)
parser.add_argument("--camera",action="store_true",help="Dedicated camera profile, exclusive I2C1")
parser.add_argument("--profile",help="Use firmware/wearable-evt0/config.<PROFILE>.lua as config.lua (e.g. board1)")
args=parser.parse_args()
dest=args.output.resolve()
if dest.exists():
    raise SystemExit(f"Refusing to overwrite existing bundle: {dest}")
src=ROOT/"firmware/wearable-evt0"
dest.mkdir(parents=True)
for p in sorted(src.glob("*.lua")):
    if not p.name.startswith("config"):
        shutil.copy2(p,dest/p.name)
shutil.copy2(src/"config.example.lua",dest/"bench_defaults.lua")
shutil.copy2(src/(f"config.{args.profile}.lua" if args.profile else "config.camera.lua" if args.camera else "config.bench.lua"),dest/"config.lua")
for p in sorted((src/"libs").glob("*.lua"))+sorted((src/"libs").glob("pins_*.json")):
    shutil.copy2(p,dest/p.name) # pins json: I2C0 for the ES8311 codec sits on a muxed pad
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.glob("*.lua"))}
(dest/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
with zipfile.ZipFile(dest.with_suffix(".zip"),"x",zipfile.ZIP_DEFLATED) as z:
    for p in sorted(dest.iterdir()): z.write(p,p.name)
print(f"Built {len(manifest)} Lua files, {sum(p.stat().st_size for p in dest.glob('*.lua'))} bytes: {dest}")
print("LuaTools: use the existing V2030_Air780EGH_1 core; add ALL .lua files, config.lua and libs included.")
print(f"Profile: {args.profile or ('camera' if args.camera else 'bench')} -> see config.lua for enabled features.")
