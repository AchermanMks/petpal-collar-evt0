"""Verify original project unchanged and fork UI files byte-identical."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
source=Path('/Users/mantashark/pet-collar')
fork=ROOT/'apps/ios_air8201'
manifest=json.loads((fork/'ESP32_SOURCE_SNAPSHOT.json').read_text())
changed=[p for p,digest in manifest.items() if not (source/p).is_file() or hashlib.sha256((source/p).read_bytes()).hexdigest()!=digest]
assert not changed,f'Original files changed: {changed}'
count=0
for name in ('Features','Theme','Assets.xcassets'):
    old=source/'ios_app/PetCollar'/name
    new=fork/'PetCollar'/name
    before={p.relative_to(old):p.read_bytes() for p in old.rglob('*') if p.is_file()}
    after={p.relative_to(new):p.read_bytes() for p in new.rglob('*') if p.is_file()}
    assert before==after,f'UI changed: {name}'
    count+=len(before)
assert 'RootView()' in (fork/'PetCollar/PetCollarApp.swift').read_text()
assert 'AirRootView' not in (fork/'PetCollar/PetCollarApp.swift').read_text()
print(f'PASS: {len(manifest)} original source hashes unchanged; {count} UI/theme/asset files byte-identical; original root navigation')
