import sys,time,hashlib
sys.path.insert(0,'apps/bridge'); import air_bridge
DEV='collar-evt-003'; N=int(sys.argv[1])
# 用法：先停桥（串口独占），再 .venv/bin/python tools/camera_soak.py 300
g=air_bridge.USBGateway(window=16384,prefetch=True,camera_config='sum=crc32 crop=off quality=1')
ok=0;errs=[];hashes=set();sizes=[];gaps=[];t0=time.time();last=t0
for i in range(N):
    try:
        b,_=g.camera_pull(DEV); ok+=1; hashes.add(hashlib.sha256(b).digest()); sizes.append(len(b)); now=time.time(); gaps.append(now-last); last=now
    except Exception as e:
        errs.append(repr(e)[:100]); time.sleep(.5); last=time.time()
el=time.time()-t0
gaps.sort()
print(f"frames ok={ok}/{N} distinct={len(hashes)} errors={len(errs)} elapsed={el:.1f}s fps={ok/el:.2f} size min/avg/max={min(sizes)}/{sum(sizes)//len(sizes)}/{max(sizes)} gap p50={gaps[len(gaps)//2]:.3f} p95={gaps[int(len(gaps)*.95)]:.3f} max={gaps[-1]:.3f} window_end={g.window}")
for e in errs[:5]: print("  err:",e)
print(g.talk('status',('ok ','err '))[:200])
