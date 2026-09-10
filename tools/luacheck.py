import lupa, glob, sys
L = lupa.LuaRuntime()
load = L.eval("function(src, name) local f, e = load(src, name) return f ~= nil, e end")
bad = 0
for p in sorted(glob.glob("firmware/wearable-evt0/*.lua") + glob.glob("firmware/wearable-evt0/libs/*.lua")):
    ok, err = load(open(p, encoding="utf-8").read(), "=" + p)
    print(("OK   " if ok else "FAIL ") + p + ("" if ok else "  " + str(err)))
    bad += 0 if ok else 1
sys.exit(bad)
