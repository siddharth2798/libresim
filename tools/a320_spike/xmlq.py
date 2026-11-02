"""Throwaway: print elements whose name matches a substring. usage: xmlq.py file.xml substr [maxchars]"""
import sys, re, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
n = int(sys.argv[3]) if len(sys.argv) > 3 else 700
for e in r.iter():
    nm = e.get("name") if isinstance(e.tag, str) else None
    if nm and sys.argv[2] in nm:
        print(re.sub(r"\s+", " ", ET.tostring(e, encoding="unicode"))[:n]); print()
