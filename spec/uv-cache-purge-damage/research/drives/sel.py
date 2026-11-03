# sel.py MODE DIR [ARG]: print files (not dirs; symlinks count as files) under DIR to delete.
import os, sys, random
mode, d = sys.argv[1], sys.argv[2]
files = []
for r, ds, fs in os.walk(d):
    for n in fs + [x for x in ds if os.path.islink(os.path.join(r, x))]:
        files.append(os.path.join(r, n))
files.sort()
if mode == "random":
    random.seed(int(sys.argv[3])); k = max(1, len(files) * 3 // 10)
    out = random.sample(files, k)
elif mode == "newest":
    files.sort(key=lambda p: (os.lstat(p).st_mtime_ns, p)); out = files[-max(1, len(files) * 3 // 10):]
elif mode == "all":
    out = files
for p in out: print(p)
