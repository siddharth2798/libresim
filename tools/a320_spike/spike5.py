import subprocess, sys, re, shutil, os
from pathlib import Path
R=Path("/Users/siddharthshivkumar/Documents/tech-projects/libresim/data/raw")
PY="/Users/siddharthshivkumar/Documents/tech-projects/libresim/tools/.venv/bin/python"
root=Path(sys.argv[1]); 
shutil.rmtree(root, ignore_errors=True)
ac=root/"aircraft"/"A320-200-CFM"; (ac/"Systems").mkdir(parents=True)
(root/"engine").symlink_to(R/"jsbsim/src/engine"); (root/"systems").symlink_to(R/"jsbsim/src/systems") if (R/"jsbsim/src/systems").exists() else None
(ac/"FDE").symlink_to(R/"fg/a320/FDE"); (ac/"Engines").symlink_to(R/"fg/a320/Engines")
for p in (R/"fg/a320/Systems").iterdir(): (ac/"Systems"/p.name).symlink_to(p)
fde=(R/"fg/a320/FDE/A320-200-CFM.xml").read_text(encoding="utf-8-sig")
fde=fde.replace('<system file="a320-core"/>','<system file="nasal-stubs"/>\n\t<system file="a320-core"/>',1)
(ac/"A320-200-CFM.xml").write_text(fde)
stubs=[]
def write():
    (ac/"Systems"/"nasal-stubs.xml").write_text('<?xml version="1.0"?>\n<system name="nasal-stubs">\n'+"".join(f'<property value="0">{s}</property>\n' for s in stubs)+'</system>\n')
write()
pat=[re.compile(r"property,? (/?[\w\[\]\-/.]+) specified"), re.compile(r"property (/?[\w\[\]\-/.]+) does not exist"), re.compile(r"property,? (/?[\w\[\]\-/.]+) (?:is undefined|not found|undefined)")]
for i in range(3000):
    r=subprocess.run([PY,"-I","spike5w.py",str(root),"A320-200-CFM"],capture_output=True,text=True)
    out=r.stdout+r.stderr
    if "RUN OK" in out: print("LOADED after",i,"stubs",len(stubs)); break
    m=None
    for p in pat:
        m=p.search(out)
        if m: break
    if not m: print(out[-1500:]); break
    n=m.group(1)
    if n in stubs: print("repeat",n); print(out[-1500:]); break
    stubs.append(n); write()
print(len(stubs)); print(stubs[:60])
