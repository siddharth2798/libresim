import xml.etree.ElementTree as ET, re
def flat(path):
    root=ET.parse(path).getroot(); out={}
    def walk(e,pre):
        for c in e:
            if not isinstance(c.tag,str): continue
            n=c.tag+(f"[{c.get('n')}]" if c.get("n") not in (None,"0") else "")
            p=pre+"/"+n
            kids=[k for k in c if isinstance(k.tag,str)]
            if kids: walk(c,p)
            elif c.text and c.text.strip():
                t=c.text.strip()
                try: out[p]=float(t) if c.get("type") in ("double","float","int") else (1.0 if t=="true" else 0.0 if t=="false" else float(t))
                except ValueError: pass
    walk(root,"")
    return out
R="/Users/siddharthshivkumar/Documents/tech-projects/libresim/data/raw/fg/a320/"
d=flat(R+"A320-main.xml"); d.update(flat(R+"A320-200-CFM-set.xml"))
print(len(d)); 
for k in list(d)[:5]: print(k,d[k])
print({k:v for k,v in d.items() if "fadec" in k})
