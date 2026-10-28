"""Print a compact summary of the <animation> elements of FlightGear model XML files (data only,
parsed with ElementTree; nothing in the files is executed). Used to find hinge centres / axes.
Usage: python -I tools/blender/fg_anim_summary.py <model.xml> [filter-substring]"""
import sys
import xml.etree.ElementTree as ET


def flat(e):
    if e is None:
        return ""
    return " ".join(f"{c.tag}={c.text.strip()}" for c in e if c.text and c.text.strip())


def main():
    root = ET.parse(sys.argv[1]).getroot()
    flt = sys.argv[2] if len(sys.argv) > 2 else ""
    for a in root.iter("animation"):
        objs = [o.text.strip() for o in a.findall("object-name") if o.text]
        t = (a.findtext("type") or "").strip()
        if flt and flt not in " ".join(objs) + t:
            continue
        prop = (a.findtext("property") or "").strip()
        tab = a.find("interpolation")
        tabs = ""
        if tab is not None:
            tabs = " ".join(f"{e.findtext('ind', '').strip()}:{e.findtext('dep', '').strip()}" for e in tab.findall("entry"))
        print(f"{t} {','.join(objs)} | prop={prop} fac={(a.findtext('factor') or '').strip()} "
              f"offs={(a.findtext('offset-deg') or '').strip()} min={(a.findtext('min-deg') or '').strip()} max={(a.findtext('max-deg') or '').strip()} "
              f"| c[{flat(a.find('center'))}] a[{flat(a.find('axis'))}] tab[{tabs}]")


main()
