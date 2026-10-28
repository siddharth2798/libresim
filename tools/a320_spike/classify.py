import re, glob, collections
import xml.etree.ElementTree as ET
R="/Users/siddharthshivkumar/Documents/tech-projects/libresim/data/raw/fg/a320"
stubs=re.findall(r">([^<]+)</property>", open("root3/aircraft/A320-200-CFM/Systems/nasal-stubs.xml").read())
produced=set()
n=lambda s: s.strip().lstrip("/")
for f in glob.glob(R+"/Systems/*.xml")+glob.glob(R+"/FDE/**/*.xml",recursive=True)+glob.glob(R+"/Engines/*.xml"):
    try: root=ET.parse(f).getroot()
    except: continue
    for e in root.iter():
        if e.tag in("switch","fcs_function","summer","pure_gain","actuator","lag_filter","sensor","scheduled_gain","kinematic","pid","washout_filter","lead_lag_filter","aerosurface_scale","function") and e.get("name"): produced.add(n(e.get("name")))
        if e.tag=="output" and e.text: produced.add(n(e.text))
        if e.tag=="property" and e.get("value") is not None and e.text: produced.add(n(e.text))
by=collections.defaultdict(list)
for s in stubs:
    if n(s) in produced: by["produced-by-JSBSim-system(order only)"].append(s)
    else:
        k=n(s).split("/")[0]; 
        by[k].append(s)
for k,v in sorted(by.items(), key=lambda kv:-len(kv[1])): print(len(v),k, v[:6] if k!="produced-by-JSBSim-system(order only)" else "")
