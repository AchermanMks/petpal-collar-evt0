"""Snapshot current PetPal iOS sources without touching the ESP32 project's dirty tree."""
import hashlib
import json
import shutil
from pathlib import Path

source=Path('/Users/mantashark/pet-collar')
root=Path(__file__).resolve().parents[1]
dest=root/'apps/ios_air8201'
package=root/'apps/PetKit'
if dest.exists() or package.exists(): raise SystemExit('Refusing to overwrite an existing iOS fork')
dest.mkdir(parents=True)
for name in ('PetCollar','PetCollarWidget'):
    shutil.copytree(source/'ios_app'/name,dest/name)
shutil.copytree(source/'ios_app/PetCollar.xcodeproj',dest/'PetPalAir8201G.xcodeproj',
    ignore=shutil.ignore_patterns('xcuserdata'))
package.mkdir()
shutil.copy2(source/'PetKit/Package.swift',package/'Package.swift')
for name in ('Sources','Tests'):
    shutil.copytree(source/'PetKit'/name,package/name)
# Mechanical namespace isolation in the fork only. Keep file/target names for source compatibility.
for parent in (dest,package):
    for p in parent.rglob('*'):
        if p.is_file() and p.suffix in ('.swift','.plist','.entitlements','.pbxproj','.xcscheme'):
            text=p.read_text()
            text=text.replace('com.petcollar.PetCollar','com.petpal.air8201g')
            text=text.replace('group.com.petcollar','group.com.petpal.air8201g')
            text=text.replace('petcollar://','petpalair://')
            if p.suffix=='.plist': text=text.replace('<string>petcollar</string>','<string>petpalair</string>')
            p.write_text(text)
manifest={str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest()
    for parent in (source/'ios_app/PetCollar',source/'ios_app/PetCollarWidget',source/'ios_app/PetCollar.xcodeproj',source/'PetKit/Sources',source/'PetKit/Tests')
    for p in parent.rglob('*') if p.is_file() and 'xcuserdata' not in p.parts}
(dest/'ESP32_SOURCE_SNAPSHOT.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(dest/'PetPalAir8201G.xcodeproj')
print('ESP32 original untouched; source snapshot manifest recorded, including uncommitted UI changes.')
